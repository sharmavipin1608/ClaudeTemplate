#!/bin/bash
# Reads tool event JSON from stdin (Claude Code hook protocol).
# Appends to logs/tool_calls.log (existing flat format, unchanged).
# Also appends a structured tool_call event to logs/pipeline.jsonl when
# CLAUDE_TASK_ID and CLAUDE_CURRENT_AGENT env vars are set by the orchestrator.

TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
LOG_FILE="${PROJECT_ROOT}/logs/tool_calls.log"
PIPELINE_LOG="${PROJECT_ROOT}/logs/pipeline.jsonl"
mkdir -p "${PROJECT_ROOT}/logs"

# Capture stdin once — Claude Code passes event JSON
INPUT=$(cat)

TOOL_NAME=$(printf '%s' "$INPUT" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('tool_name','unknown'))" 2>/dev/null || echo "unknown")

# Always write flat log (existing format preserved)
echo "${TIMESTAMP} | ${TOOL_NAME}" >> "${LOG_FILE}"

# Write structured event to pipeline.jsonl only when agent context is available
TASK_ID="${CLAUDE_TASK_ID:-}"
AGENT="${CLAUDE_CURRENT_AGENT:-}"
if [ -n "$TASK_ID" ] && [ -n "$AGENT" ]; then
    # Read run_id from pipeline_state.json — graceful fallback to empty string
    LT_RUN_ID=$(python3 -c "import json; d=json.load(open('${PROJECT_ROOT}/pipeline_state.json')); print(d.get('run_id',''))" 2>/dev/null || echo "")
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

# Write last-tool-call timestamp for idle timeout detection (read by budget_guard.sh)
if [ -n "${CLAUDE_CURRENT_AGENT:-}" ]; then
  date +%s > "/tmp/claude_last_tool_${CLAUDE_CURRENT_AGENT}"
fi
