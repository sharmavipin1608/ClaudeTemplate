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
    cd "$tmpdir"
    git init -q
    git config user.email "test@test.com"
    git config user.name "Test"
    mkdir -p hooks
    cp "$PROJECT_ROOT/hooks/init_pipeline_state.sh" hooks/
    cp "$PROJECT_ROOT/hooks/advance_pipeline_state.sh" hooks/
    git add . && git commit -q -m "init"
    echo "$tmpdir"
}

assert_field() {
    local name="$1" field="$2" expected="$3"
    actual=$(python3 -c "import json; d=json.load(open('pipeline_state.json')); v=d.get('$field'); print(v if v is not None else 'None')" 2>/dev/null || echo "MISSING")
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
(cd "$DIR" && assert_field "full pipeline starts at researcher" "current_step" "researcher")
(cd "$DIR" && assert_field "full pipeline status is running" "status" "running")
(cd "$DIR" && assert_field "full pipeline task_id recorded" "task_id" "TASK-001")
(cd "$DIR" && assert_field "full pipeline name recorded" "pipeline" "full")

# Test 2: Init fast-track pipeline → current_step=coder
DIR=$(setup_repo)
(cd "$DIR" && bash hooks/init_pipeline_state.sh TASK-002 fast-track)
(cd "$DIR" && assert_field "fast-track starts at coder" "current_step" "coder")
(cd "$DIR" && assert_field "fast-track pipeline name recorded" "pipeline" "fast-track")

# Test 3: Advance updates current_step and completed_steps
DIR=$(setup_repo)
(cd "$DIR" && bash hooks/init_pipeline_state.sh TASK-001 full)
(cd "$DIR" && bash hooks/advance_pipeline_state.sh researcher coder)
(cd "$DIR" && assert_field "advance sets current_step to coder" "current_step" "coder")
COMPLETED=$(cd "$DIR" && python3 -c "import json; d=json.load(open('pipeline_state.json')); print(d['completed_steps'])")
if echo "$COMPLETED" | grep -q "researcher"; then
    echo "PASS: advance adds researcher to completed_steps"; PASS=$((PASS+1))
else
    echo "FAIL: researcher not in completed_steps: $COMPLETED"; FAIL=$((FAIL+1))
fi

# Test 4: Advance to 'done' → status=completed, current_step=None
DIR=$(setup_repo)
(cd "$DIR" && bash hooks/init_pipeline_state.sh TASK-001 full)
(cd "$DIR" && bash hooks/advance_pipeline_state.sh memory done)
(cd "$DIR" && assert_field "done sets status=completed" "status" "completed")
(cd "$DIR" && assert_field "done sets current_step=None" "current_step" "None")

# Test 5: Advance without init → exit 1
DIR=$(setup_repo)
(cd "$DIR" && bash hooks/advance_pipeline_state.sh researcher coder 2>/dev/null) && EXIT=0 || EXIT=$?
assert_exit "advance without init fails" 1 "$EXIT"

# Test 6: Init with invalid pipeline name → exit 1
DIR=$(setup_repo)
(cd "$DIR" && bash hooks/init_pipeline_state.sh TASK-001 invalid 2>/dev/null) && EXIT=0 || EXIT=$?
assert_exit "invalid pipeline name fails" 1 "$EXIT"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
