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
    mkdir -p hooks/lib contracts
    cp "$PROJECT_ROOT/hooks/validate_output.sh" hooks/
    cp "$PROJECT_ROOT/hooks/lib/common.sh" hooks/lib/
    cp -r "$PROJECT_ROOT/contracts/." contracts/
    git add . && git commit -q -m "init"
    echo "$tmpdir"
}

assert_exit() {
    local name="$1" expected="$2" actual="$3"
    if [ "$actual" -eq "$expected" ]; then
        echo "PASS: $name"; PASS=$((PASS+1))
    else
        echo "FAIL: $name — expected exit $expected, got $actual"; FAIL=$((FAIL+1))
    fi
}

# Test 1: Free text (not JSON) → exit 1
DIR=$(setup_repo)
(cd "$DIR" && echo "looks good to me" | bash hooks/validate_output.sh reviewer 2>/dev/null) && EXIT=0 || EXIT=$?
assert_exit "free text rejected" 1 "$EXIT"

# Test 2: Valid coder envelope → exit 0
# payload must include files_changed and spec_deviations (required_payload_fields in coder.json).
# spec_deviations: [] is a positive affirmation that the implementation matches the approved spec.
DIR=$(setup_repo)
ENVELOPE='{"task_id":"TASK-001","agent":"coder","verdict":"DONE","payload":{"files_changed":["src/foo.py"],"decisions":[],"convention_gaps":[],"spec_deviations":[]},"next_agent":"reviewer","reason":null}'
(cd "$DIR" && echo "$ENVELOPE" | bash hooks/validate_output.sh coder 2>/dev/null) && EXIT=0 || EXIT=$?
assert_exit "valid coder envelope accepted" 0 "$EXIT"

# Test 2b: Coder envelope missing spec_deviations → exit 1
DIR=$(setup_repo)
MISSING_SPEC='{"task_id":"TASK-001","agent":"coder","verdict":"DONE","payload":{"files_changed":["src/foo.py"]},"next_agent":"reviewer","reason":null}'
(cd "$DIR" && echo "$MISSING_SPEC" | bash hooks/validate_output.sh coder 2>/dev/null) && EXIT=0 || EXIT=$?
assert_exit "coder envelope missing spec_deviations rejected" 1 "$EXIT"

# Test 3: Missing required fields → exit 1
DIR=$(setup_repo)
(cd "$DIR" && echo '{"agent":"coder","verdict":"DONE"}' | bash hooks/validate_output.sh coder 2>/dev/null) && EXIT=0 || EXIT=$?
assert_exit "missing required fields rejected" 1 "$EXIT"

# Test 4: Invalid verdict → exit 1
DIR=$(setup_repo)
BAD_VERDICT='{"task_id":"T-1","agent":"reviewer","verdict":"MAYBE","payload":{},"next_agent":"tester","reason":null,"timestamp":"2026-06-08T10:00:00Z"}'
(cd "$DIR" && echo "$BAD_VERDICT" | bash hooks/validate_output.sh reviewer 2>/dev/null) && EXIT=0 || EXIT=$?
assert_exit "invalid verdict rejected" 1 "$EXIT"

# Test 5: FIX_REQUIRED without reason → exit 1
DIR=$(setup_repo)
NO_REASON='{"task_id":"T-1","agent":"reviewer","verdict":"FIX_REQUIRED","payload":{"required_changes":[],"convention_candidates":[]},"next_agent":"coder","reason":null,"timestamp":"2026-06-08T10:00:00Z"}'
(cd "$DIR" && echo "$NO_REASON" | bash hooks/validate_output.sh reviewer 2>/dev/null) && EXIT=0 || EXIT=$?
assert_exit "FIX_REQUIRED without reason rejected" 1 "$EXIT"

