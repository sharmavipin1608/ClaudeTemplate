#!/bin/bash
# Check daily token spend. Warn or halt based on CLAUDE_BUDGET_MODE.
# Set CLAUDE_DAILY_TOKEN_LIMIT and CLAUDE_BUDGET_MODE in your environment
# or rely on defaults below.
DAILY_LIMIT="${CLAUDE_DAILY_TOKEN_LIMIT:-100000}"
BUDGET_MODE="${CLAUDE_BUDGET_MODE:-warn}"
TOKEN_LOG="logs/token_usage.log"
mkdir -p logs

TODAYS_TOKENS=0
if [ -f "${TOKEN_LOG}" ]; then
    TODAY=$(date +"%Y-%m-%d")
    TODAYS_TOKENS=$(grep "^${TODAY}" "${TOKEN_LOG}" \
        | awk -F'|' '{sum += $4 + $5} END {print sum+0}')
fi

if [ "${TODAYS_TOKENS}" -ge "${DAILY_LIMIT}" ]; then
    echo "[BUDGET] Daily limit reached: ${TODAYS_TOKENS}/${DAILY_LIMIT} tokens used today." >&2
    if [ "${BUDGET_MODE}" = "halt" ]; then
        echo "[BUDGET] BUDGET_MODE=halt — stopping." >&2
        exit 1
    else
        echo "[BUDGET] BUDGET_MODE=warn — continuing." >&2
    fi
fi
