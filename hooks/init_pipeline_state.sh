#!/bin/bash
# Initializes pipeline_state.json for a new task. Atomic write via .tmp → mv.
# Usage: bash hooks/init_pipeline_state.sh <task_id> <pipeline>
# pipeline: full | fast-track
set -euo pipefail

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