# Test 6: FIX_REQUIRED with reason → exit 0
DIR=$(setup_repo)
WITH_REASON='{"task_id":"T-1","agent":"reviewer","verdict":"FIX_REQUIRED","payload":{"required_changes":["[foo.py:5] issue"],"convention_candidates":[]},"next_agent":"coder","reason":"1 reliability violation","timestamp":"2026-06-08T10:00:00Z"}'
(cd "$DIR" && echo "$WITH_REASON" | bash hooks/validate_output.sh reviewer 2>/dev/null) && EXIT=0 || EXIT=$?
assert_exit "FIX_REQUIRED with reason accepted" 0 "$EXIT"

# Test 7: Unknown agent (no contract file) → exit 1
DIR=$(setup_repo)
(cd "$DIR" && echo '{"task_id":"T-1","agent":"unknown","verdict":"DONE"}' | bash hooks/validate_output.sh unknown 2>/dev/null) && EXIT=0 || EXIT=$?
assert_exit "unknown agent rejected" 1 "$EXIT"

# Test 8: BLOCKED without reason → exit 1
DIR=$(setup_repo)
BLOCKED_NO_REASON='{"task_id":"T-1","agent":"security","verdict":"BLOCKED","payload":{"blockers":[]},"next_agent":null,"reason":null,"timestamp":"2026-06-08T10:00:00Z"}'
(cd "$DIR" && echo "$BLOCKED_NO_REASON" | bash hooks/validate_output.sh security 2>/dev/null) && EXIT=0 || EXIT=$?
assert_exit "BLOCKED without reason rejected" 1 "$EXIT"

# Test 9: Agent field mismatch (coder envelope sent to reviewer validator) → exit 1
DIR=$(setup_repo)
MISMATCH='{"task_id":"T-1","agent":"coder","verdict":"DONE","payload":{},"next_agent":"reviewer","reason":null,"timestamp":"2026-06-08T10:00:00Z"}'
(cd "$DIR" && echo "$MISMATCH" | bash hooks/validate_output.sh reviewer 2>/dev/null) && EXIT=0 || EXIT=$?
assert_exit "agent field mismatch rejected" 1 "$EXIT"

# Test 10: validated_at AND timestamp are stamped with real wall clock (not agent-supplied placeholder)
# The coder contract now requires files_changed and spec_deviations in payload.
# Agents no longer supply timestamp — validate_output.sh overwrites it with the real wall clock.
DIR=$(setup_repo)
mkdir -p "$DIR/logs"
VALID_CODER='{"task_id":"T-1","agent":"coder","verdict":"DONE","payload":{"files_changed":["src/a.py"],"spec_deviations":[]},"next_agent":"reviewer","reason":null}'
(cd "$DIR" && echo "$VALID_CODER" | bash hooks/validate_output.sh coder 2>/dev/null)
VALIDATED_AT=$(python3 -c "
import json
lines = open('$DIR/logs/pipeline.jsonl').readlines()
d = json.loads(lines[-1])
print(d.get('validated_at', 'MISSING'))
" 2>/dev/null || echo "MISSING")
TIMESTAMP=$(python3 -c "
import json
lines = open('$DIR/logs/pipeline.jsonl').readlines()
d = json.loads(lines[-1])
print(d.get('timestamp', 'MISSING'))
" 2>/dev/null || echo "MISSING")
# validated_at and timestamp must exist and be real (not midnight placeholder, not MISSING)
if [ "$VALIDATED_AT" = "MISSING" ] || [ "$VALIDATED_AT" = "2026-06-10T00:00:00Z" ]; then
    echo "FAIL: validated_at missing or is fake timestamp: '$VALIDATED_AT'"; FAIL=$((FAIL+1))
else
    echo "PASS: validated_at is real wall-clock timestamp: $VALIDATED_AT"; PASS=$((PASS+1))
fi
if [ "$TIMESTAMP" = "MISSING" ] || [ "$TIMESTAMP" = "2026-06-10T00:00:00Z" ]; then
    echo "FAIL: timestamp missing or is fake: '$TIMESTAMP'"; FAIL=$((FAIL+1))
else
    echo "PASS: timestamp overwritten with real wall-clock: $TIMESTAMP"; PASS=$((PASS+1))
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
