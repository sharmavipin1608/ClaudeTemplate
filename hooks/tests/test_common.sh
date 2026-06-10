#!/bin/bash
# Tests for hooks/lib/common.sh: worktree-safe root resolution and
# pipeline_state.json context readers.
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
        mkdir -p hooks/lib
        cp "$PROJECT_ROOT/hooks/lib/common.sh" hooks/lib/
        git add . && git commit -q -m "init"
    )
    echo "$tmpdir"
}

# Test 1: PROJECT_ROOT is the repo root even from a subdirectory
DIR=$(setup_repo)
mkdir -p "$DIR/src/deep"
GOT=$(cd "$DIR/src/deep" && source ../../hooks/lib/common.sh && echo "$PROJECT_ROOT")
assert_eq "root resolved from subdirectory" "$(cd "$DIR" && pwd -P)" "$GOT"

# Test 2: inside a git worktree, PROJECT_ROOT is the MAIN repo root
DIR=$(setup_repo)
(cd "$DIR" && git worktree add -q wt -b test-wt)
GOT=$(cd "$DIR/wt" && source hooks/lib/common.sh && echo "$PROJECT_ROOT")
assert_eq "worktree resolves to main root" "$(cd "$DIR" && pwd -P)" "$GOT"

# Test 3: context readers from a running pipeline state
DIR=$(setup_repo)
cat > "$DIR/pipeline_state.json" <<'EOF'
{"task_id":"TASK-007","pipeline":"full","run_id":"abc-123","current_step":"coder","completed_steps":["researcher"],"status":"running"}
EOF
GOT=$(cd "$DIR" && source hooks/lib/common.sh && current_agent)
assert_eq "current_agent reads current_step when running" "coder" "$GOT"
GOT=$(cd "$DIR" && source hooks/lib/common.sh && current_task_id)
assert_eq "current_task_id reads task_id when running" "TASK-007" "$GOT"
GOT=$(cd "$DIR" && source hooks/lib/common.sh && current_run_id)
assert_eq "current_run_id reads run_id" "abc-123" "$GOT"

# Test 4: env var overrides state (test/manual escape hatch)
GOT=$(cd "$DIR" && CLAUDE_CURRENT_AGENT=tester bash -c 'source hooks/lib/common.sh && current_agent')
assert_eq "CLAUDE_CURRENT_AGENT env overrides state" "tester" "$GOT"

# Test 5: completed pipeline → no current agent/task
python3 - <<EOF
import json
d = json.load(open("$DIR/pipeline_state.json")); d["status"] = "completed"
json.dump(d, open("$DIR/pipeline_state.json", "w"))
EOF
GOT=$(cd "$DIR" && source hooks/lib/common.sh && current_agent)
assert_eq "no agent when pipeline completed" "" "$GOT"

# Test 6: missing state file → empty strings, no crash
rm -f "$DIR/pipeline_state.json"
GOT=$(cd "$DIR" && source hooks/lib/common.sh && current_task_id)
assert_eq "no task when state file missing" "" "$GOT"
GOT=$(cd "$DIR" && source hooks/lib/common.sh && current_run_id)
assert_eq "no run_id when state file missing" "" "$GOT"

# Test 7: sourcing creates the per-project tmp dir
DIR=$(setup_repo)
(cd "$DIR" && source hooks/lib/common.sh)
if [ -d "$DIR/.claude/tmp" ]; then
    echo "PASS: CLAUDE_TMP_DIR created"; PASS=$((PASS+1))
else
    echo "FAIL: .claude/tmp not created"; FAIL=$((FAIL+1))
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
