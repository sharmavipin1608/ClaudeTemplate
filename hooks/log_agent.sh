#!/bin/bash
# Records agent lifecycle events to logs/agent_calls.log AND logs/pipeline.jsonl.
#
# Usage:
#   bash hooks/log_agent.sh <agent> START [task_id] [pipeline]
#   bash hooks/log_agent.sh <agent> END   [task_id] [outcome] [next_agent] [reason] [retry]
#
# START args: agent, START, task_id (optional), pipeline:full|fast-track (optional)
# END args:   agent, END, task_id (optional), outcome:PASS|FAIL|BLOCKED|DONE|COMMITTED (optional),
#             next_agent (optional, "-" if none), reason (optional, "-" if none), retry:N (optional)

AGENT_NAME="${1:-unknown}"
EVENT="${2:-START}"
TASK_ID="${3:--}"
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
export LA_PROJECT_ROOT="$PROJECT_ROOT"
LOG_FILE="${PROJECT_ROOT}/logs/agent_calls.log"
PIPELINE_LOG="${PROJECT_ROOT}/logs/pipeline.jsonl"
mkdir -p "${PROJECT_ROOT}/logs"

TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Read run_id from pipeline_state.json if available — graceful fallback to empty string
RUN_ID="$(current_run_id)"
export LA_RUN_ID="$RUN_ID"

if [ "$EVENT" = "START" ]; then
    PIPELINE="${4:-unknown}"
    echo "${TIMESTAMP} | ${AGENT_NAME} | START | task:${TASK_ID} | pipeline:${PIPELINE}" >> "${LOG_FILE}"
    export LA_AGENT="$AGENT_NAME" LA_EVENT="START" LA_TASK="$TASK_ID" LA_PIPELINE="$PIPELINE" LA_TIMESTAMP="$TIMESTAMP"
    python3 - <<'PYEOF'
import json, os
from pathlib import Path
root = Path(os.environ.get("LA_PROJECT_ROOT", "."))
state_file = root / "pipeline_state.json"
if state_file.exists():
    with state_file.open() as f:
        s = json.load(f)
    s["agent_active"] = True
    tmp = str(state_file) + ".tmp"
    with open(tmp, "w") as f:
        json.dump(s, f, indent=2)
    os.replace(tmp, str(state_file))
record = {
    "event": "agent_start",
    "agent": os.environ["LA_AGENT"],
    "task_id": os.environ["LA_TASK"],
    "pipeline": os.environ["LA_PIPELINE"],
    "timestamp": os.environ["LA_TIMESTAMP"]
}
run_id = os.environ.get("LA_RUN_ID", "")
if run_id:
    record["run_id"] = run_id
p = root / "logs" / "pipeline.jsonl"
with p.open("a") as f:
    f.write(json.dumps(record) + "\n")
PYEOF
else
    # END event
    OUTCOME="${4:-unknown}"
    NEXT_AGENT="${5:--}"
    REASON="${6:--}"
    RETRY="${7:-0}"
    echo "${TIMESTAMP} | ${AGENT_NAME} | END | task:${TASK_ID} | outcome:${OUTCOME} | next:${NEXT_AGENT} | retry:${RETRY}" >> "${LOG_FILE}"
    export LA_AGENT="$AGENT_NAME" LA_EVENT="END" LA_TASK="$TASK_ID" LA_OUTCOME="$OUTCOME"
    export LA_NEXT="$NEXT_AGENT" LA_REASON="$REASON" LA_RETRY="$RETRY" LA_TIMESTAMP="$TIMESTAMP"
    python3 - <<'PYEOF'
import json, os
from pathlib import Path
root = Path(os.environ.get("LA_PROJECT_ROOT", "."))
state_file = root / "pipeline_state.json"
if state_file.exists():
    with state_file.open() as f:
        s = json.load(f)
    s["agent_active"] = False
    tmp = str(state_file) + ".tmp"
    with open(tmp, "w") as f:
        json.dump(s, f, indent=2)
    os.replace(tmp, str(state_file))
reason = os.environ["LA_REASON"]
record = {
    "event": "agent_end",
    "agent": os.environ["LA_AGENT"],
    "task_id": os.environ["LA_TASK"],
    "outcome": os.environ["LA_OUTCOME"],
    "next_agent": os.environ["LA_NEXT"] if os.environ["LA_NEXT"] != "-" else None,
    "reason": reason if reason != "-" else None,
    "retry": int(os.environ["LA_RETRY"]),
    "timestamp": os.environ["LA_TIMESTAMP"]
}
run_id = os.environ.get("LA_RUN_ID", "")
if run_id:
    record["run_id"] = run_id
p = root / "logs" / "pipeline.jsonl"
with p.open("a") as f:
    f.write(json.dumps(record) + "\n")
PYEOF
fi
