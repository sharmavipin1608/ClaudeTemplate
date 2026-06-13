#!/bin/bash
# Tests for log_tool.sh: PreToolUse-only flat logging, state-file agent
# context, pipeline.jsonl tool_call events, worktree-safe central logging.
set -euo pipefail

PASS=0; FAIL=0
PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CLEANUP_DIRS=()
trap 'rm -rf "${CLEANUP_DIRS[@]:-}"' EXIT

assert_eq() {
    local name="$1" expected="$2" actual="$3"
    if [ "$actual" = "$expected" ]; then
        echo "PASS: $name"; PASS=$((PASS+1))
    else
        echo "FAIL: $name — expected '$expected', got '$actual'"; FAIL=$((FAIL+1))
    fi
}

setup_repo() {
    local tmpdir
    tmpdir=$(mktemp -d)
    CLEANUP_DIRS+=("$tmpdir")
    (
        cd "$tmpdir"
        git init -q
        git config user.email "test@test.com"
        git config user.name "Test"
        mkdir -p hooks/lib logs
        cp "$PROJECT_ROOT/hooks/log_tool.sh" hooks/
        cp "$PROJECT_ROOT/hooks/lib/common.sh" hooks/lib/
        git add . && git commit -q -m "init"
    )
    echo "$tmpdir"
}

# Test 1: PreToolUse event appends exactly one flat line
DIR=$(setup_repo)
(cd "$DIR" && echo '{"tool_name":"Bash","hook_event_name":"PreToolUse"}' | bash hooks/log_tool.sh)
assert_eq "PreToolUse logs one line" "1" "$(wc -l < "$DIR/logs/tool_calls.log" | tr -d ' ')"

# Test 2: PostToolUse event appends nothing
(cd "$DIR" && echo '{"tool_name":"Bash","hook_event_name":"PostToolUse"}' | bash hooks/log_tool.sh)
assert_eq "PostToolUse logs nothing" "1" "$(wc -l < "$DIR/logs/tool_calls.log" | tr -d ' ')"

# Test 3: no pipeline running → no tool_call event
if [ -f "$DIR/logs/pipeline.jsonl" ] && grep -q tool_call "$DIR/logs/pipeline.jsonl" 2>/dev/null; then
    echo "FAIL: tool_call event written without active pipeline"; FAIL=$((FAIL+1))
else
    echo "PASS: no tool_call event without active pipeline"; PASS=$((PASS+1))
fi

# Test 4: running pipeline → tool_call event with agent + run_id from state file
# agent_active:true is required so current_agent() returns current_step ("coder")
# rather than "orchestrator" (the fallback when no agent is actively dispatched).
cat > "$DIR/pipeline_state.json" <<'EOF'
{"task_id":"TASK-009","pipeline":"full","run_id":"run-xyz","current_step":"coder","completed_steps":[],"status":"running","agent_active":true}
EOF
(cd "$DIR" && echo '{"tool_name":"Edit","hook_event_name":"PreToolUse"}' | bash hooks/log_tool.sh)
LAST=$(tail -1 "$DIR/logs/pipeline.jsonl")
assert_eq "event is tool_call" "tool_call" "$(echo "$LAST" | python3 -c 'import json,sys; print(json.load(sys.stdin)["event"])')"
assert_eq "agent from state file" "coder" "$(echo "$LAST" | python3 -c 'import json,sys; print(json.load(sys.stdin)["agent"])')"
assert_eq "run_id from state file" "run-xyz" "$(echo "$LAST" | python3 -c 'import json,sys; print(json.load(sys.stdin)["run_id"])')"
assert_eq "task_id from state file" "TASK-009" "$(echo "$LAST" | python3 -c 'import json,sys; print(json.load(sys.stdin)["task_id"])')"

# Test 5: idle timestamp written to .claude/tmp
if [ -f "$DIR/.claude/tmp/last_tool_coder" ]; then
    echo "PASS: idle timestamp at .claude/tmp/last_tool_coder"; PASS=$((PASS+1))
else
    echo "FAIL: idle timestamp not at .claude/tmp/last_tool_coder"; FAIL=$((FAIL+1))
fi

# Test 6: from inside a worktree, events land in the MAIN repo's logs
(cd "$DIR" && git add -A && git commit -q -m "wip" && git worktree add -q wt -b test-wt)
rm -f "$DIR/wt/logs/pipeline.jsonl"
BEFORE=$(wc -l < "$DIR/logs/pipeline.jsonl" | tr -d ' ')
(cd "$DIR/wt" && echo '{"tool_name":"Write","hook_event_name":"PreToolUse"}' | bash hooks/log_tool.sh)
AFTER=$(wc -l < "$DIR/logs/pipeline.jsonl" | tr -d ' ')
assert_eq "worktree call appends to MAIN pipeline.jsonl" "$((BEFORE + 1))" "$AFTER"
if [ -f "$DIR/wt/logs/pipeline.jsonl" ]; then
    echo "FAIL: worktree got its own pipeline.jsonl"; FAIL=$((FAIL+1))
else
    echo "PASS: no fragmented log in the worktree"; PASS=$((PASS+1))
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
