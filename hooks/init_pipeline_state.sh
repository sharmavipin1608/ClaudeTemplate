#!/bin/bash
# Initializes pipeline_state.json for a new task. Atomic write via .tmp → mv.
# Usage: bash hooks/init_pipeline_state.sh <task_id> <pipeline> ["<decision_reason>"]
# pipeline: full | fast-track
# decision_reason: optional one-line orchestrator reasoning for the pipeline
#                  choice (expected practice for AMBIGUOUS classifications)
set -euo pipefail

TASK_ID="${1:-}"
PIPELINE="${2:-}"
DECISION_REASON="${3:-}"

[ -z "$TASK_ID" ] && { echo "ERROR: task_id required" >&2; exit 1; }
[ -z "$PIPELINE" ] && { echo "ERROR: pipeline required (full|fast-track)" >&2; exit 1; }

source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

export INIT_REASON="$DECISION_REASON"
export INIT_VERDICT
INIT_VERDICT=$(cat "$CLAUDE_TMP_DIR/task_mode" 2>/dev/null || echo "UNKNOWN")

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
export INIT_RUN_ID
INIT_RUN_ID=$(python3 -c "import uuid; print(uuid.uuid4())")

python3 - <<'PYEOF'
import json, os

state = {
    "task_id": os.environ["INIT_TASK_ID"],
    "pipeline": os.environ["INIT_PIPELINE"],
    "run_id": os.environ["INIT_RUN_ID"],
    "started_at": os.environ["INIT_TIMESTAMP"],
    "current_step": os.environ["INIT_FIRST_STEP"],
    "completed_steps": [],
    "status": "running",
    "agent_active": False,
    "updated_at": os.environ["INIT_TIMESTAMP"]
}

state_file = os.environ["INIT_STATE_FILE"]
tmp = state_file + ".tmp"
with open(tmp, "w") as f:
    json.dump(state, f, indent=2)
os.replace(tmp, state_file)

log_dir = os.path.join(os.path.dirname(state_file), "logs")
os.makedirs(log_dir, exist_ok=True)
event = {
    "event": "pipeline_init",
    "task_id": state["task_id"],
    "pipeline": state["pipeline"],
    "run_id": state["run_id"],
    "classifier_verdict": os.environ.get("INIT_VERDICT", "UNKNOWN"),
    "decision_reason": os.environ.get("INIT_REASON") or None,
    "timestamp": state["started_at"],
}
with open(os.path.join(log_dir, "pipeline.jsonl"), "a") as f:
    f.write(json.dumps(event) + "\n")

print(f"Pipeline state initialized: {state['task_id']} / {state['pipeline']} → {state['current_step']}")
PYEOF
