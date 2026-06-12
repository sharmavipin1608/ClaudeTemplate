# Template Issues Fixes — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix 10 confirmed issues in ClaudeTemplate discovered during a live pipeline run on the ResearchAgent project.

**Architecture:** All fixes are in hooks/, agents/, contracts/, bootstrap.sh, and orchestrator docs. No new files except a hooks/README.md update. No dependencies between most tasks — Issues 1, 2, 9, 10 are fully independent; Issue 3 depends on Issue 2's contract format; Issue 7 depends on understanding Issue 1's fix.

**Tech Stack:** Bash, Python 3, JSON

---

## Working Notes (read before starting)

- Project root: `/Users/vipin/Projects/ClaudeTemplate`
- Hooks live at `hooks/` in the template repo (they get moved to `.claude/hooks/` only after `bootstrap.sh` runs). All edits in this plan target the template repo paths.
- Contracts live at `contracts/` in the template repo.
- `agents/changelog.md` and `agents/writer.md` do not return JSON envelopes — they are explicitly out of scope for Issue 2 and Issue 10.
- The orchestrator instructions exist in two places that must stay in sync:
  - `CLAUDE.md` (the master/source) — at project root
  - `.claude/orchestrator.md` (the bootstrap-time copy that gets imported via `@.claude/orchestrator.md`)
- Run all verification commands from the project root: `cd /Users/vipin/Projects/ClaudeTemplate`.

---

## Task 1 — Issues 9 + 10: bootstrap conventions move + drop timestamp from contracts

**Why grouped:** Both are small, fully independent, touch different files, and have no cross-dependency.

### Files

- `bootstrap.sh`
- `contracts/coder.json`
- `contracts/researcher.json`
- `contracts/reviewer.json`
- `contracts/tester.json`
- `contracts/security.json`
- `contracts/git.json`
- `contracts/devops.json`
- `contracts/memory.json`
- `contracts/changelog.json`
- `contracts/writer.json`

### Steps

- [ ] **Step 1.1 — Add `conventions` to the Step 7 loop in `bootstrap.sh`.**

  Locate this block in `bootstrap.sh` (currently around line 506-511):

  ```bash
  for dir in agents hooks skills tools contracts; do
    if [[ -d "$dir" ]]; then
      mv "$dir" ".claude/$dir"
      success "  Moved $dir/ → .claude/$dir/."
    fi
  done
  ```

  Replace it with:

  ```bash
  for dir in agents hooks skills tools contracts conventions; do
    if [[ -d "$dir" ]]; then
      mv "$dir" ".claude/$dir"
      success "  Moved $dir/ → .claude/$dir/."
    fi
  done
  ```

- [ ] **Step 1.2 — Remove `"timestamp"` from `required_fields` in every agent JSON contract.**

  For each of the 10 contracts below, replace the entire file contents with the corresponding block. The only change is removing `, "timestamp"` from `required_fields`.

  `contracts/coder.json`:
  ```json
  {
    "agent": "coder",
    "required_fields": ["task_id", "agent", "verdict", "payload", "next_agent"],
    "valid_verdicts": ["DONE"],
    "reason_required_on": []
  }
  ```

  `contracts/researcher.json`:
  ```json
  {
    "agent": "researcher",
    "required_fields": ["task_id", "agent", "verdict", "payload", "next_agent"],
    "valid_verdicts": ["DONE"],
    "reason_required_on": []
  }
  ```

  `contracts/reviewer.json`:
  ```json
  {
    "agent": "reviewer",
    "required_fields": ["task_id", "agent", "verdict", "payload", "next_agent"],
    "valid_verdicts": ["PASS", "FIX_REQUIRED"],
    "reason_required_on": ["FIX_REQUIRED"]
  }
  ```

  `contracts/tester.json`:
  ```json
  {
    "agent": "tester",
    "required_fields": ["task_id", "agent", "verdict", "payload", "next_agent"],
    "valid_verdicts": ["PASS", "FAIL"],
    "reason_required_on": ["FAIL"]
  }
  ```

  `contracts/security.json` (note: `required_payload_fields` is added in Task 4 — leave that for Task 4):
  ```json
  {
    "agent": "security",
    "required_fields": ["task_id", "agent", "verdict", "payload", "next_agent"],
    "valid_verdicts": ["PASS", "BLOCKED"],
    "reason_required_on": ["BLOCKED"]
  }
  ```

  `contracts/git.json`:
  ```json
  {
    "agent": "git",
    "required_fields": ["task_id", "agent", "verdict", "payload", "next_agent"],
    "valid_verdicts": ["COMMITTED", "PUSH_FAILED"],
    "reason_required_on": ["PUSH_FAILED"]
  }
  ```

  `contracts/devops.json`:
  ```json
  {
    "agent": "devops",
    "required_fields": ["task_id", "agent", "verdict", "payload", "next_agent"],
    "valid_verdicts": ["PASS", "CI_FAILED"],
    "reason_required_on": ["CI_FAILED"]
  }
  ```

  `contracts/memory.json`:
  ```json
  {
    "agent": "memory",
    "required_fields": ["task_id", "agent", "verdict", "payload", "next_agent"],
    "valid_verdicts": ["DONE", "DRAINED"],
    "reason_required_on": []
  }
  ```

  `contracts/changelog.json`:
  ```json
  {
    "agent": "changelog",
    "required_fields": ["task_id", "agent", "verdict", "payload", "next_agent"],
    "valid_verdicts": ["DONE"],
    "reason_required_on": []
  }
  ```

  `contracts/writer.json`:
  ```json
  {
    "agent": "writer",
    "required_fields": ["task_id", "agent", "verdict", "payload", "next_agent"],
    "valid_verdicts": ["DONE"],
    "reason_required_on": []
  }
  ```

