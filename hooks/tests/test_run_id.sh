#!/bin/bash
# Integration tests for run_id propagation across pipeline hooks.
set -euo pipefail

PASS=0; FAIL=0
PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CLEANUP_DIRS=()
trap 'rm -rf "${CLEANUP_DIRS[@]:-}"' EXIT

setup_repo() {
    local tmpdir
    tmpdir=$(mktemp -d)
    CLEANUP_DIRS+=("$tmpdir")
    (
        cd "$tmpdir"
        git init -q
        git config user.email "test@test.com"
        git config user.name "Test"
        mkdir -p logs hooks/lib
        cat > TASKS.md <<'TASKS'
### [TASK-001] Fix button label
**Status:** in_progress
**Priority:** low
**Tags:** [ui]
TASKS
        git add TASKS.md && git commit -q -m "init"
        cp "$PROJECT_ROOT/hooks/init_pipeline_state.sh" hooks/
        cp "$PROJECT_ROOT/hooks/log_agent.sh"           hooks/
        cp "$PROJECT_ROOT/hooks/log_tool.sh"            hooks/
        cp "$PROJECT_ROOT/hooks/classify_task.sh"       hooks/
        cp "$PROJECT_ROOT/hooks/lib/common.sh"          hooks/lib/
        git add hooks/ && git commit -q -m "add hooks"
    )
    echo "$tmpdir"
}

assert_true() {
    local name="$1" result="$2"
    if [ "$result" = "true" ]; then
        echo "PASS: $name"; PASS=$((PASS+1))
    else
        echo "FAIL: $name"; FAIL=$((FAIL+1))
    fi
}

assert_exit() {
    local name="$1" expected="$2" actual="$3"
    if [ "$actual" -eq "$expected" ]; then
        echo "PASS: $name"; PASS=$((PASS+1))
    else
        echo "FAIL: $name — expected exit $expected, got $actual"; FAIL=$((FAIL+1))
    fi
}

# ── Test 1: init_pipeline_state.sh writes run_id ──────────────────────
DIR=$(setup_repo)
(cd "$DIR" && bash hooks/init_pipeline_state.sh TASK-001 full)
RUN_ID=$(python3 -c "import json; d=json.load(open('$DIR/pipeline_state.json')); print(d.get('run_id',''))" 2>/dev/null || echo "")
if [ -n "$RUN_ID" ]; then
    assert_true "init writes non-empty run_id" "true"
else
    assert_true "init writes non-empty run_id" "false"
fi

# ── Test 2: two consecutive init calls produce different run_ids ───────
DIR=$(setup_repo)
(cd "$DIR" && bash hooks/init_pipeline_state.sh TASK-001 full)
RUN_ID_1=$(python3 -c "import json; d=json.load(open('$DIR/pipeline_state.json')); print(d.get('run_id',''))")
(cd "$DIR" && bash hooks/init_pipeline_state.sh TASK-001 full)
RUN_ID_2=$(python3 -c "import json; d=json.load(open('$DIR/pipeline_state.json')); print(d.get('run_id',''))")
if [ "$RUN_ID_1" != "$RUN_ID_2" ] && [ -n "$RUN_ID_1" ] && [ -n "$RUN_ID_2" ]; then
    assert_true "two consecutive inits produce different run_ids" "true"
else
    assert_true "two consecutive inits produce different run_ids" "false"
fi

# ── Test 3: log_agent.sh START includes run_id in pipeline.jsonl ──────
DIR=$(setup_repo)
(cd "$DIR" && bash hooks/init_pipeline_state.sh TASK-001 full)
(cd "$DIR" && bash hooks/log_agent.sh coder START TASK-001 full)
LAST_LINE=$(tail -1 "$DIR/logs/pipeline.jsonl")
HAS_RUN_ID=$(python3 -c "import json,sys; d=json.loads('$LAST_LINE'); print('true' if 'run_id' in d and d['run_id'] else 'false')" 2>/dev/null || echo "false")
assert_true "log_agent START includes run_id" "$HAS_RUN_ID"

