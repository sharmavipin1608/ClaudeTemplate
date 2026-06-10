#!/bin/bash
# Guards against excessive tool call volume as a cost proxy.
# Claude Code doesn't expose token counts in hooks, so we count tool calls instead.
#
# Per-agent limits are read from contracts/pipeline-slos.md via lookup table below.
# Set CLAUDE_CURRENT_AGENT to the active agent name to enable per-agent enforcement.
# Set CLAUDE_DAILY_CALL_LIMIT (default 500) and CLAUDE_BUDGET_MODE (warn|halt) in your env.
# Set CLAUDE_IDLE_TIMEOUT_MINUTES (default 10) to control the per-agent idle timeout.
#   If no tool call is made for this many minutes, an idle warning (or halt) is triggered.

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
    # Lookup table: soft:hard limits per agent (bash 3.2 compatible — no declare -A)
    AGENT_LOWER=$(echo "$AGENT" | tr '[:upper:]' '[:lower:]')
    case "$AGENT_LOWER" in
        researcher) SOFT=15; HARD=25 ;;
        coder)      SOFT=20; HARD=35 ;;
        reviewer)   SOFT=10; HARD=15 ;;
        tester)     SOFT=15; HARD=25 ;;
        security)   SOFT=8;  HARD=12 ;;
        git)        SOFT=5;  HARD=8  ;;
        memory)     SOFT=5;  HARD=8  ;;
        devops)     SOFT=10; HARD=18 ;;
        writer)     SOFT=12; HARD=20 ;;
        *)          SOFT=""; HARD="" ;;
    esac

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

    # ── Per-agent idle timeout check ──────────────────────────────────
    # Fires only when a timestamp file exists from a previous tool call in this session.
    # First call of a session has no file yet — skip silently to avoid false positives.
    LAST_TOOL_FILE="/tmp/claude_last_tool_${AGENT}"
    if [ -f "$LAST_TOOL_FILE" ]; then
        LAST_TS=$(cat "$LAST_TOOL_FILE" 2>/dev/null || echo "")
        if [ -n "$LAST_TS" ]; then
            NOW_TS=$(date +%s)
            IDLE_SECS=$(( NOW_TS - LAST_TS ))
            IDLE_LIMIT=$(( ${CLAUDE_IDLE_TIMEOUT_MINUTES:-10} * 60 ))
            if [ "$IDLE_SECS" -ge "$IDLE_LIMIT" ]; then
                echo "[BUDGET] Agent '${AGENT}' idle for ${IDLE_SECS}s (limit=${IDLE_LIMIT}s — no tool call detected)." >&2
                if [ "${BUDGET_MODE}" = "halt" ]; then
                    echo "[BUDGET] BUDGET_MODE=halt — stopping." >&2
                    exit 1
                fi
            fi
        fi
    fi
fi