### Verification

```bash
cd /Users/vipin/Projects/ClaudeTemplate

# 9. bootstrap.sh now references conventions in the move loop
grep -E "^for dir in" bootstrap.sh
# Expected: for dir in agents hooks skills tools contracts conventions; do

# 10. No contract still lists "timestamp" as a required field
! grep -l '"timestamp"' contracts/*.json
# Expected: command exits 0 (no matches) — but if it errors, list the offending files

# Sanity: every contract is still valid JSON
for f in contracts/*.json; do python3 -c "import json,sys; json.load(open('$f'))" && echo "OK $f"; done
# Expected: 11 lines each starting with "OK "

# Sanity: validate_output.sh still parses a sample envelope without "timestamp"
echo '{"task_id":"TASK-001","agent":"coder","verdict":"DONE","payload":{},"next_agent":"reviewer"}' \
  | bash hooks/validate_output.sh coder
# Expected: "OK: coder verdict=DONE"
```

### Commit

```bash
cd /Users/vipin/Projects/ClaudeTemplate
git add bootstrap.sh contracts/*.json
git commit -m "fix(template): move conventions/ in bootstrap step 7; drop timestamp from contracts (issues 9, 10)"
```

---

## Task 2 — Issues 1 + 7: stop double agent_start; emit session_start and pipeline_complete

**Why grouped:** Both touch `advance_pipeline_state.sh`; Issue 7's `pipeline_complete` lives in the same file as Issue 1's auto-emit removal. Issue 7's `session_start` lives in `session_context.sh`.

### Files

- `hooks/advance_pipeline_state.sh`
- `hooks/session_context.sh`

### Steps

- [ ] **Step 2.1 — Remove the auto-emit `agent_start` block from `advance_pipeline_state.sh` (Issue 1).**

  Open `hooks/advance_pipeline_state.sh`. Delete the trailing block (currently lines 61-66):

  ```bash
  # Auto-emit agent_start for the new step so timing is recorded even if the
  # orchestrator forgets to call log_agent.sh START explicitly.
  if [ "$NEXT" != "done" ]; then
      PIPELINE=$(python3 -c "import json; print(json.load(open('${STATE_FILE}'))['pipeline'])" 2>/dev/null || echo "unknown")
      bash "$(dirname "${BASH_SOURCE[0]}")/log_agent.sh" "$NEXT" START "$(state_field task_id)" "$PIPELINE"
  fi
  ```

  After deletion the file ends at the closing `PYEOF` on line 59.

- [ ] **Step 2.2 — Emit `pipeline_complete` when `NEXT == "done"` (Issue 7b).**

  Add this Python block inside the existing heredoc so it runs in the same atomic write — append it right before the closing `PYEOF` (after `print(f"State advanced: ...")`). The full replacement for the heredoc body (lines 24-59 of the original) is:

  ```bash
  python3 - <<'PYEOF'
  import json, os
  from pathlib import Path

  state_file = os.environ["ADVANCE_STATE_FILE"]
  with open(state_file) as f:
      state = json.load(f)

  completed = os.environ["ADVANCE_COMPLETED"]
  next_step = os.environ["ADVANCE_NEXT"]

  retries = state.setdefault("retries", {})
  if next_step != "done" and next_step in state["completed_steps"]:
      retries[next_step] = retries.get(next_step, 0) + 1
      state["completed_steps"].remove(next_step)

  if completed not in state["completed_steps"]:
      state["completed_steps"].append(completed)

  if next_step == "done":
      state["status"] = "completed"
      state["current_step"] = None
      state["agent_active"] = False
  else:
      state["current_step"] = next_step
      state["agent_active"] = False  # cleared at boundary; log_agent START will re-set

  state["updated_at"] = os.environ["ADVANCE_TIMESTAMP"]

  tmp = state_file + ".tmp"
  with open(tmp, "w") as f:
      json.dump(state, f, indent=2)
  os.replace(tmp, state_file)

  current = state.get("current_step") or "none"
  print(f"State advanced: completed={state['completed_steps']} next={current} status={state['status']}")

  # Emit pipeline_complete to pipeline.jsonl when the run is finished.
  if next_step == "done":
      project_root = Path(state_file).parent
      log_dir = project_root / "logs"
      log_dir.mkdir(exist_ok=True)
      event = {
          "event": "pipeline_complete",
          "task_id": state.get("task_id"),
          "pipeline": state.get("pipeline"),
          "run_id": state.get("run_id"),
          "completed_steps": state.get("completed_steps", []),
          "status": state.get("status"),
          "timestamp": state["updated_at"],
      }
      with (log_dir / "pipeline.jsonl").open("a") as f:
          f.write(json.dumps(event) + "\n")
  PYEOF
  ```

  After this step, the full final file is:

  ```bash
  #!/bin/bash
  # Advances pipeline_state.json to the next step. Atomic write via .tmp → mv.
  # Usage: bash hooks/advance_pipeline_state.sh <completed_step> <next_step|done>
  # Pass "done" as next_step when the pipeline completes.
  set -euo pipefail

  COMPLETED="${1:-}"
  NEXT="${2:-}"

  [ -z "$COMPLETED" ] && { echo "ERROR: completed_step required" >&2; exit 1; }
  [ -z "$NEXT" ] && { echo "ERROR: next_step required (or 'done')" >&2; exit 1; }

  source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
  STATE_FILE="$PROJECT_ROOT/pipeline_state.json"

  [ ! -f "$STATE_FILE" ] && { echo "ERROR: pipeline_state.json not found — call init_pipeline_state.sh first" >&2; exit 1; }

  export ADVANCE_COMPLETED="$COMPLETED"
  export ADVANCE_NEXT="$NEXT"
  export ADVANCE_STATE_FILE="$STATE_FILE"
  export ADVANCE_TIMESTAMP
  ADVANCE_TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  python3 - <<'PYEOF'
  import json, os
  from pathlib import Path

  state_file = os.environ["ADVANCE_STATE_FILE"]
  with open(state_file) as f:
      state = json.load(f)

  completed = os.environ["ADVANCE_COMPLETED"]
  next_step = os.environ["ADVANCE_NEXT"]

  retries = state.setdefault("retries", {})
  if next_step != "done" and next_step in state["completed_steps"]:
      retries[next_step] = retries.get(next_step, 0) + 1
      state["completed_steps"].remove(next_step)

  if completed not in state["completed_steps"]:
      state["completed_steps"].append(completed)

  if next_step == "done":
      state["status"] = "completed"
      state["current_step"] = None
      state["agent_active"] = False
  else:
      state["current_step"] = next_step
      state["agent_active"] = False

  state["updated_at"] = os.environ["ADVANCE_TIMESTAMP"]

  tmp = state_file + ".tmp"
  with open(tmp, "w") as f:
      json.dump(state, f, indent=2)
  os.replace(tmp, state_file)

  current = state.get("current_step") or "none"
  print(f"State advanced: completed={state['completed_steps']} next={current} status={state['status']}")

  if next_step == "done":
      project_root = Path(state_file).parent
      log_dir = project_root / "logs"
      log_dir.mkdir(exist_ok=True)
      event = {
          "event": "pipeline_complete",
          "task_id": state.get("task_id"),
          "pipeline": state.get("pipeline"),
          "run_id": state.get("run_id"),
          "completed_steps": state.get("completed_steps", []),
          "status": state.get("status"),
          "timestamp": state["updated_at"],
      }
      with (log_dir / "pipeline.jsonl").open("a") as f:
          f.write(json.dumps(event) + "\n")
  PYEOF
  ```

