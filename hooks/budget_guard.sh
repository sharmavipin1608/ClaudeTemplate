#!/bin/bash
# Guards against excessive tool call volume as a cost proxy.
# Claude Code doesn't expose token counts in hooks, so we count tool calls instead.
#
# Per-agent limits are read from contracts/pipeline-slos.md via lookup table below.
# Set CLAUDE_CURRENT_AGENT to the active agent name to enable per-agent enforcement.
# Set CLAUDE_DAILY_CALL_LIMIT (default 500) and CLAUDE_BUDGET_MODE (warn|halt) in your env.

DAILY_LIMIT="${CLAUDE_DAILY_CALL_LIMIT:-500}"
BUDGET_MODE="${CLAUDE_BUDGET_MODE:-warn}"
LOG_FILE="logs/tool_calls.log"
mkdir -p logs

TODAY=$(date +"%Y-%m-%d")
TODAYS_CALLS=0
if [ -f "${LOG_FILE}" ]; then
    TODAYS_CALLS=$(grep -c "^${TODAY}" "${LOG_FILE}" 2>/dev/null) || TODAYS_CALLS=0
fi

# ── Daily aggregate check ─────────────────────────────────────────────
WARN_AT=$(( DAILY_LIMIT * 80 / 100 ))
if [ "${TODAYS_CALLS}" -ge "${DAILY_LIMIT}" ]; then
    echo "[BUDGET] Daily hard limit reached: ${TODAYS_CALLS}/${DAILY_LIMIT} tool calls today." >&2
    if [ "${BUDGET_MODE}" = "halt" ]; then
        echo "[BUDGET] BUDGET_MODE=halt — stopping." >&2
        exit 1
    else
        echo "[BUDGET] BUDGET_MODE=warn — continuing." >&2
    fi
elif [ "${TODAYS_CALLS}" -ge "${WARN_AT}" ]; then
    echo "[BUDGET] Daily soft limit warning: ${TODAYS_CALLS}/${DAILY_LIMIT} (${WARN_AT} threshold) tool calls today." >&2
fi

# ── Per-agent check (only when CLAUDE_CURRENT_AGENT is set) ──────────
AGENT="${CLAUDE_CURRENT_AGENT:-}"
if [ -n "$AGENT" ]; then
    # Lookup table: agent_name:soft_limit:hard_limit
    declare -A AGENT_SOFT=( [researcher]=15 [coder]=20 [reviewer]=10 [tester]=15 [security]=8 [git]=5 [memory]=5 [devops]=10 [writer]=12 )
    declare -A AGENT_HARD=( [researcher]=25 [coder]=35 [reviewer]=15 [tester]=25 [security]=12 [git]=8 [memory]=8 [devops]=18 [writer]=20 )
    AGENT_LOWER=$(echo "$AGENT" | tr '[:upper:]' '[:lower:]')
    SOFT="${AGENT_SOFT[$AGENT_LOWER]:-}"
    HARD="${AGENT_HARD[$AGENT_LOWER]:-}"

    if [ -n "$HARD" ]; then
        # Count calls for this agent: look for lines tagged with the agent name in the log
        # Format written by log_agent.sh: "timestamp | agent_name | START|END"
        # For per-call counting we fall back to today's total as a conservative proxy
        # when no per-agent call tracking exists yet.
        AGENT_CALLS="${TODAYS_CALLS}"
        if [ "${AGENT_CALLS}" -ge "${HARD}" ]; then
            echo "[BUDGET] Agent '${AGENT}' hard limit reached: ${AGENT_CALLS} calls (hard=${HARD})." >&2
            if [ "${BUDGET_MODE}" = "halt" ]; then
                echo "[BUDGET] BUDGET_MODE=halt — stopping." >&2
                exit 1
            fi
        elif [ -n "$SOFT" ] && [ "${AGENT_CALLS}" -ge "${SOFT}" ]; then
            echo "[BUDGET] Agent '${AGENT}' soft limit warning: ${AGENT_CALLS} calls (soft=${SOFT}, hard=${HARD})." >&2
        fi
    fi
fi