# ── Test 4: log_agent.sh END includes run_id in pipeline.jsonl ────────
DIR=$(setup_repo)
(cd "$DIR" && bash hooks/init_pipeline_state.sh TASK-001 full)
(cd "$DIR" && bash hooks/log_agent.sh coder END TASK-001 DONE reviewer - 0)
LAST_LINE=$(tail -1 "$DIR/logs/pipeline.jsonl")
HAS_RUN_ID=$(python3 -c "import json,sys; d=json.loads('$LAST_LINE'); print('true' if 'run_id' in d and d['run_id'] else 'false')" 2>/dev/null || echo "false")
assert_true "log_agent END includes run_id" "$HAS_RUN_ID"

# ── Test 5: log_tool.sh with CLAUDE_TASK_ID set includes run_id ───────
DIR=$(setup_repo)
(cd "$DIR" && bash hooks/init_pipeline_state.sh TASK-001 full)
(cd "$DIR" && CLAUDE_TASK_ID=TASK-001 CLAUDE_CURRENT_AGENT=coder \
    bash hooks/log_tool.sh <<< '{"tool_name":"Read"}')
LAST_LINE=$(tail -1 "$DIR/logs/pipeline.jsonl")
HAS_RUN_ID=$(python3 -c "import json,sys; d=json.loads('$LAST_LINE'); print('true' if 'run_id' in d and d['run_id'] else 'false')" 2>/dev/null || echo "false")
assert_true "log_tool with CLAUDE_TASK_ID includes run_id" "$HAS_RUN_ID"

# ── Test 6: log_agent.sh without pipeline_state.json does not fail ────
DIR=$(setup_repo)
# No init_pipeline_state.sh call — pipeline_state.json does not exist
(cd "$DIR" && bash hooks/log_agent.sh coder START TASK-001 full 2>/dev/null) && EXIT=0 || EXIT=$?
assert_exit "log_agent without pipeline_state.json exits 0" 0 "$EXIT"

# ── Test 7: log_tool.sh without pipeline_state.json does not fail ─────
DIR=$(setup_repo)
(cd "$DIR" && CLAUDE_TASK_ID=TASK-001 CLAUDE_CURRENT_AGENT=coder \
    bash hooks/log_tool.sh <<< '{"tool_name":"Read"}' 2>/dev/null) && EXIT=0 || EXIT=$?
assert_exit "log_tool without pipeline_state.json exits 0" 0 "$EXIT"

# ── Test 8: log_agent.sh without pipeline_state.json omits run_id field ─
DIR=$(setup_repo)
(cd "$DIR" && bash hooks/log_agent.sh coder START TASK-001 full 2>/dev/null)
LAST_LINE=$(tail -1 "$DIR/logs/pipeline.jsonl")
HAS_RUN_ID=$(python3 -c "import json; d=json.loads('$LAST_LINE'); print('true' if 'run_id' in d else 'false')" 2>/dev/null || echo "false")
assert_true "log_agent without pipeline_state.json omits run_id" "$([ "$HAS_RUN_ID" = "false" ] && echo true || echo false)"

# ── Test 9: All event types in a single run share the same run_id ──────
DIR=$(setup_repo)
(cd "$DIR" && bash hooks/init_pipeline_state.sh TASK-001 full)
STATE_RUN_ID=$(python3 -c "import json; d=json.load(open('$DIR/pipeline_state.json')); print(d.get('run_id',''))")
(cd "$DIR" && bash hooks/log_agent.sh coder START TASK-001 full)
(cd "$DIR" && CLAUDE_TASK_ID=TASK-001 CLAUDE_CURRENT_AGENT=coder \
    bash hooks/log_tool.sh <<< '{"tool_name":"Read"}')