- [ ] **Step 2.3 — Emit `session_start` from `session_context.sh` (Issue 7a).**

  In `hooks/session_context.sh`, insert a new block right before `exit 0` at the end of the file. The full new file is:

  ```bash
  #!/bin/bash
  # SessionStart hook — injects project memory and pipeline recovery state
  # into the model's context. SessionStart STDOUT is added to context;
  # stderr (and PreToolUse stdout) is not — which is why this replaced the
  # old pre_task.sh PreToolUse/stderr approach.

  source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

  cat > /dev/null  # consume stdin per hook protocol

  MEMORY_DIR="${PROJECT_ROOT}/memory"

  if [ -f "${MEMORY_DIR}/core.md" ]; then
      echo "=== PROJECT CORE ==="
      cat "${MEMORY_DIR}/core.md"
      echo "===================="
  fi

  if [ -f "${MEMORY_DIR}/session_checkpoint.md" ]; then
      CHECKPOINT_SIZE=$(wc -c < "${MEMORY_DIR}/session_checkpoint.md")
      if [ "${CHECKPOINT_SIZE}" -gt 50 ]; then
          echo "=== SESSION CHECKPOINT ==="
          cat "${MEMORY_DIR}/session_checkpoint.md"
          echo "=========================="
      fi
  fi

  if [ -f "${MEMORY_DIR}/scratchpad.md" ]; then
      SCRATCHPAD_SIZE=$(wc -c < "${MEMORY_DIR}/scratchpad.md")
      if [ "${SCRATCHPAD_SIZE}" -gt 100 ]; then
          echo "=== SCRATCHPAD ==="
          cat "${MEMORY_DIR}/scratchpad.md"
          echo "=================="
      fi
  fi

  # Pipeline recovery: if a run was mid-flight when the last session ended,
  # tell the orchestrator exactly where to resume.
  if [ "$(state_field status)" = "running" ]; then
      TASK="$(state_field task_id)"
      STEP="$(state_field current_step)"
      DONE="$(state_field completed_steps)"
      echo "=== PIPELINE RECOVERY ==="
      echo "RECOVERY: Task ${TASK} was in progress at step '${STEP}'. Resume from '${STEP}' — do not restart the pipeline."
      echo "Completed steps: ${DONE}"
      echo "========================="
  fi

  # Cross-session orchestration warning (Issue 8):
  # If pipeline_state.json exists but the active branch / cwd does not match the
  # run's working tree, the orchestrator is likely running cross-project and
  # PreToolUse hooks (budget_guard, classify_task) will NOT fire here.
  if [ -f "$PROJECT_ROOT/pipeline_state.json" ]; then
      RUN_STATUS="$(state_field status)"
      RUN_ROOT="$(state_field project_root)"
      if [ "$RUN_STATUS" = "running" ] && [ -n "$RUN_ROOT" ] && [ "$RUN_ROOT" != "$PROJECT_ROOT" ]; then
          echo "=== CROSS-SESSION WARNING ==="
          echo "WARN: pipeline_state.json references project_root='${RUN_ROOT}' but this session runs at '${PROJECT_ROOT}'."
          echo "WARN: PreToolUse hooks (budget_guard, classify_task) will NOT fire for the other project."
          echo "WARN: See .claude/hooks/README.md → 'Cross-session orchestration'."
          echo "============================="
      fi
  fi

  # Emit a session_start event to pipeline.jsonl so replay tools can
  # identify session boundaries.
  export SC_PROJECT_ROOT="$PROJECT_ROOT"
  export SC_RUN_ID
  SC_RUN_ID="$(current_run_id)"
  python3 - <<'PYEOF'
  import json, os
  from pathlib import Path
  from datetime import datetime, timezone
  project_root = Path(os.environ.get("SC_PROJECT_ROOT", "."))
  log_dir = project_root / "logs"
  log_dir.mkdir(exist_ok=True)
  record = {
      "event": "session_start",
      "timestamp": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
      "project_root": str(project_root),
  }
  run_id = os.environ.get("SC_RUN_ID", "")
  if run_id:
      record["run_id"] = run_id
  with (log_dir / "pipeline.jsonl").open("a") as f:
      f.write(json.dumps(record) + "\n")
  PYEOF

  exit 0
  ```

  Note: the cross-session warning is added now because `session_context.sh` is the natural place — it requires no extra edits in Task 7 beyond the docs update.

