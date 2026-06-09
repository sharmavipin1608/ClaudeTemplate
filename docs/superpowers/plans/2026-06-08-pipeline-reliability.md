# Pipeline Reliability — State Machine, Contracts, Validation

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close three coupled reliability gaps: add a durable `pipeline_state.json` state machine so crashed sessions resume at the right step; define a shared JSON envelope schema for all agent outputs so the orchestrator routes on `verdict` rather than prose; add `validate_output.sh` to reject malformed agent output before the pipeline proceeds.

**Architecture:** All agent output becomes a JSON envelope `{ task_id, agent, verdict, payload, next_agent, reason, timestamp }`. Per-agent schemas live in `contracts/<agent>.json`. `hooks/validate_output.sh` validates stdin against the correct contract. `hooks/init_pipeline_state.sh` and `hooks/advance_pipeline_state.sh` maintain `pipeline_state.json` atomically. `hooks/pre_task.sh` outputs a recovery hint when `pipeline_state.json` shows a running task on session start. Orchestrator docs are updated to call validate and advance scripts between every agent handoff.

**Tech Stack:** Bash, Python 3 (stdlib only — no pip installs). All new files are either bash scripts, JSON, or markdown.

---

## File Map

| Action | File | Responsibility |
|---|---|---|
| Create | `contracts/coder.json` | Envelope schema — valid verdicts and required fields for Coder |
| Create | `contracts/researcher.json` | Same for Researcher |
| Create | `contracts/reviewer.json` | Same for Reviewer; reason required on FIX_REQUIRED |
| Create | `contracts/tester.json` | Same for Tester; reason required on FAIL |
| Create | `contracts/security.json` | Same for Security; reason required on BLOCKED |
| Create | `contracts/git.json` | Same for Git; reason required on PUSH_FAILED |
| Create | `contracts/devops.json` | Same for DevOps; reason required on CI_FAILED |
| Create | `contracts/memory.json` | Same for Memory |
| Create | `hooks/validate_output.sh` | Read stdin JSON, validate against contracts/<agent>.json; exit 1 with message on mismatch |
| Create | `hooks/init_pipeline_state.sh` | Write initial `pipeline_state.json` for a task; atomic `.tmp → mv` |
| Create | `hooks/advance_pipeline_state.sh` | Move `pipeline_state.json` to next step; set status=completed on done |
| Create | `hooks/tests/test_validate_output.sh` | 8-case bash test suite for validate_output.sh |
| Create | `hooks/tests/test_pipeline_state.sh` | 6-case bash test suite for init/advance scripts |
| Modify | `hooks/pre_task.sh` | Add session-start recovery hint from pipeline_state.json |
| Modify | `agents/coder.md` | Replace prose "Output to orchestrator" with envelope format |
| Modify | `agents/researcher.md` | Same |
| Modify | `agents/reviewer.md` | Same |
| Modify | `agents/tester.md` | Same |
| Modify | `agents/security.md` | Same |
| Modify | `agents/git.md` | Same |
| Modify | `agents/devops.md` | Same |
| Modify | `agents/memory.md` | Same |
| Modify | `.claude/orchestrator.md` | Add validate step, state advance, verdict-based routing in per-task loop |
| Modify | `CLAUDE.md` | Same updates as orchestrator.md |
| Modify | `.gitignore` | Add `pipeline_state.json` (runtime file, not committed) |
| Modify | `bootstrap.sh` | Add `contracts` to step 7/9 infra-move loop; add `tests/` to cleanup step so neither pollutes bootstrapped projects |
| Create | `tests/verify_issue_30.sh` | Bootstrap demo project, run 30 structured checks, post markdown report to GitHub issue #30 |

---

### Task 1: Create agent envelope contracts

**Files:**
- Create: `contracts/coder.json`
- Create: `contracts/researcher.json`
- Create: `contracts/reviewer.json`
- Create: `contracts/tester.json`
- Create: `contracts/security.json`
- Create: `contracts/git.json`
- Create: `contracts/devops.json`
- Create: `contracts/memory.json`

Each contract defines `required_fields`, `valid_verdicts`, and `reason_required_on`. These are consumed by `validate_output.sh` (Task 2) and referenced in agent definitions (Task 5).

- [ ] **Step 1: Create contracts/ directory and write all 8 contract files**

```bash
mkdir -p contracts
```

`contracts/coder.json`:
```json
{
  "agent": "coder",
  "required_fields": ["task_id", "agent", "verdict", "payload", "next_agent", "timestamp"],
  "valid_verdicts": ["DONE"],
  "reason_required_on": []
}
```

`contracts/researcher.json`:
```json
{
  "agent": "researcher",
  "required_fields": ["task_id", "agent", "verdict", "payload", "next_agent", "timestamp"],
  "valid_verdicts": ["DONE"],
  "reason_required_on": []
}
```

`contracts/reviewer.json`:
```json
{
  "agent": "reviewer",
  "required_fields": ["task_id", "agent", "verdict", "payload", "next_agent", "timestamp"],
  "valid_verdicts": ["PASS", "FIX_REQUIRED"],
  "reason_required_on": ["FIX_REQUIRED"]
}
```

`contracts/tester.json`:
```json
{
  "agent": "tester",
  "required_fields": ["task_id", "agent", "verdict", "payload", "next_agent", "timestamp"],
  "valid_verdicts": ["PASS", "FAIL"],
  "reason_required_on": ["FAIL"]
}
```

`contracts/security.json`:
```json
{
  "agent": "security",
  "required_fields": ["task_id", "agent", "verdict", "payload", "next_agent", "timestamp"],
  "valid_verdicts": ["PASS", "BLOCKED"],
  "reason_required_on": ["BLOCKED"]
}
```

`contracts/git.json`:
```json
{
  "agent": "git",
  "required_fields": ["task_id", "agent", "verdict", "payload", "next_agent", "timestamp"],
  "valid_verdicts": ["COMMITTED", "PUSH_FAILED"],
  "reason_required_on": ["PUSH_FAILED"]
}
```

`contracts/devops.json`:
```json
{
  "agent": "devops",
  "required_fields": ["task_id", "agent", "verdict", "payload", "next_agent", "timestamp"],
  "valid_verdicts": ["PASS", "CI_FAILED"],
  "reason_required_on": ["CI_FAILED"]
}
```

`contracts/memory.json`:
```json
{
  "agent": "memory",
  "required_fields": ["task_id", "agent", "verdict", "payload", "next_agent", "timestamp"],
  "valid_verdicts": ["DONE", "DRAINED"],
  "reason_required_on": []
}
```

- [ ] **Step 2: Verify all 8 files exist and are valid JSON**

```bash
ls contracts/ | sort
# Expected output:
# coder.json
# devops.json
# git.json
# memory.json
# researcher.json
# reviewer.json
# security.json
# tester.json

for f in contracts/*.json; do python3 -m json.tool "$f" > /dev/null && echo "OK: $f"; done
# Expected: OK: contracts/coder.json ... (8 lines, all OK)
```

- [ ] **Step 3: Commit**

```bash
git add contracts/
git commit -m "feat(pipeline): add agent envelope contracts to contracts/"
```

---

### Task 2: Create validate_output.sh (TDD)

**Files:**
- Create: `hooks/tests/test_validate_output.sh`
- Create: `hooks/validate_output.sh`

- [ ] **Step 1: Write the failing tests**

Create `hooks/tests/test_validate_output.sh`:

