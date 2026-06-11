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