### Verification

```bash
cd /Users/vipin/Projects/ClaudeTemplate

# Issue 1: verify auto-emit block is gone
! grep -F "Auto-emit agent_start" hooks/advance_pipeline_state.sh
# Expected: exits 0 (no match)

# Issue 7a: invoke session_context.sh and confirm session_start lands in pipeline.jsonl
mkdir -p logs && : > logs/pipeline.jsonl
echo '{}' | bash hooks/session_context.sh >/dev/null
tail -1 logs/pipeline.jsonl | python3 -c "import sys,json; d=json.loads(sys.stdin.read()); assert d['event']=='session_start', d; print('OK session_start emitted')"
# Expected: "OK session_start emitted"

# Issue 7b: simulate a completed pipeline_state and verify pipeline_complete emits
cat > pipeline_state.json <<'JSON'
{"task_id":"TASK-TEST","pipeline":"full","run_id":"00000000-test","started_at":"2026-06-12T00:00:00Z","current_step":"memory","completed_steps":["researcher","coder","reviewer","tester","security","git"],"status":"running","agent_active":false,"updated_at":"2026-06-12T00:00:00Z"}
JSON
bash hooks/advance_pipeline_state.sh memory done
tail -1 logs/pipeline.jsonl | python3 -c "import sys,json; d=json.loads(sys.stdin.read()); assert d['event']=='pipeline_complete' and d['status']=='completed', d; print('OK pipeline_complete emitted')"
# Expected: "OK pipeline_complete emitted"
rm -f pipeline_state.json
```

### Commit

```bash
cd /Users/vipin/Projects/ClaudeTemplate
git add hooks/advance_pipeline_state.sh hooks/session_context.sh
git commit -m "fix(hooks): stop double agent_start; emit session_start and pipeline_complete events (issues 1, 7)"
```

---

## Task 3 — Issue 2: stop fabricating agent timestamps

**Goal:** Agents stop returning `"timestamp"` in their envelopes; `validate_output.sh` stamps it with the real wall clock; contracts already updated in Task 1.

### Files

- `hooks/validate_output.sh`
- `agents/researcher.md`
- `agents/coder.md`
- `agents/reviewer.md`
- `agents/tester.md`
- `agents/security.md`
- `agents/git.md`
- `agents/devops.md`
- `agents/memory.md`

(`agents/changelog.md` and `agents/writer.md` do not emit JSON envelopes — skip them.)

### Steps

- [ ] **Step 3.1 — Have `validate_output.sh` stamp `timestamp` from the real wall clock.**

  Replace the block that currently sets `validated_at` (lines 76-94 of `hooks/validate_output.sh`) with:

  ```python
  # Append validated envelope to pipeline.jsonl, injecting run_id and a
  # real wall-clock timestamp. The agent-supplied timestamp (if any) is
  # ignored — agents fabricate placeholder values they have no way to know.
  try:
      log_dir = Path(project_root) / "logs"
      log_dir.mkdir(exist_ok=True)
      pipeline_log = log_dir / "pipeline.jsonl"
      now_iso = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
      run_id = os.environ.get("VALIDATE_RUN_ID", "")
      if run_id:
          envelope["run_id"] = run_id
      envelope.setdefault("event", "agent_envelope")
      # Authoritative wall-clock stamp — overwrites any agent-supplied value.
      envelope["timestamp"] = now_iso
      envelope["validated_at"] = now_iso
      with pipeline_log.open("a") as f:
          f.write(json.dumps(envelope) + "\n")
  except Exception as e:
      # Non-fatal: validation succeeded; log the write failure to stderr only
      print(f"WARN: failed to write to pipeline.jsonl: {e}", file=sys.stderr)
  ```

  We keep `validated_at` for downstream consumers that may already read it, AND we now write `timestamp` with the same value. Contracts (Task 1) no longer require `timestamp` to be present from the agent, so this is a pure addition.

- [ ] **Step 3.2 — Remove the `timestamp` field from every agent envelope template.**

  In each agent file below, delete the `"timestamp": "<ISO 8601 ...>"` line AND the trailing comma on the previous line. Also delete any prose that asks the agent to supply a timestamp.

  `agents/researcher.md` — In the JSON example, change:
  ```json
    "reason": null,
    "timestamp": "<ISO 8601 UTC>"
  }
  ```
  to:
  ```json
    "reason": null
  }
  ```

  `agents/coder.md` — change:
  ```json
    "reason": null,
    "timestamp": "<ISO 8601 UTC, e.g. 2026-06-08T10:00:00Z>"
  }
  ```
  to:
  ```json
    "reason": null
  }
  ```

  `agents/reviewer.md` — apply the same edit to both envelope blocks (PASS and FIX_REQUIRED). Each `"timestamp": "<ISO 8601 UTC>"` line and the trailing comma before it must be removed.

  `agents/tester.md` — apply the same edit to both envelope blocks (PASS and FAIL).

  `agents/security.md` — apply the same edit to both envelope blocks (PASS and BLOCKED).

  `agents/git.md` — apply the same edit to both envelope blocks (COMMITTED and PUSH_FAILED).

  `agents/devops.md` — apply the same edit to both envelope blocks (PASS and CI_FAILED).

  `agents/memory.md` — apply the same edit to both envelope blocks (DONE and DRAINED). Leave the `outcome_link` event example untouched — that is a separate `pipeline.jsonl` event the Memory agent writes itself, not an envelope, and the Memory agent already has tooling to stamp it correctly.

