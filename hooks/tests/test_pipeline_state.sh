#!/bin/bash
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
        mkdir -p hooks/lib
        cp "$PROJECT_ROOT/hooks/init_pipeline_state.sh" hooks/
        cp "$PROJECT_ROOT/hooks/advance_pipeline_state.sh" hooks/
        cp "$PROJECT_ROOT/hooks/lib/common.sh" hooks/lib/
        git add . && git commit -q -m "init"
    )
    echo "$tmpdir"
}

assert_field() {
    local name="$1" dir="$2" field="$3" expected="$4"
    local actual
    actual=$(python3 -c "
import json, sys
try:
    d = json.load(open('$dir/pipeline_state.json'))
    v = d.get('$field')
    print(v if v is not None else 'None')
except Exception as e:
    print('MISSING', file=sys.stderr)
    sys.exit(1)
" 2>/dev/null || echo "MISSING")
    if [ "$actual" = "$expected" ]; then
        echo "PASS: $name"; PASS=$((PASS+1))
    else
        echo "FAIL: $name — expected $field='$expected', got '$actual'"; FAIL=$((FAIL+1))
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

# Test 1: Init full pipeline → current_step=researcher, status=running
DIR=$(setup_repo)
(cd "$DIR" && bash hooks/init_pipeline_state.sh TASK-001 full)
assert_field "full pipeline starts at researcher" "$DIR" "current_step" "researcher"
assert_field "full pipeline status is running"   "$DIR" "status"       "running"
assert_field "full pipeline task_id recorded"    "$DIR" "task_id"      "TASK-001"
assert_field "full pipeline name recorded"       "$DIR" "pipeline"     "full"

# Test 2: Init fast-track pipeline → current_step=coder
DIR=$(setup_repo)
(cd "$DIR" && bash hooks/init_pipeline_state.sh TASK-002 fast-track)
assert_field "fast-track starts at coder"         "$DIR" "current_step" "coder"
assert_field "fast-track pipeline name recorded"  "$DIR" "pipeline"     "fast-track"

# Test 3: Advance updates current_step and completed_steps
DIR=$(setup_repo)
(cd "$DIR" && bash hooks/init_pipeline_state.sh TASK-001 full)
(cd "$DIR" && bash hooks/advance_pipeline_state.sh researcher coder)
assert_field "advance sets current_step to coder" "$DIR" "current_step" "coder"
COMPLETED=$(python3 -c "import json; d=json.load(open('$DIR/pipeline_state.json')); print(d['completed_steps'])")
if echo "$COMPLETED" | grep -q "researcher"; then
    echo "PASS: advance adds researcher to completed_steps"; PASS=$((PASS+1))
else
    echo "FAIL: researcher not in completed_steps: $COMPLETED"; FAIL=$((FAIL+1))
fi

# Test 4: Advance to 'done' → status=completed, current_step=None
DIR=$(setup_repo)
(cd "$DIR" && bash hooks/init_pipeline_state.sh TASK-001 full)
(cd "$DIR" && bash hooks/advance_pipeline_state.sh memory done)
assert_field "done sets status=completed"  "$DIR" "status"       "completed"
assert_field "done sets current_step=None" "$DIR" "current_step" "None"

# Test 5: Advance without init → exit 1
DIR=$(setup_repo)
(cd "$DIR" && bash hooks/advance_pipeline_state.sh researcher coder 2>/dev/null) && EXIT=0 || EXIT=$?
assert_exit "advance without init fails" 1 "$EXIT"

# Test 6: Init with invalid pipeline name → exit 1
DIR=$(setup_repo)
(cd "$DIR" && bash hooks/init_pipeline_state.sh TASK-001 invalid 2>/dev/null) && EXIT=0 || EXIT=$?
assert_exit "invalid pipeline name fails" 1 "$EXIT"

# Test: init records started_at as ISO-8601 UTC
DIR=$(setup_repo)
(cd "$DIR" && bash hooks/init_pipeline_state.sh TASK-001 full)
STARTED=$(python3 -c "import json; print(json.load(open('$DIR/pipeline_state.json')).get('started_at',''))")
if echo "$STARTED" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8}Z$'; then
    echo "PASS: init records started_at"; PASS=$((PASS+1))
else
    echo "FAIL: started_at missing or malformed: '$STARTED'"; FAIL=$((FAIL+1))
fi

# Test: re-running a completed step counts as a retry and re-opens the step
DIR=$(setup_repo)
(cd "$DIR" && bash hooks/init_pipeline_state.sh TASK-001 full)
(cd "$DIR" && bash hooks/advance_pipeline_state.sh researcher coder)
(cd "$DIR" && bash hooks/advance_pipeline_state.sh coder reviewer)
(cd "$DIR" && bash hooks/advance_pipeline_state.sh reviewer coder)
RETRY=$(python3 -c "import json; print(json.load(open('$DIR/pipeline_state.json')).get('retries',{}).get('coder',0))")
assert_field "retry re-opens the step (current_step=coder)" "$DIR" "current_step" "coder"
if [ "$RETRY" = "1" ]; then
    echo "PASS: retries.coder == 1 after backward transition"; PASS=$((PASS+1))
else
    echo "FAIL: retries.coder expected 1, got '$RETRY'"; FAIL=$((FAIL+1))
fi
COMPLETED=$(python3 -c "import json; print(json.load(open('$DIR/pipeline_state.json'))['completed_steps'])")
if echo "$COMPLETED" | grep -q "coder"; then
    echo "FAIL: coder still in completed_steps after retry: $COMPLETED"; FAIL=$((FAIL+1))
else
    echo "PASS: coder removed from completed_steps on retry"; PASS=$((PASS+1))
fi

# Test: pre_task.sh outputs RECOVERY block when pipeline_state.json shows running
DIR=$(setup_repo)
cp "$PROJECT_ROOT/hooks/pre_task.sh" "$DIR/hooks/"
mkdir -p "$DIR/memory"
(cd "$DIR" && bash hooks/init_pipeline_state.sh TASK-003 full)
# advance to mid-pipeline to simulate a crash after researcher
(cd "$DIR" && bash hooks/advance_pipeline_state.sh researcher coder)
RECOVERY_OUTPUT=$(cd "$DIR" && echo '{"session_id":"test-123"}' | bash hooks/pre_task.sh 2>&1 || true)
if echo "$RECOVERY_OUTPUT" | grep -q "RECOVERY"; then
    echo "PASS: pre_task.sh outputs RECOVERY when pipeline running"; PASS=$((PASS+1))
else
    echo "FAIL: pre_task.sh did not output RECOVERY block"; FAIL=$((FAIL+1))
fi
if echo "$RECOVERY_OUTPUT" | grep -q "coder"; then
    echo "PASS: RECOVERY block names the interrupted step"; PASS=$((PASS+1))
else
    echo "FAIL: step name not in recovery output"; FAIL=$((FAIL+1))
fi
if echo "$RECOVERY_OUTPUT" | grep -q "TASK-003"; then
    echo "PASS: RECOVERY block names the task id"; PASS=$((PASS+1))
else
    echo "FAIL: task id not in recovery output"; FAIL=$((FAIL+1))
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
