#!/bin/bash
# on_error.sh (Stop hook): always clears idle timestamps; when a pipeline
# is still 'running' at stop, appends ONE recovery note per run_id.
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
        mkdir -p hooks/lib memory logs .claude/tmp
        cp "$PROJECT_ROOT/hooks/on_error.sh" hooks/
        cp "$PROJECT_ROOT/hooks/lib/common.sh" hooks/lib/
        echo "# Scratchpad" > memory/scratchpad.md
        git add . && git commit -q -m "init"
    )
    echo "$tmpdir"
}

# Test 1: idle timestamps cleared on every stop
DIR=$(setup_repo)
echo "123" > "$DIR/.claude/tmp/last_tool_coder"
(cd "$DIR" && echo '{}' | bash hooks/on_error.sh)
if [ -f "$DIR/.claude/tmp/last_tool_coder" ]; then
    echo "FAIL: idle timestamp survived stop"; FAIL=$((FAIL+1))
else
    echo "PASS: idle timestamps cleared on stop"; PASS=$((PASS+1))
fi

# Test 2: running pipeline → recovery note in scratchpad + STOP line in log
DIR=$(setup_repo)
cat > "$DIR/pipeline_state.json" <<'EOF'
{"task_id":"TASK-005","pipeline":"full","run_id":"r9","current_step":"tester","completed_steps":["researcher","coder","reviewer"],"status":"running"}
EOF
(cd "$DIR" && echo '{}' | bash hooks/on_error.sh)
if grep -q "TASK-005" "$DIR/memory/scratchpad.md" && grep -q "tester" "$DIR/memory/scratchpad.md"; then
    echo "PASS: recovery note written to scratchpad"; PASS=$((PASS+1))
else
    echo "FAIL: no recovery note in scratchpad"; FAIL=$((FAIL+1))
fi
if grep -q "pipeline_incomplete" "$DIR/logs/tool_calls.log"; then
    echo "PASS: STOP line logged"; PASS=$((PASS+1))
else
    echo "FAIL: no STOP line in tool_calls.log"; FAIL=$((FAIL+1))
fi

# Test 3: second stop for the same run does not duplicate the note
BEFORE=$(grep -c "TASK-005" "$DIR/memory/scratchpad.md")
(cd "$DIR" && echo '{}' | bash hooks/on_error.sh)
AFTER=$(grep -c "TASK-005" "$DIR/memory/scratchpad.md")
if [ "$BEFORE" = "$AFTER" ]; then
    echo "PASS: note deduped per run_id"; PASS=$((PASS+1))
else
    echo "FAIL: duplicate recovery note"; FAIL=$((FAIL+1))
fi

# Test 4: completed pipeline → no note
DIR=$(setup_repo)
cat > "$DIR/pipeline_state.json" <<'EOF'
{"task_id":"TASK-006","pipeline":"full","run_id":"r10","current_step":null,"completed_steps":["researcher"],"status":"completed"}
EOF
(cd "$DIR" && echo '{}' | bash hooks/on_error.sh)
if grep -q "TASK-006" "$DIR/memory/scratchpad.md"; then
    echo "FAIL: note written for completed pipeline"; FAIL=$((FAIL+1))
else
    echo "PASS: no note for completed pipeline"; PASS=$((PASS+1))
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