```bash
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
    mkdir -p hooks contracts
    cp "$PROJECT_ROOT/hooks/validate_output.sh" hooks/
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
DIR=$(setup_repo)
ENVELOPE='{"task_id":"TASK-001","agent":"coder","verdict":"DONE","payload":{"files_changed":["src/foo.py"],"decisions":[],"convention_gaps":[]},"next_agent":"reviewer","reason":null,"timestamp":"2026-06-08T10:00:00Z"}'
(cd "$DIR" && echo "$ENVELOPE" | bash hooks/validate_output.sh coder 2>/dev/null) && EXIT=0 || EXIT=$?
assert_exit "valid coder envelope accepted" 0 "$EXIT"

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

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
```

- [ ] **Step 2: Run tests to confirm they all fail (validate_output.sh doesn't exist yet)**

```bash
bash hooks/tests/test_validate_output.sh
# Expected: multiple FAIL lines — the script doesn't exist yet
```

- [ ] **Step 3: Write hooks/validate_output.sh**

```bash
#!/bin/bash
# Validates agent JSON envelope output against contracts/<agent>.json
# Usage: bash hooks/validate_output.sh <agent_name>  (reads envelope from stdin)
# Exit 0: valid. Exit 1: invalid (error written to stderr).
set -uo pipefail

AGENT="${1:-}"
[ -z "$AGENT" ] && { echo "ERROR: agent name required" >&2; exit 1; }

PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

# Contracts live at .claude/contracts/ in bootstrapped projects, contracts/ in the template repo itself.
if [ -d "$PROJECT_ROOT/.claude/contracts" ]; then
    CONTRACTS_DIR="$PROJECT_ROOT/.claude/contracts"
else
    CONTRACTS_DIR="$PROJECT_ROOT/contracts"
fi
CONTRACT="$CONTRACTS_DIR/${AGENT}.json"

[ ! -f "$CONTRACT" ] && { echo "ERROR: no contract found for agent '${AGENT}' at ${CONTRACT}" >&2; exit 1; }

export VALIDATE_INPUT_B64
VALIDATE_INPUT_B64=$(cat | base64)
export VALIDATE_CONTRACT="$CONTRACT"

python3 - <<'PYEOF'
import sys, json, base64, os

input_b64 = os.environ.get("VALIDATE_INPUT_B64", "")
contract_path = os.environ.get("VALIDATE_CONTRACT", "")

try:
    raw = base64.b64decode(input_b64).decode("utf-8")
    envelope = json.loads(raw)
except Exception as e:
    print(f"ERROR: output is not valid JSON: {e}", file=sys.stderr)
    sys.exit(1)

with open(contract_path) as f:
    contract = json.load(f)

errors = []

for field in contract["required_fields"]:
    if field not in envelope:
        errors.append(f"missing required field: '{field}'")

if "agent" in envelope and envelope["agent"] != contract["agent"]:
    errors.append(f"agent mismatch: expected '{contract['agent']}', got '{envelope['agent']}'")

if "verdict" in envelope:
    verdict = envelope["verdict"]
    if verdict not in contract["valid_verdicts"]:
        errors.append(f"invalid verdict '{verdict}': must be one of {contract['valid_verdicts']}")
    elif verdict in contract.get("reason_required_on", []):
        if not envelope.get("reason"):
            errors.append(f"verdict '{verdict}' requires a non-empty 'reason' field")

if errors:
    agent_name = contract.get("agent", "unknown")
    print(f"VALIDATION FAILED for agent '{agent_name}':", file=sys.stderr)
    for e in errors:
        print(f"  - {e}", file=sys.stderr)
    sys.exit(1)

print(f"OK: {envelope.get('agent')} verdict={envelope.get('verdict')}")
PYEOF
```

```bash
chmod +x hooks/validate_output.sh
```

- [ ] **Step 4: Run tests to confirm all 8 pass**

```bash
bash hooks/tests/test_validate_output.sh
# Expected:
# PASS: free text rejected
# PASS: valid coder envelope accepted
# PASS: missing required fields rejected
# PASS: invalid verdict rejected
# PASS: FIX_REQUIRED without reason rejected
# PASS: FIX_REQUIRED with reason accepted
# PASS: unknown agent rejected
# PASS: BLOCKED without reason rejected
#
# Results: 8 passed, 0 failed
```

- [ ] **Step 5: Commit**

```bash
git add hooks/validate_output.sh hooks/tests/test_validate_output.sh
git commit -m "feat(pipeline): add validate_output.sh with contract-based envelope validation"
```

---

### Task 3: Create pipeline state machine scripts (TDD)

**Files:**
- Create: `hooks/tests/test_pipeline_state.sh`
- Create: `hooks/init_pipeline_state.sh`
- Create: `hooks/advance_pipeline_state.sh`

- [ ] **Step 1: Write the failing tests**

Create `hooks/tests/test_pipeline_state.sh`:

```bash
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
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
bash hooks/tests/test_pipeline_state.sh
# Expected: multiple FAIL lines — scripts don't exist yet
```

- [ ] **Step 3: Write hooks/init_pipeline_state.sh**

```bash
#!/bin/bash
# Initializes pipeline_state.json for a new task. Atomic write via .tmp → mv.
# Usage: bash hooks/init_pipeline_state.sh <task_id> <pipeline>
# pipeline: full | fast-track
set -uo pipefail

TASK_ID="${1:-}"
PIPELINE="${2:-}"

[ -z "$TASK_ID" ] && { echo "ERROR: task_id required" >&2; exit 1; }
[ -z "$PIPELINE" ] && { echo "ERROR: pipeline required (full|fast-track)" >&2; exit 1; }

PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

case "$PIPELINE" in
    full)       FIRST_STEP="researcher" ;;
    fast-track) FIRST_STEP="coder" ;;
    *)          echo "ERROR: pipeline must be 'full' or 'fast-track'" >&2; exit 1 ;;
esac

export INIT_TASK_ID="$TASK_ID"
export INIT_PIPELINE="$PIPELINE"
export INIT_FIRST_STEP="$FIRST_STEP"
export INIT_STATE_FILE="$PROJECT_ROOT/pipeline_state.json"
export INIT_TIMESTAMP
INIT_TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

python3 - <<'PYEOF'
import json, os

state = {
    "task_id": os.environ["INIT_TASK_ID"],
    "pipeline": os.environ["INIT_PIPELINE"],
    "current_step": os.environ["INIT_FIRST_STEP"],
    "completed_steps": [],
    "status": "running",
    "updated_at": os.environ["INIT_TIMESTAMP"]
}

state_file = os.environ["INIT_STATE_FILE"]
tmp = state_file + ".tmp"
with open(tmp, "w") as f:
    json.dump(state, f, indent=2)
os.replace(tmp, state_file)
print(f"Pipeline state initialized: {state['task_id']} / {state['pipeline']} → {state['current_step']}")
PYEOF
```

```bash
chmod +x hooks/init_pipeline_state.sh
```

- [ ] **Step 4: Write hooks/advance_pipeline_state.sh**

```bash
#!/bin/bash
# Advances pipeline_state.json to the next step. Atomic write via .tmp → mv.
# Usage: bash hooks/advance_pipeline_state.sh <completed_step> <next_step|done>
# Pass "done" as next_step when the pipeline completes.
set -uo pipefail

COMPLETED="${1:-}"
NEXT="${2:-}"

[ -z "$COMPLETED" ] && { echo "ERROR: completed_step required" >&2; exit 1; }
[ -z "$NEXT" ] && { echo "ERROR: next_step required (or 'done')" >&2; exit 1; }

PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
STATE_FILE="$PROJECT_ROOT/pipeline_state.json"

[ ! -f "$STATE_FILE" ] && { echo "ERROR: pipeline_state.json not found — call init_pipeline_state.sh first" >&2; exit 1; }

export ADVANCE_COMPLETED="$COMPLETED"
export ADVANCE_NEXT="$NEXT"
export ADVANCE_STATE_FILE="$STATE_FILE"
export ADVANCE_TIMESTAMP
ADVANCE_TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

python3 - <<'PYEOF'
import json, os

state_file = os.environ["ADVANCE_STATE_FILE"]
with open(state_file) as f:
    state = json.load(f)

completed = os.environ["ADVANCE_COMPLETED"]
next_step = os.environ["ADVANCE_NEXT"]

if completed not in state["completed_steps"]:
    state["completed_steps"].append(completed)

if next_step == "done":
    state["status"] = "completed"
    state["current_step"] = None
else:
    state["current_step"] = next_step

state["updated_at"] = os.environ["ADVANCE_TIMESTAMP"]

tmp = state_file + ".tmp"
with open(tmp, "w") as f:
    json.dump(state, f, indent=2)
os.replace(tmp, state_file)

current = state.get("current_step") or "none"
print(f"State advanced: completed={state['completed_steps']} next={current} status={state['status']}")
PYEOF
```

```bash
chmod +x hooks/advance_pipeline_state.sh
```

- [ ] **Step 5: Run tests to confirm all 10 assertions pass**

```bash
bash hooks/tests/test_pipeline_state.sh
# Expected:
# PASS: full pipeline starts at researcher
# PASS: full pipeline status is running
# PASS: full pipeline task_id recorded
# PASS: full pipeline name recorded
# PASS: fast-track starts at coder
# PASS: fast-track pipeline name recorded
# PASS: advance sets current_step to coder
# PASS: advance adds researcher to completed_steps
# PASS: done sets status=completed
# PASS: done sets current_step=None
# PASS: advance without init fails
# PASS: invalid pipeline name fails
#
# Results: 12 passed, 0 failed
```

- [ ] **Step 6: Commit**

```bash
git add hooks/init_pipeline_state.sh hooks/advance_pipeline_state.sh hooks/tests/test_pipeline_state.sh
git commit -m "feat(pipeline): add init/advance pipeline state scripts with atomic writes"
```

---

### Task 4: Add session-start recovery to pre_task.sh (TDD)

**Files:**
- Modify: `hooks/pre_task.sh`
- Modify: `hooks/tests/` (extend test_pipeline_state.sh with recovery test)

- [ ] **Step 1: Write a failing test for recovery output**

Append to `hooks/tests/test_pipeline_state.sh` before the final `echo "Results"` line:

```bash
# Test: pre_task.sh outputs RECOVERY block when pipeline_state.json shows running
DIR=$(setup_repo)
cp "$PROJECT_ROOT/hooks/pre_task.sh" "$DIR/hooks/"
mkdir -p "$DIR/memory"
(cd "$DIR" && bash hooks/init_pipeline_state.sh TASK-003 full)
# advance to mid-pipeline to simulate a crash after researcher
(cd "$DIR" && bash hooks/advance_pipeline_state.sh researcher coder)
OUTPUT=$(cd "$DIR" && echo '{"session_id":"test-123"}' | bash hooks/pre_task.sh 2>&1 || true)
if echo "$OUTPUT" | grep -q "RECOVERY"; then
    echo "PASS: pre_task.sh outputs RECOVERY when pipeline running"; PASS=$((PASS+1))
else
    echo "FAIL: pre_task.sh did not output RECOVERY block"; FAIL=$((FAIL+1))
fi
```

- [ ] **Step 2: Run the test to confirm it fails**

```bash
bash hooks/tests/test_pipeline_state.sh 2>/dev/null | tail -5
# Expected: FAIL: pre_task.sh did not output RECOVERY block
```

- [ ] **Step 3: Add recovery check to hooks/pre_task.sh**

Add the following block at the end of `hooks/pre_task.sh`, after the scratchpad injection block:

```bash
# Recovery check — if pipeline was in progress when session died, output resume hint
if [ -f "pipeline_state.json" ]; then
    export RECOVERY_STATE_FILE="pipeline_state.json"
    STATUS=$(python3 -c "import json,os; d=json.load(open(os.environ['RECOVERY_STATE_FILE'])); print(d.get('status',''))" 2>/dev/null || echo "")
    if [ "$STATUS" = "running" ]; then
        echo "=== PIPELINE RECOVERY ===" >&2
        python3 - <<'PYEOF'
import json, os
d = json.load(open(os.environ["RECOVERY_STATE_FILE"]))
task = d.get("task_id", "unknown")
step = d.get("current_step", "unknown")
done = d.get("completed_steps", [])
print(f"RECOVERY: Task {task} was in progress at step '{step}'. Resume from '{step}'. Completed steps: {done}.")
PYEOF
        echo "========================" >&2
    fi
fi
```

- [ ] **Step 4: Run all pipeline state tests including the new recovery test**

```bash
bash hooks/tests/test_pipeline_state.sh
# Expected: all tests pass including new RECOVERY test
# Results: 13 passed, 0 failed
```

- [ ] **Step 5: Commit**

```bash
git add hooks/pre_task.sh hooks/tests/test_pipeline_state.sh
git commit -m "feat(pipeline): add session-start recovery hint from pipeline_state.json"
```

---

### Task 5: Update agent definitions to output JSON envelope

**Files:**
- Modify: `agents/coder.md`
- Modify: `agents/researcher.md`
- Modify: `agents/reviewer.md`
- Modify: `agents/tester.md`
- Modify: `agents/security.md`
- Modify: `agents/git.md`
- Modify: `agents/devops.md`
- Modify: `agents/memory.md`

Each agent's `## Output to orchestrator` section is replaced with a JSON envelope template. The `payload` field carries the same content the agent previously returned as prose. The orchestrator routes on `verdict`, not the prose content.

- [ ] **Step 1: Update agents/coder.md**

Replace the entire `## Output to orchestrator` section (currently the last section) with:

```markdown
## Output to orchestrator

Return a single JSON object — nothing else before or after it:

```json
{
  "task_id": "<task_id from your task entry>",
  "agent": "coder",
  "verdict": "DONE",
  "payload": {
    "files_changed": ["path/to/changed_file.py"],
    "decisions": [],
    "convention_gaps": []
  },
  "next_agent": "reviewer",
  "reason": null,
  "timestamp": "<ISO 8601 UTC, e.g. 2026-06-08T10:00:00Z>"
}
```

`verdict` is always `"DONE"`. `reason` is always `null`. `decisions` and `convention_gaps` follow the same rules as before — max 3 bullets each, only if non-obvious; `[]` otherwise.
```

- [ ] **Step 2: Update agents/researcher.md**

Replace the entire `## Output to orchestrator` section with:

```markdown
## Output to orchestrator

Return a single JSON object — nothing else before or after it:

```json
{
  "task_id": "<task_id from your task entry>",
  "agent": "researcher",
  "verdict": "DONE",
  "payload": {
    "facts_written": 3,
    "key_finding": "<one sentence>",
    "contradictions": []
  },
  "next_agent": "coder",
  "reason": null,
  "timestamp": "<ISO 8601 UTC>"
}
```

`verdict` is always `"DONE"`. `reason` is always `null`. `contradictions` is `[]` or a list of one-line conflict descriptions.
```

- [ ] **Step 3: Update agents/reviewer.md**

Replace the entire `## Output to orchestrator` section and the existing `## You produce` section with the following two sections:

Replace `## You produce` (currently defines the STATUS: PASS/FIX_REQUIRED block) with:

```markdown
## You produce

A single JSON object. Work through all five lenses first, then write the envelope — do not produce partial output mid-review.

**On PASS:**
```json
{
  "task_id": "<task_id>",
  "agent": "reviewer",
  "verdict": "PASS",
  "payload": {
    "required_changes": [],
    "convention_candidates": [],
    "lens_results": [
      "Lens 1 (Reliability): no violations",
      "Lens 2 (Domain skill): not provided — skipped",
      "Lens 3 (Spec coverage): all N criteria satisfied",
      "Lens 4 (Edge cases): all public functions handle obvious edge inputs",
      "Lens 5 (Conventions): no violations"
    ]
  },
  "next_agent": "tester",
  "reason": null,
  "timestamp": "<ISO 8601 UTC>"
}
```

**On FIX_REQUIRED:**
```json
{
  "task_id": "<task_id>",
  "agent": "reviewer",
  "verdict": "FIX_REQUIRED",
  "payload": {
    "required_changes": [
      "[file:line] Issue description. Expected: X. Found: Y. [Pattern/Lens ref]"
    ],
    "convention_candidates": []
  },
  "next_agent": "coder",
  "reason": "<one sentence summarising how many issues and which lens fired>",
  "timestamp": "<ISO 8601 UTC>"
}
```

`reason` is required when verdict is `FIX_REQUIRED`. `convention_candidates` follows the same rule as before — add when a pattern appears 3+ times in the diff.
```

Also remove the `## Output for STATUS: PASS` section (its per-lens text moves into `payload.lens_results` in the PASS envelope above) and the `## Output to orchestrator` section (now redundant — the envelope is the only output).

- [ ] **Step 4: Update agents/tester.md**

Replace the entire `## Output to orchestrator` section with:

```markdown
## Output to orchestrator

Return a single JSON object — nothing else before or after it:

**On PASS:**
```json
{
  "task_id": "<task_id>",
  "agent": "tester",
  "verdict": "PASS",
  "payload": {
    "tests_run": 5,
    "unit": 2,
    "integration": 2,
    "edge": 1
  },
  "next_agent": "security",
  "reason": null,
  "timestamp": "<ISO 8601 UTC>"
}
```

**On FAIL:**
```json
{
  "task_id": "<task_id>",
  "agent": "tester",
  "verdict": "FAIL",
  "payload": {
    "tests_run": 5,
    "passed": 3,
    "failures": [
      {"test": "test_login_with_expired_token", "reason": "AttributeError: 'NoneType' has no attribute 'token'"}
    ],
    "attempted_fix": "<one sentence describing what fix was tried>"
  },
  "next_agent": "coder",
  "reason": "<N tests failed after one fix attempt>",
  "timestamp": "<ISO 8601 UTC>"
}
```

`reason` is required when verdict is `FAIL`.
```

- [ ] **Step 5: Update agents/security.md**

Replace the entire `## You produce` section and `## Output to orchestrator` section with:

```markdown
## You produce

A single JSON object. Inspect the full diff against every rule in `security-rules.md`, then write the envelope.

**On PASS:**
```json
{
  "task_id": "<task_id>",
  "agent": "security",
  "verdict": "PASS",
  "payload": {"blockers": []},
  "next_agent": "git",
  "reason": null,
  "timestamp": "<ISO 8601 UTC>"
}
```

**On BLOCKED:**
```json
{
  "task_id": "<task_id>",
  "agent": "security",
  "verdict": "BLOCKED",
  "payload": {
    "blockers": [
      {
        "severity": "HIGH",
        "location": "src/auth.py:34",
        "description": "Hardcoded secret key in source file",
        "vector": "Source code exposure",
        "fix": "Move to environment variable"
      }
    ]
  },
  "next_agent": null,
  "reason": "<N blocker(s): one-line summary>",
  "timestamp": "<ISO 8601 UTC>"
}
```

`next_agent` is `null` when `BLOCKED` — this is a hard gate; the orchestrator stops the pipeline. `reason` is required when verdict is `BLOCKED`.
```

- [ ] **Step 6: Update agents/git.md**

Replace the entire `## Output to orchestrator` section with:

```markdown
## Output to orchestrator

Return a single JSON object — nothing else before or after it:

**On success:**
```json
{
  "task_id": "<task_id>",
  "agent": "git",
  "verdict": "COMMITTED",
  "payload": {
    "sha": "abc1234",
    "branch": "feat/30-pipeline-reliability",
    "message": "feat(pipeline): add validate_output.sh"
  },
  "next_agent": "memory",
  "reason": null,
  "timestamp": "<ISO 8601 UTC>"
}
```

**On push failure:**
```json
{
  "task_id": "<task_id>",
  "agent": "git",
  "verdict": "PUSH_FAILED",
  "payload": {"error": "<exact error from git push>", "sha": null},
  "next_agent": null,
  "reason": "<exact error — no destructive retry attempted>",
  "timestamp": "<ISO 8601 UTC>"
}
```

`reason` is required when verdict is `PUSH_FAILED`.
```

- [ ] **Step 7: Update agents/devops.md**

Replace the entire `## Output to orchestrator` section (last section, currently "Return only the NOTE lines...") with:

```markdown
## Output to orchestrator

Return a single JSON object — nothing else before or after it. Prepend any NOTE lines as a `notes` array in `payload`.

**On CI pass:**
```json
{
  "task_id": "<task_id passed by orchestrator>",
  "agent": "devops",
  "verdict": "PASS",
  "payload": {
    "ci_url": "https://github.com/owner/repo/actions/runs/12345",
    "smoke_test": "PASS",
    "notes": []
  },
  "next_agent": "memory",
  "reason": null,
  "timestamp": "<ISO 8601 UTC>"
}
```

`smoke_test` is `"PASS"`, `"SKIPPED"`, or `"FAILED"`. Set `verdict` to `"CI_FAILED"` when smoke test fails (not just CI).

**On CI or smoke test failure:**
```json
{
  "task_id": "<task_id>",
  "agent": "devops",
  "verdict": "CI_FAILED",
  "payload": {
    "workflow": "CI",
    "job": "test",
    "failure_reason": "pytest: 3 tests failed",
    "run_url": "https://github.com/owner/repo/actions/runs/12345",
    "notes": []
  },
  "next_agent": null,
  "reason": "<workflow/job: failure reason>",
  "timestamp": "<ISO 8601 UTC>"
}
```

`reason` is required when verdict is `CI_FAILED`. `next_agent` is `null` — the orchestrator marks all feature tasks `blocked`.
```

- [ ] **Step 8: Update agents/memory.md**

Replace the entire `## Output to orchestrator` section with:

```markdown
## Output to orchestrator

Return a single JSON object — nothing else before or after it:

**When tasks remain:**
```json
{
  "task_id": "<task_id just completed>",
  "agent": "memory",
  "verdict": "DONE",
  "payload": {
    "facts_added": 2,
    "queue_remaining": 3,
    "convention_candidates": []
  },
  "next_agent": null,
  "reason": null,
  "timestamp": "<ISO 8601 UTC>"
}
```

**When queue is drained:**
```json
{
  "task_id": "<task_id just completed>",
  "agent": "memory",
  "verdict": "DRAINED",
  "payload": {
    "facts_added": 1,
    "queue_remaining": 0,
    "convention_candidates": []
  },
  "next_agent": null,
  "reason": null,
  "timestamp": "<ISO 8601 UTC>"
}
```

`next_agent` is always `null` — the orchestrator decides what comes next (next task or DevOps). `verdict` is `"DRAINED"` when `grep -c "Status: pending\|Status: in_progress" TASKS.md` returns 0.
```

- [ ] **Step 9: Verify all agent files reference the envelope format**

```bash
for f in agents/coder.md agents/researcher.md agents/reviewer.md agents/tester.md agents/security.md agents/git.md agents/devops.md agents/memory.md; do
  grep -q '"verdict"' "$f" && echo "OK: $f" || echo "MISSING envelope in: $f"
done
# Expected: OK for all 8 files
```

- [ ] **Step 10: Verify no agent file still has the old prose-only output format**

```bash
grep -l "^Done\. Files changed:" agents/*.md
# Expected: no output (no files match)

grep -l "^Written N facts" agents/*.md
# Expected: no output

grep -l "^PASS — N tests" agents/*.md
# Expected: no output
```

- [ ] **Step 11: Commit**

```bash
git add agents/
git commit -m "feat(pipeline): update all agent definitions to output JSON envelope format"
```

---

### Task 6: Update orchestrator docs to use validate, advance, and verdict routing

**Files:**
- Modify: `.claude/orchestrator.md`
- Modify: `CLAUDE.md`

The per-task loop steps 8-13 in both files need to reflect: validate_output.sh call after each agent, advance_pipeline_state.sh after each handoff, and routing on `verdict` instead of prose.

- [ ] **Step 1: Update .claude/orchestrator.md per-task loop**

Find the section `**For every task:**`. Replace steps 8–13 (shown below in full so you know exactly what text to match) with the expanded version that follows.

**Current steps 8–13 — replace this entire block:**

```markdown
8. Invoke the `using-git-worktrees` skill to ensure an isolated workspace exists before dispatching any agent that will write files (Coder, Reviewer, Tester, Git, Memory, Writer). Background subagents require `EnterWorktree` to be called before any file write; without it the harness silently gates the write and the session stalls.
9. Before dispatching each agent: `bash .claude/hooks/log_agent.sh <agent_name> START`
10. Delegate to first agent in chosen pipeline with **surgical context** — only what they need
11. After each agent completes: `bash .claude/hooks/log_agent.sh <agent_name> END`
12. Memory agent (last in per-task pipeline) marks the task `completed` in `TASKS.md` — do not update it yourself
13. When Memory returns `Queue: DRAINED` — collect all commit SHAs produced by Git agents across this feature's tasks, then dispatch the end-of-feature pipeline: DevOps (branch name + commit SHAs + core.md) → Memory (final checkpoint)
```

**Replace with:**

```markdown
8. Invoke the `using-git-worktrees` skill to ensure an isolated workspace exists before dispatching any agent that will write files.
9. **Initialize pipeline state:**
   `bash hooks/init_pipeline_state.sh <task_id> <full|fast-track>`
10. For each agent in the chosen pipeline, run this loop:
    a. `bash .claude/hooks/log_agent.sh <agent_name> START`
    b. Dispatch agent with surgical context (task + relevant memory + skill files only)
    c. Agent returns a JSON envelope
    d. **Validate:** `bash hooks/validate_output.sh <agent_name> <<< <envelope>`
       - If exit 1: mark task `blocked` in TASKS.md, log `VALIDATION FAILED`, stop pipeline
    e. **Route** based on `envelope.verdict`:

       | Agent | Verdict | Next action |
       |---|---|---|
       | researcher | DONE | advance → coder |
       | coder | DONE | advance → reviewer |
       | reviewer | PASS | advance → tester |
       | reviewer | FIX_REQUIRED | advance → coder (one retry only; if FIX_REQUIRED again, mark blocked) |
       | tester | PASS | advance → security |
       | tester | FAIL | advance → coder (one retry only; if FAIL again, mark blocked) |
       | security | PASS | advance → git |
       | security | BLOCKED | mark task `blocked` in TASKS.md, log reason, **stop pipeline** |
       | git | COMMITTED | advance → memory |
       | git | PUSH_FAILED | log reason, **stop pipeline** |
       | devops | PASS | advance → memory (final checkpoint) |
       | devops | CI_FAILED | mark all feature tasks `blocked`, log reason, **stop pipeline** |
       | memory | DONE | `bash hooks/advance_pipeline_state.sh memory done` — pick next pending task |
       | memory | DRAINED | `bash hooks/advance_pipeline_state.sh memory done` — dispatch DevOps end-of-feature |

    f. `bash .claude/hooks/log_agent.sh <agent_name> END`
    g. `bash hooks/advance_pipeline_state.sh <completed_agent> <next_agent|done>`
11. When Memory returns `DRAINED` — collect all commit SHAs from Git agent payloads (`payload.sha`) across this feature's tasks, then dispatch the end-of-feature pipeline: DevOps → Memory.
```

- [ ] **Step 2: Update CLAUDE.md with the same changes**

CLAUDE.md mirrors `.claude/orchestrator.md` for the per-task loop. The text to match is identical — steps 8–13 read exactly the same as shown above. Apply the same replacement to the `**For every task:**` section in CLAUDE.md.

- [ ] **Step 3: Verify both files reference validate_output.sh and advance_pipeline_state.sh**

```bash
grep -l "validate_output" .claude/orchestrator.md CLAUDE.md
# Expected: both files listed

grep -l "advance_pipeline_state" .claude/orchestrator.md CLAUDE.md
# Expected: both files listed

grep -l '"verdict"' .claude/orchestrator.md CLAUDE.md
# Expected: both files listed
```

- [ ] **Step 4: Commit**

```bash
git add .claude/orchestrator.md CLAUDE.md
git commit -m "feat(pipeline): update orchestrator loop — validate envelopes, advance state, route on verdict"
```

---

### Task 7: Gitignore pipeline_state.json and run final verification

**Files:**
- Modify: `.gitignore`

- [ ] **Step 1: Add pipeline_state.json to .gitignore**

Add to `.gitignore` under the `# Hook runtime files` section:

```
pipeline_state.json
pipeline_state.json.tmp
```

- [ ] **Step 2: Verify pipeline_state.json is not tracked**

```bash
git check-ignore -v pipeline_state.json
# Expected: .gitignore:<line_number>:pipeline_state.json    pipeline_state.json
```

- [ ] **Step 3: Run the full test suite**

```bash
bash hooks/tests/test_validate_output.sh && bash hooks/tests/test_pipeline_state.sh
# Expected: all tests pass, 0 failed
```

- [ ] **Step 4: Run the verification commands from issue #30**

```bash
# Verify pipeline_state.json schema (after init)
bash hooks/init_pipeline_state.sh TASK-TEST full
cat pipeline_state.json | python3 -c "
import sys,json; d=json.load(sys.stdin)
print(d['current_step'], d['completed_steps'])
"
# Expected: researcher []

bash hooks/advance_pipeline_state.sh researcher coder
cat pipeline_state.json | python3 -c "
import sys,json; d=json.load(sys.stdin)
print(d['current_step'], d['completed_steps'])
"
# Expected: coder ['researcher']

# Verify free text is rejected
echo "looks good to me" | bash hooks/validate_output.sh reviewer
# Expected: exit 1 with VALIDATION FAILED message

# Verify contracts directory
ls contracts/
# Expected: coder.json devops.json git.json memory.json researcher.json reviewer.json security.json tester.json

# Clean up test state file
rm -f pipeline_state.json
```

- [ ] **Step 5: Final commit**

```bash
git add .gitignore
git commit -m "chore(pipeline): gitignore pipeline_state.json runtime file"
```

---

### Task 8: Update bootstrap.sh to move contracts/ into .claude/

**Context:** `bootstrap.sh` step 7/9 moves template infra dirs (`agents/`, `hooks/`, `skills/`, `tools/`) into `.claude/`. The new `contracts/` directory must be added to that list so bootstrapped projects end up with `.claude/contracts/` instead of `contracts/` at the project root.

`validate_output.sh` already handles both locations (added in Task 2) — it checks `.claude/contracts/` first, falls back to `contracts/`. No change needed there.

However, `bootstrap.sh` also patches `classify_task.sh` to update a hardcoded path pattern (`^hooks/` → `^.claude/hooks/`). There is no equivalent pattern for `contracts/` in `classify_task.sh`, so no extra patch is needed.

**Files:**
- Modify: `bootstrap.sh`

- [ ] **Step 1: Remove tests/ during bootstrap cleanup**

The `tests/` directory contains template-specific verification scripts (e.g. `verify_issue_30.sh`) that have no meaning in a bootstrapped project. Add a removal step alongside the existing `docs/superpowers/` and HTML cleanup block (around line 328 in bootstrap.sh):

Find this block:

```bash
# Remove ClaudeTemplate-specific HTML docs (architecture diagram + GitHub Pages index)
[[ -f "docs/ARCHITECTURE.html" ]] && rm -f docs/ARCHITECTURE.html && success "  Removed docs/ARCHITECTURE.html."
[[ -f "docs/index.html"        ]] && rm -f docs/index.html        && success "  Removed docs/index.html."
```

Add immediately after it:

```bash
# Remove template-specific verification scripts — new projects don't need ClaudeTemplate's own tests
if [[ -d "tests" ]]; then
  rm -rf tests/
  success "  Removed tests/ (ClaudeTemplate-specific verification scripts)."
fi
```

- [ ] **Step 2: Add contracts to the infra move loop in bootstrap.sh**

Find this block in `bootstrap.sh` (around line 369):

```bash
for dir in agents hooks skills tools; do
  if [[ -d "$dir" ]]; then
    mv "$dir" ".claude/$dir"
    success "  Moved $dir/ → .claude/$dir/."
  fi
done
```

Replace with:

```bash
for dir in agents hooks skills tools contracts; do
  if [[ -d "$dir" ]]; then
    mv "$dir" ".claude/$dir"
    success "  Moved $dir/ → .claude/$dir/."
  fi
done
```

The only change is adding `contracts` to the list. The `if [[ -d "$dir" ]]` guard means bootstrap won't fail on projects that don't have a `contracts/` dir yet.

- [ ] **Step 3: Verify both changes are correct**

```bash
grep "for dir in" bootstrap.sh
# Expected:
# for dir in agents hooks skills tools contracts; do

grep -A3 "ClaudeTemplate-specific verification" bootstrap.sh
# Expected:
# if [[ -d "tests" ]]; then
#   rm -rf tests/
```

- [ ] **Step 4: Test bootstrap moves contracts/ and removes tests/**

```bash
# Set up a throw-away clone to test the bootstrap steps in isolation
TMPDIR=$(mktemp -d)
cp -r . "$TMPDIR/template_test"
cd "$TMPDIR/template_test"
mkdir -p .claude

# Simulate tests/ removal
[[ -d "tests" ]] && rm -rf tests/

# Simulate infra move
for dir in agents hooks skills tools contracts; do
  [[ -d "$dir" ]] && mv "$dir" ".claude/$dir"
done

# Verify: tests/ gone from root
ls tests/ 2>&1
# Expected: ls: cannot access 'tests/': No such file or directory  (or similar)

# Verify: contracts/ gone from root
ls contracts/ 2>&1
# Expected: ls: cannot access 'contracts/': No such file or directory  (or similar)

# Verify: .claude/contracts/ has all 8 files
ls .claude/contracts/ | sort
# Expected: coder.json devops.json git.json memory.json researcher.json reviewer.json security.json tester.json

# Verify: validate_output.sh finds contracts at .claude/contracts/ (post-bootstrap path)
echo '{"task_id":"T-1","agent":"coder","verdict":"DONE","payload":{"files_changed":[],"decisions":[],"convention_gaps":[]},"next_agent":"reviewer","reason":null,"timestamp":"2026-06-08T10:00:00Z"}' \
  | bash .claude/hooks/validate_output.sh coder
# Expected: OK: coder verdict=DONE

# Clean up
cd -
rm -rf "$TMPDIR"
```

- [ ] **Step 5: Commit**

```bash
git add bootstrap.sh
git commit -m "feat(bootstrap): move contracts/ to .claude/ and remove tests/ on bootstrap"
```

---

### Task 9: End-to-end demo project verification and GitHub proof

**Goal:** Bootstrap a real demo project from the template, run a scripted pipeline simulation inside it, capture a structured report, and post it as a comment on GitHub issue #30. This is the proof that the feature works in a real bootstrapped project — not just in the template repo.

**What "proof" covers:**
1. Post-bootstrap structure — contracts moved, paths correct
2. All 8 contracts valid JSON
3. `validate_output.sh` accepts a valid envelope for every agent
4. `validate_output.sh` rejects: free text, missing field, invalid verdict, missing reason on verdict that requires it
5. `init_pipeline_state.sh` creates correct state for full and fast-track pipelines
6. `advance_pipeline_state.sh` transitions correctly through multiple steps
7. Recovery scenario: state shows `running` at mid-pipeline step → `pre_task.sh` outputs RECOVERY block
8. Post-bootstrap path resolution: contracts found at `.claude/contracts/`, not `contracts/`

**Files:**
- Create: `tests/verify_issue_30.sh`

- [ ] **Step 1: Write tests/verify_issue_30.sh**

```bash
#!/bin/bash
# End-to-end verification of issue #30 — pipeline reliability: state machine, contracts, validation.
# Bootstraps a demo project, runs structural + functional checks, generates a markdown report,
# and posts it as a comment on GitHub issue #30.
#
# Prerequisites: git, python3 (stdlib), gh CLI authenticated
# Usage: bash tests/verify_issue_30.sh [--dry-run]
#   --dry-run: print report to stdout only, do not post to GitHub
set -uo pipefail

DRY_RUN="${1:-}"
TEMPLATE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
REPORT_FILE="/tmp/issue_30_verification_$(date +%Y%m%d_%H%M%S).md"
DEMO_DIR=$(mktemp -d)
trap 'rm -rf "$DEMO_DIR"' EXIT

PASS=0; FAIL=0
REPORT_LINES=()

# ── Helpers ────────────────────────────────────────────────────────────────────

log()  { REPORT_LINES+=("$1"); }
check() {
    local name="$1" result="$2"  # result: "pass" or "fail: <reason>"
    if [[ "$result" == "pass" ]]; then
        log "- [x] $name"
        PASS=$((PASS+1))
    else
        log "- [ ] **FAIL** $name — ${result#fail: }"
        FAIL=$((FAIL+1))
    fi
}
run_silent() { "$@" > /dev/null 2>&1; }

# ── Bootstrap a demo project ───────────────────────────────────────────────────

log "# Issue #30 Verification Report"
log ""
log "**Branch:** $(cd "$TEMPLATE_DIR" && git rev-parse --abbrev-ref HEAD)"
log "**Commit:** $(cd "$TEMPLATE_DIR" && git rev-parse --short HEAD)"
log "**Date:** $(date -u +"%Y-%m-%d %H:%M UTC")"
log "**Demo project:** \`$DEMO_DIR\`"
log ""
log "## 1. Bootstrap — Structure"
log ""

# Copy template to demo dir and run the infra-move step manually
# (full bootstrap requires interactive prompts; we replicate just the infra move)
cp -r "$TEMPLATE_DIR/." "$DEMO_DIR/"
cd "$DEMO_DIR"
git init -q
git config user.email "verify@test.com"
git config user.name "Verify"
git add . && git commit -q -m "init"
mkdir -p .claude

for dir in agents hooks skills tools contracts; do
    [[ -d "$dir" ]] && mv "$dir" ".claude/$dir"
done

# Patch hook paths (mirrors bootstrap.sh step 7/9)
python3 << 'PYEOF'
content = open('.claude/settings.json').read()
content = content.replace('${CLAUDE_PROJECT_DIR}/hooks/', '${CLAUDE_PROJECT_DIR}/.claude/hooks/')
open('.claude/settings.json', 'w').write(content)
PYEOF
sed -i.bak 's|\^hooks/|^\.claude/hooks/|g' .claude/hooks/classify_task.sh
rm -f .claude/hooks/classify_task.sh.bak

# Check 1: contracts/ gone from root
[[ ! -d "contracts" ]] \
    && check "contracts/ removed from project root" "pass" \
    || check "contracts/ removed from project root" "fail: contracts/ still exists at root"

# Check 1b: tests/ gone from root
[[ ! -d "tests" ]] \
    && check "tests/ removed from project root (template-specific scripts not copied)" "pass" \
    || check "tests/ removed from project root (template-specific scripts not copied)" "fail: tests/ still exists at root"

# Check 2: .claude/contracts/ exists
[[ -d ".claude/contracts" ]] \
    && check ".claude/contracts/ exists" "pass" \
    || check ".claude/contracts/ exists" "fail: .claude/contracts/ not found"

# Check 3: all 8 contract files present
CONTRACT_COUNT=$(ls .claude/contracts/*.json 2>/dev/null | wc -l | tr -d ' ')
[[ "$CONTRACT_COUNT" -eq 8 ]] \
    && check "all 8 contract files present in .claude/contracts/" "pass" \
    || check "all 8 contract files present in .claude/contracts/" "fail: found $CONTRACT_COUNT, expected 8"

# Check 4: all contracts are valid JSON
JSON_ERRORS=""
for f in .claude/contracts/*.json; do
    python3 -m json.tool "$f" > /dev/null 2>&1 || JSON_ERRORS="$JSON_ERRORS $f"
done
[[ -z "$JSON_ERRORS" ]] \
    && check "all contract files are valid JSON" "pass" \
    || check "all contract files are valid JSON" "fail: invalid JSON in$JSON_ERRORS"

# Check 5: .claude/hooks/validate_output.sh exists
[[ -f ".claude/hooks/validate_output.sh" ]] \
    && check "validate_output.sh present at .claude/hooks/" "pass" \
    || check "validate_output.sh present at .claude/hooks/" "fail: not found"

# Check 6: validate_output.sh resolves contracts from .claude/contracts/ (post-bootstrap path)
CONTRACTS_USED=$(bash .claude/hooks/validate_output.sh coder 2>&1 <<'EOF' || true
{"task_id":"T-1","agent":"coder","verdict":"DONE","payload":{},"next_agent":"reviewer","reason":null,"timestamp":"2026-06-08T10:00:00Z"}
EOF
)
[[ "$CONTRACTS_USED" == "OK"* ]] \
    && check "validate_output.sh resolves contracts at .claude/contracts/ (post-bootstrap path)" "pass" \
    || check "validate_output.sh resolves contracts at .claude/contracts/ (post-bootstrap path)" "fail: got: $CONTRACTS_USED"

log ""
log "## 2. validate_output.sh — Acceptance checks (one per agent)"
log ""

# Helper: assert valid envelope accepted
assert_valid() {
    local agent="$1" envelope="$2"
    result=$(echo "$envelope" | bash .claude/hooks/validate_output.sh "$agent" 2>&1) && EXIT=0 || EXIT=$?
    [[ "$EXIT" -eq 0 ]] \
        && check "valid $agent envelope accepted" "pass" \
        || check "valid $agent envelope accepted" "fail: $result"
}

assert_valid "coder" \
    '{"task_id":"T-1","agent":"coder","verdict":"DONE","payload":{"files_changed":["src/foo.py"],"decisions":[],"convention_gaps":[]},"next_agent":"reviewer","reason":null,"timestamp":"2026-06-08T10:00:00Z"}'

assert_valid "researcher" \
    '{"task_id":"T-1","agent":"researcher","verdict":"DONE","payload":{"facts_written":2,"key_finding":"JWT rotates daily","contradictions":[]},"next_agent":"coder","reason":null,"timestamp":"2026-06-08T10:00:00Z"}'

assert_valid "reviewer" \
    '{"task_id":"T-1","agent":"reviewer","verdict":"PASS","payload":{"required_changes":[],"convention_candidates":[],"lens_results":["Lens 1: no violations"]},"next_agent":"tester","reason":null,"timestamp":"2026-06-08T10:00:00Z"}'

assert_valid "tester" \
    '{"task_id":"T-1","agent":"tester","verdict":"PASS","payload":{"tests_run":4,"unit":2,"integration":1,"edge":1},"next_agent":"security","reason":null,"timestamp":"2026-06-08T10:00:00Z"}'

assert_valid "security" \
    '{"task_id":"T-1","agent":"security","verdict":"PASS","payload":{"blockers":[]},"next_agent":"git","reason":null,"timestamp":"2026-06-08T10:00:00Z"}'

assert_valid "git" \
    '{"task_id":"T-1","agent":"git","verdict":"COMMITTED","payload":{"sha":"abc1234","branch":"feat/30","message":"feat: add pipeline state"},"next_agent":"memory","reason":null,"timestamp":"2026-06-08T10:00:00Z"}'

assert_valid "devops" \
    '{"task_id":"T-1","agent":"devops","verdict":"PASS","payload":{"ci_url":"https://github.com/a/b/runs/1","smoke_test":"SKIPPED","notes":[]},"next_agent":"memory","reason":null,"timestamp":"2026-06-08T10:00:00Z"}'

assert_valid "memory" \
    '{"task_id":"T-1","agent":"memory","verdict":"DONE","payload":{"facts_added":1,"queue_remaining":2,"convention_candidates":[]},"next_agent":null,"reason":null,"timestamp":"2026-06-08T10:00:00Z"}'

log ""
log "## 3. validate_output.sh — Rejection checks"
log ""

# Helper: assert invalid envelope rejected
assert_rejected() {
    local name="$1" agent="$2" envelope="$3"
    echo "$envelope" | bash .claude/hooks/validate_output.sh "$agent" > /dev/null 2>&1 && EXIT=0 || EXIT=$?
    [[ "$EXIT" -ne 0 ]] \
        && check "$name" "pass" \
        || check "$name" "fail: expected rejection but got exit 0"
}

assert_rejected "free text rejected" "reviewer" \
    "looks good to me"

assert_rejected "missing required fields rejected" "coder" \
    '{"agent":"coder","verdict":"DONE"}'

assert_rejected "invalid verdict rejected" "reviewer" \
    '{"task_id":"T-1","agent":"reviewer","verdict":"MAYBE","payload":{},"next_agent":"tester","reason":null,"timestamp":"2026-06-08T10:00:00Z"}'

assert_rejected "FIX_REQUIRED without reason rejected" "reviewer" \
    '{"task_id":"T-1","agent":"reviewer","verdict":"FIX_REQUIRED","payload":{"required_changes":[],"convention_candidates":[]},"next_agent":"coder","reason":null,"timestamp":"2026-06-08T10:00:00Z"}'

assert_rejected "BLOCKED without reason rejected" "security" \
    '{"task_id":"T-1","agent":"security","verdict":"BLOCKED","payload":{"blockers":[{"severity":"HIGH","location":"foo.py:1","description":"x","vector":"y","fix":"z"}]},"next_agent":null,"reason":null,"timestamp":"2026-06-08T10:00:00Z"}'

assert_rejected "FAIL without reason rejected (tester)" "tester" \
    '{"task_id":"T-1","agent":"tester","verdict":"FAIL","payload":{"tests_run":3,"passed":1,"failures":[]},"next_agent":"coder","reason":null,"timestamp":"2026-06-08T10:00:00Z"}'

assert_rejected "PUSH_FAILED without reason rejected (git)" "git" \
    '{"task_id":"T-1","agent":"git","verdict":"PUSH_FAILED","payload":{"error":"rejected","sha":null},"next_agent":null,"reason":null,"timestamp":"2026-06-08T10:00:00Z"}'

assert_rejected "unknown agent rejected" "unknown" \
    '{"task_id":"T-1","agent":"unknown","verdict":"DONE","payload":{},"next_agent":null,"reason":null,"timestamp":"2026-06-08T10:00:00Z"}'

log ""
log "## 4. Pipeline state machine"
log ""

# Init full pipeline
bash .claude/hooks/init_pipeline_state.sh TASK-DEMO full > /dev/null
STATE=$(python3 -c "import json; d=json.load(open('pipeline_state.json')); print(d['current_step'], d['status'], d['pipeline'])")
[[ "$STATE" == "researcher running full" ]] \
    && check "init full pipeline: current_step=researcher, status=running" "pass" \
    || check "init full pipeline: current_step=researcher, status=running" "fail: got '$STATE'"

# Advance researcher → coder
bash .claude/hooks/advance_pipeline_state.sh researcher coder > /dev/null
STATE=$(python3 -c "import json; d=json.load(open('pipeline_state.json')); print(d['current_step'], 'researcher' in d['completed_steps'])")
[[ "$STATE" == "coder True" ]] \
    && check "advance researcher→coder: current_step=coder, researcher in completed_steps" "pass" \
    || check "advance researcher→coder: current_step=coder, researcher in completed_steps" "fail: got '$STATE'"

# Advance through the rest of the full pipeline
for step_pair in "coder reviewer" "reviewer tester" "tester security" "security git" "git memory"; do
    FROM="${step_pair% *}"; TO="${step_pair#* }"
    bash .claude/hooks/advance_pipeline_state.sh "$FROM" "$TO" > /dev/null
done

STATE=$(python3 -c "import json; d=json.load(open('pipeline_state.json')); print(d['current_step'], len(d['completed_steps']))")
[[ "$STATE" == "memory 6" ]] \
    && check "advance through all 6 pre-memory steps: current_step=memory, 6 in completed_steps" "pass" \
    || check "advance through all 6 pre-memory steps: current_step=memory, 6 in completed_steps" "fail: got '$STATE'"

# Advance to done
bash .claude/hooks/advance_pipeline_state.sh memory done > /dev/null
STATE=$(python3 -c "import json; d=json.load(open('pipeline_state.json')); print(d['status'], d['current_step'])")
[[ "$STATE" == "completed None" ]] \
    && check "advance to done: status=completed, current_step=None" "pass" \
    || check "advance to done: status=completed, current_step=None" "fail: got '$STATE'"

# Fast-track init
bash .claude/hooks/init_pipeline_state.sh TASK-FAST fast-track > /dev/null
STEP=$(python3 -c "import json; d=json.load(open('pipeline_state.json')); print(d['current_step'])")
[[ "$STEP" == "coder" ]] \
    && check "init fast-track pipeline: current_step=coder" "pass" \
    || check "init fast-track pipeline: current_step=coder" "fail: got '$STEP'"

log ""
log "## 5. Session recovery scenario"
log ""

# Set up a mid-pipeline state (simulating a crash after researcher)
bash .claude/hooks/init_pipeline_state.sh TASK-CRASH full > /dev/null
bash .claude/hooks/advance_pipeline_state.sh researcher coder > /dev/null
# pipeline_state.json now shows status=running, current_step=coder

# Run pre_task.sh (as if a new session started) and check for RECOVERY output
mkdir -p memory
RECOVERY_OUTPUT=$(echo '{"session_id":"new-session-abc"}' | bash .claude/hooks/pre_task.sh 2>&1 || true)
echo "$RECOVERY_OUTPUT" | grep -q "RECOVERY" \
    && check "pre_task.sh outputs RECOVERY block when pipeline_state.json shows running" "pass" \
    || check "pre_task.sh outputs RECOVERY block when pipeline_state.json shows running" "fail: RECOVERY not found in output"

echo "$RECOVERY_OUTPUT" | grep -q "coder" \
    && check "RECOVERY block names the interrupted step (coder)" "pass" \
    || check "RECOVERY block names the interrupted step (coder)" "fail: step name not found in recovery output"

echo "$RECOVERY_OUTPUT" | grep -q "TASK-CRASH" \
    && check "RECOVERY block names the task id (TASK-CRASH)" "pass" \
    || check "RECOVERY block names the task id (TASK-CRASH)" "fail: task id not found in recovery output"

log ""
log "### Recovery block output"
log ""
log '```'
log "$RECOVERY_OUTPUT"
log '```'

log ""
log "## Summary"
log ""
log "| Result | Count |"
log "|---|---|"
log "| ✅ Passed | $PASS |"
log "| ❌ Failed | $FAIL |"
log ""
if [[ "$FAIL" -eq 0 ]]; then
    log "**All $PASS checks passed.** Issue #30 acceptance criteria verified in a bootstrapped demo project."
else
    log "**$FAIL check(s) failed.** See items marked FAIL above."
fi
log ""
log "<details><summary>Pipeline state.json at end of verification</summary>"
log ""
log '```json'
log "$(cat pipeline_state.json 2>/dev/null || echo '{}')"
log '```'
log ""
log "</details>"

# ── Write report ───────────────────────────────────────────────────────────────

printf '%s\n' "${REPORT_LINES[@]}" > "$REPORT_FILE"
echo ""
echo "=== Verification complete: $PASS passed, $FAIL failed ==="
echo "Report written to: $REPORT_FILE"
cat "$REPORT_FILE"

[ "$FAIL" -ne 0 ] && exit 1

# ── Post to GitHub issue #30 ──────────────────────────────────────────────────

if [[ "$DRY_RUN" == "--dry-run" ]]; then
    echo ""
    echo "Dry run — skipping GitHub comment."
    exit 0
fi

if ! command -v gh &>/dev/null; then
    echo "ERROR: gh CLI not found. Install from https://cli.github.com/ then run:"
    echo "  gh issue comment 30 --repo sharmavipin1608/ClaudeTemplate --body-file $REPORT_FILE"
    exit 1
fi

gh issue comment 30 \
    --repo sharmavipin1608/ClaudeTemplate \
    --body-file "$REPORT_FILE"

echo "Posted verification report to GitHub issue #30."
```

- [ ] **Step 2: Make the script executable and run a dry run to confirm it works**

```bash
chmod +x tests/verify_issue_30.sh
bash tests/verify_issue_30.sh --dry-run
# Expected: all checks pass, report printed to stdout, no GitHub post
# Final line: === Verification complete: 34 passed, 0 failed ===
```

If any checks fail, fix the underlying issue (not the test) and re-run until all pass.

- [ ] **Step 3: Run for real and post to GitHub issue #30**

```bash
bash tests/verify_issue_30.sh
# Expected: all checks pass AND a comment is posted to https://github.com/sharmavipin1608/ClaudeTemplate/issues/30
```

Confirm the comment appears on the issue before moving on.

- [ ] **Step 4: Commit the verification script**

```bash
git add tests/verify_issue_30.sh
git commit -m "test(pipeline): add end-to-end verification script for issue #30"
```