- [ ] **Step 3.3 — Add an explicit note to each agent file's "You produce" / "Output" section.**

  At the top of the JSON envelope section in each of the 8 agent files (researcher, coder, reviewer, tester, security, git, devops, memory), add this one-line note above the first JSON example:

  ```
  > Do NOT include a `timestamp` field — `validate_output.sh` injects the real wall-clock timestamp on validation. Agent-supplied timestamps were always fabricated placeholders.
  ```

### Verification

```bash
cd /Users/vipin/Projects/ClaudeTemplate

# 3.1: validator stamps real timestamp, even though envelope omits it
: > logs/pipeline.jsonl
echo '{"task_id":"TASK-001","agent":"coder","verdict":"DONE","payload":{},"next_agent":"reviewer"}' \
  | bash hooks/validate_output.sh coder
# Expected: "OK: coder verdict=DONE"

tail -1 logs/pipeline.jsonl | python3 -c "
import sys, json, re
from datetime import datetime, timezone
d = json.loads(sys.stdin.read())
assert 'timestamp' in d, 'timestamp missing'
assert re.match(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z\$', d['timestamp']), d['timestamp']
# Sanity: stamped timestamp must be within 60s of now (real wall clock, not a placeholder)
stamped = datetime.strptime(d['timestamp'], '%Y-%m-%dT%H:%M:%SZ').replace(tzinfo=timezone.utc)
now = datetime.now(timezone.utc)
assert abs((now - stamped).total_seconds()) < 60, f'timestamp {d[\"timestamp\"]} is not within 60s of now {now}'
assert 'validated_at' in d
print('OK timestamp stamped:', d['timestamp'])
"
# Expected: "OK timestamp stamped: <current UTC time>"

# 3.2: no agent envelope template still mentions an ISO 8601 timestamp field
! grep -nE '"timestamp"\s*:\s*"<ISO' agents/*.md
# Expected: exits 0 (no matches)
```

### Commit

```bash
cd /Users/vipin/Projects/ClaudeTemplate
git add hooks/validate_output.sh agents/*.md
git commit -m "fix(template): stamp real wall-clock timestamp in validator; drop fabricated agent timestamps (issue 2)"
```

---

## Task 4 — Issue 3: enforce required payload fields for Security

**Goal:** Security envelopes can no longer pass validation with `payload: {}`. The contract gets a new optional `required_payload_fields` schema entry; `validate_output.sh` enforces it.

### Files

- `contracts/security.json`
- `hooks/validate_output.sh`

### Steps

- [ ] **Step 4.1 — Add `required_payload_fields` to `contracts/security.json`.**

  Replace the file with:

  ```json
  {
    "agent": "security",
    "required_fields": ["task_id", "agent", "verdict", "payload", "next_agent"],
    "valid_verdicts": ["PASS", "BLOCKED"],
    "reason_required_on": ["BLOCKED"],
    "required_payload_fields": ["findings"]
  }
  ```

  Note: `agents/security.md` currently uses `blockers` in its envelope example, not `findings`. That mismatch is an agent-prompt bug — fix it inside this same task so the contract and prompt stay consistent.

- [ ] **Step 4.2 — Update the Security agent envelope to use `findings`.**

  In `agents/security.md`, replace both envelope blocks (PASS and BLOCKED) with the versions below. Keep the Task 3 fix already applied (no `timestamp` field) and the Task 3 note (`Do NOT include a timestamp field...`) above them.

  PASS block (replaces the existing PASS envelope block under `**On PASS:**`):
  ```json
  {
    "task_id": "<task_id>",
    "agent": "security",
    "verdict": "PASS",
    "payload": {"findings": []},
    "next_agent": "git",
    "reason": null
  }
  ```

  BLOCKED block (replaces the existing BLOCKED envelope block under `**On BLOCKED:**`):
  ```json
  {
    "task_id": "<task_id>",
    "agent": "security",
    "verdict": "BLOCKED",
    "payload": {
      "findings": [
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
    "reason": "<N finding(s): one-line summary>"
  }
  ```

  Update any prose lower in the file that still says `blockers` (Rule 2 and the Containment line under Blast Radius use the word generically and can stay; but the explicit field name in the envelope schema must read `findings`).

- [ ] **Step 4.3 — Extend `validate_output.sh` to enforce `required_payload_fields`.**

  Insert the following check immediately after the existing verdict-validation block (after the `if "verdict" in envelope: ... ` block ends, and before `if errors:`). The exact replacement (new lines marked with a leading `+` in narrative; in the file just paste them in):

  ```python
  # Optional contract extension: enforce that named payload fields are present.
  required_payload_fields = contract.get("required_payload_fields", [])
  if required_payload_fields:
      payload = envelope.get("payload")
      if not isinstance(payload, dict):
          errors.append(f"payload must be an object when required_payload_fields is set (got {type(payload).__name__})")
      else:
          for field in required_payload_fields:
              if field not in payload:
                  errors.append(f"missing required payload field: 'payload.{field}'")
  ```

### Verification

