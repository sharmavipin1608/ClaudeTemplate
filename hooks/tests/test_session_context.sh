#!/bin/bash
# session_context.sh must print memory context and the pipeline recovery
# hint to STDOUT (SessionStart stdout is injected into model context;
# stderr is not — that was the original bug).
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
        mkdir -p hooks/lib memory
        cp "$PROJECT_ROOT/hooks/session_context.sh" hooks/
        cp "$PROJECT_ROOT/hooks/lib/common.sh" hooks/lib/
        git add . && git commit -q -m "init"
    )
    echo "$tmpdir"
}

assert_stdout_contains() {
    local name="$1" pattern="$2" output="$3"
    if echo "$output" | grep -qF "$pattern"; then
        echo "PASS: $name"; PASS=$((PASS+1))
    else
        echo "FAIL: $name — expected '$pattern' in stdout"; FAIL=$((FAIL+1))
    fi
}

# Test 1: core.md content goes to STDOUT (not stderr)
DIR=$(setup_repo)
echo "PROJECT-CORE-SENTINEL" > "$DIR/memory/core.md"
OUT=$(cd "$DIR" && echo '{}' | bash hooks/session_context.sh 2>/dev/null)
assert_stdout_contains "core.md on stdout" "PROJECT-CORE-SENTINEL" "$OUT"
ERR=$(cd "$DIR" && echo '{}' | bash hooks/session_context.sh 2>&1 >/dev/null)
if [ -z "$ERR" ]; then
    echo "PASS: nothing on stderr"; PASS=$((PASS+1))
else
    echo "FAIL: unexpected stderr: $ERR"; FAIL=$((FAIL+1))
fi

# Test 2: recovery hint on stdout when a pipeline is mid-run
cat > "$DIR/pipeline_state.json" <<'EOF'
{"task_id":"TASK-003","pipeline":"full","run_id":"r1","current_step":"coder","completed_steps":["researcher"],"status":"running"}
EOF
OUT=$(cd "$DIR" && echo '{}' | bash hooks/session_context.sh 2>/dev/null)
assert_stdout_contains "recovery block present" "PIPELINE RECOVERY" "$OUT"
assert_stdout_contains "recovery names the step" "coder" "$OUT"
assert_stdout_contains "recovery names the task" "TASK-003" "$OUT"

# Test 3: no crash and no recovery block when state is completed
python3 - <<EOF
import json
d = json.load(open("$DIR/pipeline_state.json")); d["status"] = "completed"
json.dump(d, open("$DIR/pipeline_state.json", "w"))
EOF
OUT=$(cd "$DIR" && echo '{}' | bash hooks/session_context.sh 2>/dev/null)
if echo "$OUT" | grep -q "PIPELINE RECOVERY"; then
    echo "FAIL: recovery block shown for completed pipeline"; FAIL=$((FAIL+1))
else
    echo "PASS: no recovery block when completed"; PASS=$((PASS+1))
fi

# Test 4: small/missing memory files are skipped without error
DIR=$(setup_repo)
(cd "$DIR" && echo '{}' | bash hooks/session_context.sh 2>/dev/null) || { echo "FAIL: crashed on empty memory"; FAIL=$((FAIL+1)); false; }
echo "PASS: runs cleanly with no memory files"; PASS=$((PASS+1))

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
