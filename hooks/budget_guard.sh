#!/bin/bash
# Guards against excessive tool call volume as a cost proxy.
# Claude Code doesn't expose token counts in hooks, so we count tool calls instead.
# Set CLAUDE_DAILY_CALL_LIMIT (default 500) and CLAUDE_BUDGET_MODE (warn|halt) in your env.
DAILY_LIMIT="${CLAUDE_DAILY_CALL_LIMIT:-500}"
BUDGET_MODE="${CLAUDE_BUDGET_MODE:-warn}"
LOG_FILE="logs/tool_calls.log"
mkdir -p logs

TODAY=$(date +"%Y-%m-%d")
TODAYS_CALLS=$(grep -c "^${TODAY}" "${LOG_FILE}" 2>/dev/null || echo 0)

if [ "${TODAYS_CALLS}" -ge "${DAILY_LIMIT}" ]; then
    echo "[BUDGET] Daily call limit reached: ${TODAYS_CALLS}/${DAILY_LIMIT} tool calls today." >&2
    if [ "${BUDGET_MODE}" = "halt" ]; then
        echo "[BUDGET] BUDGET_MODE=halt — stopping." >&2
        exit 1
    else
        echo "[BUDGET] BUDGET_MODE=warn — continuing." >&2
    fi
fi