```bash
cd /Users/vipin/Projects/ClaudeTemplate

# 4.1 + 4.3: empty payload now FAILS validation for security
: > logs/pipeline.jsonl
echo '{"task_id":"TASK-1","agent":"security","verdict":"PASS","payload":{},"next_agent":"git","reason":null}' \
  | bash hooks/validate_output.sh security
echo "exit=$?"
# Expected: VALIDATION FAILED on stderr; exit=1

# Payload with findings PASSES
echo '{"task_id":"TASK-1","agent":"security","verdict":"PASS","payload":{"findings":[]},"next_agent":"git","reason":null}' \
  | bash hooks/validate_output.sh security
# Expected: "OK: security verdict=PASS"

# Non-security agents are unaffected (no required_payload_fields set)
echo '{"task_id":"TASK-1","agent":"coder","verdict":"DONE","payload":{},"next_agent":"reviewer"}' \
  | bash hooks/validate_output.sh coder
# Expected: "OK: coder verdict=DONE"

# agents/security.md no longer uses "blockers" inside payload — only "findings"
! grep -E '"payload"\s*:\s*\{"blockers"' agents/security.md
# Expected: exits 0
```

### Commit

```bash
cd /Users/vipin/Projects/ClaudeTemplate
git add contracts/security.json hooks/validate_output.sh agents/security.md
git commit -m "fix(security): enforce required payload.findings field; align contract and agent prompt (issue 3)"
```

---

## Task 5 — Issue 6: classifier task-tag rules

**Goal:** Classifier reads the in-progress task's `**Tags:**` line and forces FORCE_FULL for sensitive domain tags, regardless of git state.

### Files

- `hooks/classify_task.sh`

### Steps

- [ ] **Step 5.1 — Add a tag-extraction step and a tag-based FORCE_FULL rule.**

  In `hooks/classify_task.sh`, insert the new rule immediately after the `# ── Hard rules: file path patterns ────────────────────────────────────` block and before the `# ── Structural signals ────────────────────────────────────` block. Concretely, paste this block right after the `file_matches "CLAUDE\.md|AGENTS\.md"   ... force_full "orchestrator config changed"` line:

  ```bash
  # ── Task-tag rules (description-driven, independent of git state) ──────
  # Read the **Tags:** line from the current in-progress task in TASKS.md.
  # A task with [api], [auth], [security], or [database] tags must run the
  # full pipeline even on a clean tree, because the next file write will
  # touch one of those domains.
  TASK_TAGS=$(grep -A20 "\*\*Status:\*\* in_progress" "$TASK_FILE" 2>/dev/null \
      | grep -m1 -oE "\*\*Tags:\*\*[^\n]*" \
      | sed -E 's/^\*\*Tags:\*\*\s*//' \
      | tr -d '\r')
  if [ -n "$TASK_TAGS" ]; then
      echo "$TASK_TAGS" | grep -qiE "\[(api|auth|security|database)\]" \
          && force_full "task tag triggers full pipeline: $(echo "$TASK_TAGS" | grep -oiE "\[(api|auth|security|database)\]" | head -1)"
  fi
  ```

  `force_full` already calls `exit 0` after writing the verdict, so no further rules run if this one fires.

### Verification

```bash
cd /Users/vipin/Projects/ClaudeTemplate

# Set up a scratch TASKS.md with an in-progress [api] task
TMPDIR=$(mktemp -d)
mkdir -p "$TMPDIR/.claude/tmp" "$TMPDIR/logs"
cat > "$TMPDIR/TASKS.md" <<'TASK'
### [TASK-999] Tag rule probe
**Status:** in_progress
**Priority:** medium
**Agent:** coder
**Tags:** [api] [core]

Probe task for the classifier tag rule.
TASK

# Run classifier with a clean tree (no git changes) — must FORCE_FULL on the tag
( cd "$TMPDIR" && git init -q && git add . && git commit -q -m init \
  && echo '{"tool_name":"Edit"}' \
     | bash /Users/vipin/Projects/ClaudeTemplate/hooks/classify_task.sh )
cat "$TMPDIR/.claude/tmp/task_mode"; echo
# Expected: FORCE_FULL
grep "CLASSIFIER" "$TMPDIR/logs/tool_calls.log" | tail -1
# Expected: REASON contains "task tag triggers full pipeline: [api]"

# Now flip the tag to a benign domain
sed -i.bak 's/\[api\] \[core\]/[ui]/' "$TMPDIR/TASKS.md"
rm -f "$TMPDIR/.claude/tmp/task_mode" "$TMPDIR/.claude/tmp/task_mode_hash"
( cd "$TMPDIR" && echo '{"tool_name":"Edit"}' \
   | bash /Users/vipin/Projects/ClaudeTemplate/hooks/classify_task.sh )
cat "$TMPDIR/.claude/tmp/task_mode"; echo
# Expected: AMBIGUOUS (no hard rule fires on a clean tree with [ui] tag)

rm -rf "$TMPDIR"
```

### Commit

```bash
cd /Users/vipin/Projects/ClaudeTemplate
git add hooks/classify_task.sh
git commit -m "fix(classifier): force full pipeline on sensitive task tags ([api],[auth],[security],[database]) (issue 6)"
```

---

## Task 6 — Issue 5: DevOps must fail when no git remote is configured

**Goal:** The DevOps agent's first step is now an explicit `git remote -v` check. Missing remote → `CI_FAILED` with an actionable reason — never `PASS`.

### Files

- `agents/devops.md`

### Steps

