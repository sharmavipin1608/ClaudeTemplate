#!/bin/bash
# Fires on Claude Code Stop event. Reads stop_reason from stdin JSON.
# Silently exits on normal completion (end_turn). Logs and flags unexpected stops.
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
LOG_FILE="logs/tool_calls.log"
mkdir -p logs

INPUT=$(cat)
STOP_REASON=$(echo "$INPUT" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('stop_reason','unknown'))" 2>/dev/null || echo "unknown")

# Normal completion — nothing to do
if [ "$STOP_REASON" = "end_turn" ]; then
    exit 0
fi

# Unexpected stop — log it and note in scratchpad for next session
echo "${TIMESTAMP} | STOP | ${STOP_REASON}" >> "${LOG_FILE}"

if [ -f "memory/scratchpad.md" ]; then
    cat >> "memory/scratchpad.md" << EOF

## SESSION ENDED UNEXPECTEDLY (${TIMESTAMP})
Stop reason: ${STOP_REASON}
Action required: Review what was in progress and resume
EOF
fi

echo "[STOP] Session ended with reason '${STOP_REASON}'. See memory/scratchpad.md." >&2