(cd "$DIR" && bash hooks/log_agent.sh coder END TASK-001 DONE reviewer - 0)
ALL_MATCH=$(python3 -c "
import json, sys
state_run_id = '$STATE_RUN_ID'
mismatches = []
with open('$DIR/logs/pipeline.jsonl') as f:
    for i, line in enumerate(f):
        line = line.strip()
        if not line:
            continue
        try:
            d = json.loads(line)
        except json.JSONDecodeError:
            mismatches.append(f'line {i+1}: not valid JSON')
            continue
        if 'run_id' in d:
            if d['run_id'] != state_run_id:
                mismatches.append(f'line {i+1}: run_id={d[\"run_id\"]} != {state_run_id}')
print('true' if not mismatches else 'false')
" 2>/dev/null || echo "false")
assert_true "all events in a single run share the same run_id" "$ALL_MATCH"

# ── Test 10: classify_task.sh classifier event includes run_id ─────────
DIR=$(setup_repo)
(cd "$DIR" && bash hooks/init_pipeline_state.sh TASK-001 full)
STATE_RUN_ID=$(python3 -c "import json; d=json.load(open('$DIR/pipeline_state.json')); print(d.get('run_id',''))")
# Clear any cached classifier verdict so classify_task.sh runs fresh
rm -f /tmp/task_mode /tmp/task_mode_hash
# Add an untracked file to trigger the "new file(s) created" FORCE_FULL rule
(cd "$DIR" && touch newfile.py && bash hooks/classify_task.sh <<< '{"tool_name":"Write"}')
CLASSIFIER_RUN_ID=$(python3 -c "
import json
lines = open('$DIR/logs/pipeline.jsonl').readlines()
for line in reversed(lines):
    line = line.strip()
    if not line:
        continue
    try:
        d = json.loads(line)
    except json.JSONDecodeError:
        continue
    if d.get('event') == 'classifier' and 'run_id' in d:
        print(d['run_id'])
        break
" 2>/dev/null || echo "")
if [ -n "$CLASSIFIER_RUN_ID" ] && [ "$CLASSIFIER_RUN_ID" = "$STATE_RUN_ID" ]; then
    assert_true "classify_task classifier event includes run_id" "true"
else
    assert_true "classify_task classifier event includes run_id" "false"
fi

# ── Test 11: validate_output.sh envelope record includes run_id ────────
DIR=$(setup_repo)
(cd "$DIR" && mkdir -p hooks contracts)
(cd "$DIR" && cp "$PROJECT_ROOT/hooks/validate_output.sh" hooks/)
(cd "$DIR" && cp -r "$PROJECT_ROOT/contracts/." contracts/)
(cd "$DIR" && bash hooks/init_pipeline_state.sh TASK-001 full)
STATE_RUN_ID=$(python3 -c "import json; d=json.load(open('$DIR/pipeline_state.json')); print(d.get('run_id',''))")
VALID_ENVELOPE='{"task_id":"TASK-001","agent":"reviewer","verdict":"PASS","payload":{},"next_agent":"tester","reason":null,"timestamp":"2026-06-10T00:00:00Z"}'
(cd "$DIR" && echo "$VALID_ENVELOPE" | bash hooks/validate_output.sh reviewer 2>/dev/null)
VALIDATE_RUN_ID=$(python3 -c "
import json
lines = open('$DIR/logs/pipeline.jsonl').readlines()
for line in reversed(lines):
    line = line.strip()
    if not line:
        continue
    try:
        d = json.loads(line)
    except json.JSONDecodeError:
        continue
    if 'run_id' in d:
        print(d['run_id'])
        break
" 2>/dev/null || echo "")
if [ -n "$VALIDATE_RUN_ID" ] && [ "$VALIDATE_RUN_ID" = "$STATE_RUN_ID" ]; then
    assert_true "validate_output envelope record includes run_id" "true"
else
    assert_true "validate_output envelope record includes run_id" "false"
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