- [ ] **Step 6.1 — Insert a new Step 0 ("Verify remote") in `agents/devops.md`.**

  Add this new section between `## Steps (run in order, stop on first failure)` and the existing `### Step 1 — Resolve CI provider`. Renumbering subsequent steps is not required — the new step explicitly says "Step 0" and the existing numbering stays.

  ```markdown
  ### Step 0 — Verify a git remote is configured

  Before any CI check, confirm a remote exists for this repository:

  ```bash
  git remote -v
  ```

  - If the command output is empty (no remote configured), abort immediately with:
    ```json
    {
      "task_id": "<task_id>",
      "agent": "devops",
      "verdict": "CI_FAILED",
      "payload": {
        "failure_reason": "no git remote configured",
        "notes": ["Run: gh repo create <name> --private --source=. --remote=origin --push"]
      },
      "next_agent": null,
      "reason": "no git remote configured — run: gh repo create <name> --private --source=. --remote=origin --push"
    }
    ```
    Do NOT return `verdict: PASS` and `payload.pushed: false`. A missing remote means CI never ran and never can run — this is a hard CI failure, not a skip.
  - If at least one remote is listed, proceed to Step 1.
  ```

- [ ] **Step 6.2 — Strengthen Rule 5 in `agents/devops.md` and add a new Rule 8.**

  In the `## Rules` section, replace Rule 5 with:

  ```
  5. Never assume the repo or that a remote exists — always run `git remote -v` first and resolve the repo via `core.md` or `git remote get-url origin` before making any `gh` call. No remote → CI_FAILED, never PASS.
  ```

  And append at the end of the Rules list:

  ```
  8. Never report PASS when no remote is configured — a missing remote means no CI run exists or can exist
  ```

### Verification

```bash
cd /Users/vipin/Projects/ClaudeTemplate

# Confirm Step 0 exists and references git remote -v
grep -n "Step 0 — Verify a git remote is configured" agents/devops.md
# Expected: a line number is printed
grep -nE "git remote -v" agents/devops.md
# Expected: at least one match
grep -nE "no git remote configured" agents/devops.md
# Expected: at least two matches (envelope + reason)

# Confirm Rule 5 mentions "No remote → CI_FAILED, never PASS"
grep -nE "No remote → CI_FAILED, never PASS" agents/devops.md
# Expected: one match
```

### Commit

```bash
cd /Users/vipin/Projects/ClaudeTemplate
git add agents/devops.md
git commit -m "fix(devops): require git remote -v as Step 0; CI_FAILED when no remote configured (issue 5)"
```

---

## Task 7 — Issues 4 + 8: orchestrator DevOps start logging + cross-session warning docs

**Why grouped:** Both are pure documentation updates touching the orchestrator instructions and `hooks/README.md`. No code changes here.

### Files

- `CLAUDE.md`
- `.claude/orchestrator.md`
- `hooks/README.md`

### Steps

- [ ] **Step 7.1 — Add an explicit `log_agent.sh START` requirement for DevOps in CLAUDE.md.**

  In `CLAUDE.md`, locate this paragraph (currently line 80):

  ```
  11. When Memory returns `DRAINED` — collect all commit SHAs from Git agent payloads (`payload.sha`) across this feature's tasks, then dispatch the end-of-feature pipeline: DevOps → Memory.
  ```

  Replace it with:

  ```
  11. When Memory returns `DRAINED` — collect all commit SHAs from Git agent payloads (`payload.sha`) across this feature's tasks, then dispatch the end-of-feature pipeline: DevOps → Memory. For BOTH end-of-feature agents (DevOps and the final Memory), run the same per-step loop used for per-task agents — that is, call `bash hooks/log_agent.sh <agent> START <task_id> end-of-feature` before dispatch, and `bash hooks/log_agent.sh <agent> END <task_id> <verdict> <next|-> <reason|-> 0` after. Skipping the START call for DevOps leaves it visible only as an `agent_end` in the log.
  ```

- [ ] **Step 7.2 — Make the same edit in `.claude/orchestrator.md`.**

  In `.claude/orchestrator.md`, locate the matching paragraph (search for `When Memory returns \`DRAINED\``) and replace it with:

  ```
  11. When Memory returns `DRAINED` — collect all commit SHAs from Git agent payloads (`payload.sha`) across this feature's tasks, then dispatch the end-of-feature pipeline: DevOps → Memory. For BOTH end-of-feature agents (DevOps and the final Memory), run the same per-step loop used for per-task agents — that is, call `bash .claude/hooks/log_agent.sh <agent> START <task_id> end-of-feature` before dispatch, and `bash .claude/hooks/log_agent.sh <agent> END <task_id> <verdict> <next|-> <reason|-> 0` after. Skipping the START call for DevOps leaves it visible only as an `agent_end` in the log.
  ```

  (The only difference vs CLAUDE.md is the `.claude/hooks/` path prefix — `.claude/orchestrator.md` is the post-bootstrap copy.)

