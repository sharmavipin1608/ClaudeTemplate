#!/bin/bash
# Logs tool calls. Reads the hook event JSON from stdin.
#
# - Flat line to logs/tool_calls.log — PreToolUse only, so each call is
#   counted exactly once (this script is also safe if registered on Post).
# - Structured tool_call event to logs/pipeline.jsonl whenever a pipeline
#   run is active. Agent/task/run context comes from pipeline_state.json
#   via hooks/lib/common.sh — no env vars required.
# - Per-agent idle timestamp to .claude/tmp/ (read by budget_guard.sh).

source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
LOG_FILE="${PROJECT_ROOT}/logs/tool_calls.log"
mkdir -p "${PROJECT_ROOT}/logs"

INPUT=$(cat)

TOOL_NAME=$(printf '%s' "$INPUT" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('tool_name','unknown'))" 2>/dev/null || echo "unknown")
HOOK_EVENT=$(printf '%s' "$INPUT" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('hook_event_name',''))" 2>/dev/null || echo "")

# Only record the Pre side — Post would double-count every call.
if [ "$HOOK_EVENT" = "PostToolUse" ]; then
    exit 0
fi

echo "${TIMESTAMP} | ${TOOL_NAME}" >> "${LOG_FILE}"

TASK_ID="$(current_task_id)"
AGENT="$(current_agent)"
if [ -n "$TASK_ID" ] && [ -n "$AGENT" ]; then
    LT_RUN_ID="$(current_run_id)"
    export LT_TOOL="$TOOL_NAME" LT_TASK="$TASK_ID" LT_AGENT="$AGENT" LT_TIMESTAMP="$TIMESTAMP" LT_PROJECT_ROOT="$PROJECT_ROOT" LT_RUN_ID
    python3 - <<'PYEOF'
import json, os
from pathlib import Path
record = {
    "event": "tool_call",
    "tool": os.environ["LT_TOOL"],
    "agent": os.environ["LT_AGENT"],
    "task_id": os.environ["LT_TASK"],
    "timestamp": os.environ["LT_TIMESTAMP"]
}
run_id = os.environ.get("LT_RUN_ID", "")
if run_id:
    record["run_id"] = run_id
p = Path(os.environ["LT_PROJECT_ROOT"]) / "logs" / "pipeline.jsonl"
with p.open("a") as f:
    f.write(json.dumps(record) + "\n")
PYEOF
fi

# Idle-timeout timestamp (read by budget_guard.sh)
if [ -n "$AGENT" ]; then
    date +%s > "${CLAUDE_TMP_DIR}/last_tool_${AGENT}"
fi
