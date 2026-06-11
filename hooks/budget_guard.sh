#!/bin/bash
# Guards tool-call volume (cost proxy), per-agent budgets, wall-clock SLOs,
# and per-agent idle timeouts. Runs on PreToolUse.
#
# Limits come from contracts/pipeline-slos.md (tables are the source of
# truth). Agent/run context comes from pipeline_state.json via
# hooks/lib/common.sh; CLAUDE_CURRENT_AGENT overrides it for tests.
#
# Env:
#   CLAUDE_DAILY_CALL_LIMIT      default 500
#   CLAUDE_BUDGET_MODE           warn|halt (default warn)
#   CLAUDE_IDLE_TIMEOUT_MINUTES  default 10
#
# Exit codes: 0 = allow (warnings on stderr), 2 = BLOCK this tool call.
# Claude Code only blocks PreToolUse on exit 2 — exit 1 does NOT block.

source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

DAILY_LIMIT="${CLAUDE_DAILY_CALL_LIMIT:-500}"
BUDGET_MODE="${CLAUDE_BUDGET_MODE:-warn}"
LOG_FILE="${PROJECT_ROOT}/logs/tool_calls.log"
PIPELINE_LOG="${PROJECT_ROOT}/logs/pipeline.jsonl"

# SLO file: .claude/contracts/ after bootstrap, contracts/ in the template
if [ -f "${PROJECT_ROOT}/.claude/contracts/pipeline-slos.md" ]; then
    SLO_FILE="${PROJECT_ROOT}/.claude/contracts/pipeline-slos.md"
else
    SLO_FILE="${PROJECT_ROOT}/contracts/pipeline-slos.md"
fi

halt_or_warn() {
    echo "$1" >&2
    if [ "${BUDGET_MODE}" = "halt" ]; then
        echo "[BUDGET] BUDGET_MODE=halt — blocking tool call." >&2
        exit 2
    fi
}

# Parse "| name | <num> | <num> |" row from an SLO table. args: name
# Prints "soft hard" (or nothing if no row matches).
slo_limits() {
    awk -F'|' -v key="$1" '
        NF >= 4 {
            name = tolower($2); gsub(/^[ \t]+|[ \t]+$/, "", name)
            a = $3; gsub(/[ \t]/, "", a)
            b = $4; gsub(/[ \t]/, "", b)
            if (name == key && a ~ /^[0-9]+$/ && b ~ /^[0-9]+$/) { print a, b; exit }
        }' "$SLO_FILE" 2>/dev/null
}

# ── Daily aggregate (UTC — log timestamps are UTC) ─────────────────────
TODAY=$(date -u +"%Y-%m-%d")
TODAYS_CALLS=0
if [ -f "${LOG_FILE}" ]; then
    # Tool lines have exactly one " | " — CLASSIFIER/POST_TOOL/STOP markers have more
    TODAYS_CALLS=$(grep -cE "^${TODAY}T[0-9:]{8}Z \| [^|]+$" "${LOG_FILE}" 2>/dev/null) || TODAYS_CALLS=0
fi

WARN_AT=$(( DAILY_LIMIT * 80 / 100 ))
if [ "${TODAYS_CALLS}" -ge "${DAILY_LIMIT}" ]; then
    halt_or_warn "[BUDGET] Daily hard limit reached: ${TODAYS_CALLS}/${DAILY_LIMIT} tool calls today."
elif [ "${TODAYS_CALLS}" -ge "${WARN_AT}" ]; then
    echo "[BUDGET] Daily soft limit warning: ${TODAYS_CALLS}/${DAILY_LIMIT} (warn at ${WARN_AT})." >&2
fi