- [ ] **Step 7.3 — Add a cross-session orchestration warning section to `hooks/README.md`.**

  Append a new section to `hooks/README.md` (after the existing `## Logs` section, or at end of file if `## Logs` is the last section):

  ```markdown
  ---

  ## Cross-session orchestration (Issue 8)

  **Warning — this is a structural Claude Code limitation, not a bug.**

  Claude Code wires PreToolUse and SessionStart hooks to the project that owns the current Claude session (the project Claude Code was started against). When you run the orchestrator inside Project A's Claude session but it dispatches subagents that operate on Project B's files, **Project B's hooks never fire**.

  Concrete consequences when orchestrating Project B from Project A:

  - `budget_guard.sh` in Project B is never consulted — daily-call limits, per-agent budgets, and idle timeouts will NOT enforce on Project B's tool calls.
  - `classify_task.sh` in Project B is never consulted — `.claude/tmp/task_mode` is not refreshed, and the orchestrator may operate on a stale FORCE_FULL / AMBIGUOUS verdict.
  - `log_tool.sh` in Project B does not append to `logs/tool_calls.log` or `logs/pipeline.jsonl` for these tool calls. The pipeline trace will be missing tool_call events.
  - `pipeline_state.json` updates and `logs/pipeline.jsonl` writes that are made by `log_agent.sh` / `validate_output.sh` (called explicitly by the orchestrator) DO still land in Project B, because those scripts are invoked directly by the orchestrator with explicit paths.

  Detection: `session_context.sh` checks `pipeline_state.json` at session start. If a run is `status=running` and the `project_root` recorded in state does not match the current `PROJECT_ROOT`, it prints a `CROSS-SESSION WARNING` block into the session context so the orchestrator can react.

  Mitigation options:

  1. **Recommended:** Start a fresh Claude Code session in the target project. The hooks then fire normally.
  2. If you must orchestrate cross-project, drive the pipeline manually — accept that PreToolUse hooks will be inert and run `budget_guard.sh` and `classify_task.sh` by hand against the target project where appropriate.
  3. Do not rely on `logs/tool_calls.log` for budget accounting in cross-session runs; rely on `logs/pipeline.jsonl` `agent_end` events instead (those are written by the orchestrator's explicit `log_agent.sh` calls and still land correctly).
  ```

### Verification

```bash
cd /Users/vipin/Projects/ClaudeTemplate

# 7.1: CLAUDE.md mentions logging DevOps START explicitly
grep -nE "log_agent.sh <agent> START.*end-of-feature" CLAUDE.md
# Expected: at least one match

# 7.2: orchestrator.md mentions logging DevOps START explicitly (with .claude/ prefix)
grep -nE "\.claude/hooks/log_agent\.sh <agent> START.*end-of-feature" .claude/orchestrator.md
# Expected: at least one match

# 7.3: hooks/README.md has the cross-session section
grep -nE "Cross-session orchestration \(Issue 8\)" hooks/README.md
# Expected: one match
grep -nE "budget_guard\.sh in Project B is never consulted" hooks/README.md
# Expected: one match
```

### Commit

```bash
cd /Users/vipin/Projects/ClaudeTemplate
git add CLAUDE.md .claude/orchestrator.md hooks/README.md
git commit -m "docs: require log_agent.sh START for end-of-feature DevOps; document cross-session hook limitation (issues 4, 8)"
```

---

## Final Verification (all tasks complete)

After Task 7, run this end-to-end smoke pass from the project root:

```bash
cd /Users/vipin/Projects/ClaudeTemplate

# All contracts still parse
for f in contracts/*.json; do python3 -c "import json,sys; json.load(open('$f'))" || { echo "BAD $f"; exit 1; }; done && echo "OK contracts"

# All hook scripts still parse
for f in hooks/*.sh; do bash -n "$f" || { echo "BAD $f"; exit 1; }; done && echo "OK hook syntax"

# Sample envelope round-trip for every agent that emits one
: > logs/pipeline.jsonl
for a in researcher coder reviewer tester git devops memory; do
  echo "{\"task_id\":\"TASK-X\",\"agent\":\"$a\",\"verdict\":\"DONE\",\"payload\":{},\"next_agent\":null}" \
    | bash hooks/validate_output.sh "$a" 2>&1 | grep -E "^OK|VALIDATION FAILED"
done
# reviewer and tester have verdicts other than DONE; expect VALIDATION FAILED for them
# (invalid verdict 'DONE'). All others should print OK with the correct agent.

# Security needs findings + valid verdict
echo '{"task_id":"TASK-X","agent":"security","verdict":"PASS","payload":{"findings":[]},"next_agent":"git","reason":null}' \
  | bash hooks/validate_output.sh security
# Expected: OK: security verdict=PASS

# Last-line sanity: pipeline.jsonl entries all have a real (non-midnight) timestamp
python3 - <<'PY'
import json
ok = True
for line in open("logs/pipeline.jsonl"):
    d = json.loads(line)
    ts = d.get("timestamp") or d.get("validated_at")
    if ts and ts.endswith("T00:00:00Z"):
        print("BAD midnight timestamp:", d); ok = False
print("OK timestamps" if ok else "FAIL")
PY
```

---

## Summary of behavior changes

| # | Issue | After fix |
|---|---|---|
| 1 | Double agent_start | One `agent_start` per dispatch — orchestrator's explicit `log_agent.sh START` is the only source. |
| 2 | Fake midnight timestamps | Agents omit `timestamp`; `validate_output.sh` stamps it with real UTC wall clock (matches `validated_at`). |
| 3 | Empty security payload | Security envelopes must include `payload.findings` (array, can be empty); validator rejects bare `{}`. |
| 4 | DevOps START missing | Orchestrator docs require `log_agent.sh START` for end-of-feature DevOps (and final Memory). |
| 5 | DevOps PASS with no remote | DevOps Step 0 checks `git remote -v`; no remote → `CI_FAILED` with actionable reason. |
| 6 | Classifier always AMBIGUOUS | Classifier reads in-progress task `**Tags:**`; `[api]`, `[auth]`, `[security]`, `[database]` → FORCE_FULL. |
| 7 | No session boundaries | `session_context.sh` emits `session_start`; `advance_pipeline_state.sh` emits `pipeline_complete` on `done`. |
| 8 | Cross-session hooks silently inert | `hooks/README.md` warns; `session_context.sh` prints a `CROSS-SESSION WARNING` when state's project_root mismatches. |
| 9 | `conventions/` left at root | `bootstrap.sh` Step 7 now moves it into `.claude/conventions/`. |
| 10 | `timestamp` in required_fields | Removed from all 10 agent JSON contracts; field is no longer agent-supplied. |
