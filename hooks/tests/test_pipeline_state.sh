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
        cp "$PROJECT_ROOT/hooks/log_agent.sh" hooks/
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

# Test: advance auto-emits agent_start for the next step
DIR=$(setup_repo)
mkdir -p "$DIR/logs"
(cd "$DIR" && bash hooks/init_pipeline_state.sh TASK-001 fast-track >/dev/null)
(cd "$DIR" && bash hooks/advance_pipeline_state.sh coder tester >/dev/null)
if grep -q '"event": "agent_start"' "$DIR/logs/pipeline.jsonl" 2>/dev/null && \
   grep -q '"agent": "tester"' "$DIR/logs/pipeline.jsonl" 2>/dev/null; then
    echo "PASS: advance auto-emits agent_start for next step"; PASS=$((PASS+1))
else
    echo "FAIL: advance did not auto-emit agent_start"; FAIL=$((FAIL+1))
fi

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

# Test: init emits a run-scoped pipeline_init event with the classifier verdict
DIR=$(setup_repo)
mkdir -p "$DIR/.claude/tmp"
echo "AMBIGUOUS" > "$DIR/.claude/tmp/task_mode"
(cd "$DIR" && bash hooks/init_pipeline_state.sh TASK-007 fast-track "doc-only change, no shared logic")
RUN_ID=$(python3 -c "import json; print(json.load(open('$DIR/pipeline_state.json'))['run_id'])")
LAST=$(tail -1 "$DIR/logs/pipeline.jsonl" 2>/dev/null || echo "{}")
for check in \
    "event=pipeline_init" \
    "task_id=TASK-007" \
    "pipeline=fast-track" \
    "classifier_verdict=AMBIGUOUS" \
    "decision_reason=doc-only change, no shared logic" \
    "run_id=$RUN_ID"; do
    field="${check%%=*}"; expected="${check#*=}"
    actual=$(echo "$LAST" | python3 -c "import json,sys; print(json.load(sys.stdin).get('$field',''))")
    if [ "$actual" = "$expected" ]; then
        echo "PASS: pipeline_init $field"; PASS=$((PASS+1))
    else
        echo "FAIL: pipeline_init $field — expected '$expected', got '$actual'"; FAIL=$((FAIL+1))
    fi
done

# Test: init sets agent_active=false
DIR=$(setup_repo)
(cd "$DIR" && bash hooks/init_pipeline_state.sh TASK-010 full >/dev/null)
ACTIVE=$(python3 -c "import json; print(json.load(open('$DIR/pipeline_state.json')).get('agent_active'))")
if [ "$ACTIVE" = "False" ]; then
    echo "PASS: init sets agent_active=false"; PASS=$((PASS+1))
else
    echo "FAIL: init agent_active expected False, got '$ACTIVE'"; FAIL=$((FAIL+1))
fi

# Test: log_agent START sets agent_active=true
DIR=$(setup_repo)
(cd "$DIR" && bash hooks/init_pipeline_state.sh TASK-011 fast-track >/dev/null)
(cd "$DIR" && bash hooks/log_agent.sh coder START TASK-011 fast-track >/dev/null 2>&1)
ACTIVE=$(python3 -c "import json; print(json.load(open('$DIR/pipeline_state.json')).get('agent_active'))")
if [ "$ACTIVE" = "True" ]; then
    echo "PASS: log_agent START sets agent_active=true"; PASS=$((PASS+1))
else
    echo "FAIL: log_agent START agent_active expected True, got '$ACTIVE'"; FAIL=$((FAIL+1))
fi

# Test: log_agent END sets agent_active=false
(cd "$DIR" && bash hooks/log_agent.sh coder END TASK-011 DONE - - 0 >/dev/null 2>&1)
ACTIVE=$(python3 -c "import json; print(json.load(open('$DIR/pipeline_state.json')).get('agent_active'))")
if [ "$ACTIVE" = "False" ]; then
    echo "PASS: log_agent END sets agent_active=false"; PASS=$((PASS+1))
else
    echo "FAIL: log_agent END agent_active expected False, got '$ACTIVE'"; FAIL=$((FAIL+1))
fi

# Test: advance to done leaves agent_active=false (no auto-emit)
DIR=$(setup_repo)
(cd "$DIR" && bash hooks/init_pipeline_state.sh TASK-012 fast-track >/dev/null)
(cd "$DIR" && bash hooks/log_agent.sh memory START TASK-012 fast-track >/dev/null 2>&1)
(cd "$DIR" && bash hooks/advance_pipeline_state.sh memory done >/dev/null)
ACTIVE=$(python3 -c "import json; print(json.load(open('$DIR/pipeline_state.json')).get('agent_active'))")
if [ "$ACTIVE" = "False" ]; then
    echo "PASS: advance to done leaves agent_active=false"; PASS=$((PASS+1))
else
    echo "FAIL: advance-to-done agent_active expected False, got '$ACTIVE'"; FAIL=$((FAIL+1))
fi

# Test: no task_mode file → verdict UNKNOWN; no reason arg → null
DIR=$(setup_repo)
(cd "$DIR" && bash hooks/init_pipeline_state.sh TASK-008 full)
LAST=$(tail -1 "$DIR/logs/pipeline.jsonl" 2>/dev/null || echo "{}")
V=$(echo "$LAST" | python3 -c "import json,sys; print(json.load(sys.stdin).get('classifier_verdict',''))")
R=$(echo "$LAST" | python3 -c "import json,sys; print(json.load(sys.stdin).get('decision_reason'))")
if [ "$V" = "UNKNOWN" ] && [ "$R" = "None" ]; then
    echo "PASS: pipeline_init defaults (UNKNOWN verdict, null reason)"; PASS=$((PASS+1))
else
    echo "FAIL: pipeline_init defaults — verdict '$V', reason '$R'"; FAIL=$((FAIL+1))
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