# ── Per-agent budget (per pipeline run) ────────────────────────────────
AGENT="$(current_agent)"
RUN_ID="$(current_run_id)"
if [ -n "$AGENT" ]; then
    AGENT_LOWER=$(echo "$AGENT" | tr '[:upper:]' '[:lower:]')
    LIMITS=$(slo_limits "$AGENT_LOWER")
    SOFT=$(echo "$LIMITS" | awk '{print $1}')
    HARD=$(echo "$LIMITS" | awk '{print $2}')

    if [ -n "$HARD" ]; then
        AGENT_CALLS=$(python3 - "$AGENT" "$RUN_ID" "$PIPELINE_LOG" <<'PYEOF'
import json, sys
agent, run_id, path = sys.argv[1], sys.argv[2], sys.argv[3]
n = 0
try:
    with open(path) as f:
        for line in f:
            try:
                d = json.loads(line)
            except json.JSONDecodeError:
                continue
            if d.get("event") != "tool_call" or d.get("agent") != agent:
                continue
            if run_id and d.get("run_id") != run_id:
                continue
            n += 1
except FileNotFoundError:
    pass
print(n)
PYEOF
)
        if [ "${AGENT_CALLS:-0}" -ge "${HARD}" ]; then
            halt_or_warn "[BUDGET] Agent '${AGENT}' hard limit reached: ${AGENT_CALLS} calls this run (hard=${HARD})."
        elif [ -n "$SOFT" ] && [ "${AGENT_CALLS:-0}" -ge "${SOFT}" ]; then
            echo "[BUDGET] Agent '${AGENT}' soft limit warning: ${AGENT_CALLS} calls this run (soft=${SOFT}, hard=${HARD})." >&2
        fi
    fi

    # ── Per-agent idle timeout (retrospective: evaluated on the NEXT call) ──
    LAST_TOOL_FILE="${CLAUDE_TMP_DIR}/last_tool_${AGENT}"
    if [ -f "$LAST_TOOL_FILE" ]; then
        LAST_TS=$(cat "$LAST_TOOL_FILE" 2>/dev/null || echo "")
        if [ -n "$LAST_TS" ]; then
            NOW_TS=$(date +%s)
            IDLE_SECS=$(( NOW_TS - LAST_TS ))
            IDLE_LIMIT=$(( ${CLAUDE_IDLE_TIMEOUT_MINUTES:-10} * 60 ))
            if [ "$IDLE_SECS" -ge "$IDLE_LIMIT" ]; then
                halt_or_warn "[BUDGET] Agent '${AGENT}' idle for ${IDLE_SECS}s (limit=${IDLE_LIMIT}s — no tool call detected)."
            fi
        fi
    fi
fi

# ── Wall-clock SLO for the active pipeline run ─────────────────────────
if [ "$(state_field status)" = "running" ]; then
    PIPELINE="$(state_field pipeline)"
    STARTED_AT="$(state_field started_at)"
    if [ -n "$PIPELINE" ] && [ -n "$STARTED_AT" ]; then
        WALL=$(slo_limits "$(echo "$PIPELINE" | tr '[:upper:]' '[:lower:]')")
        WALL_WARN=$(echo "$WALL" | awk '{print $1}')
        WALL_HALT=$(echo "$WALL" | awk '{print $2}')
        if [ -n "$WALL_HALT" ]; then
            START_EPOCH=$(python3 -c "from datetime import datetime; print(int(datetime.fromisoformat('${STARTED_AT}'.replace('Z','+00:00')).timestamp()))" 2>/dev/null || echo "")
            if [ -n "$START_EPOCH" ]; then
                ELAPSED=$(( $(date +%s) - START_EPOCH ))
                if [ "$ELAPSED" -ge "$WALL_HALT" ]; then
                    halt_or_warn "[BUDGET] Pipeline '${PIPELINE}' wall-clock budget exceeded: ${ELAPSED}s (halt=${WALL_HALT}s)."
                elif [ "$ELAPSED" -ge "$WALL_WARN" ]; then
                    echo "[BUDGET] Pipeline '${PIPELINE}' wall-clock warning: ${ELAPSED}s (warn=${WALL_WARN}s, halt=${WALL_HALT}s)." >&2
                fi
            fi
        fi
    fi
fi

exit 0
