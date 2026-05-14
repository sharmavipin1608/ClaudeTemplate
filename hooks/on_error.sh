#!/bin/bash
# On agent failure: log error, update scratchpad, requeue task.
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
ERROR_MSG="${CLAUDE_ERROR_MESSAGE:-Unknown error}"
CURRENT_TASK="${CLAUDE_CURRENT_TASK:-Unknown task}"
LOG_FILE="logs/tool_calls.log"
TASKS_FILE="TASKS.md"
mkdir -p logs

echo "${TIMESTAMP} | ERROR | ${CURRENT_TASK} | ${ERROR_MSG}" >> "${LOG_FILE}"

if [ -f "memory/scratchpad.md" ]; then
    cat >> "memory/scratchpad.md" << EOF

## ERROR (${TIMESTAMP})
Task: ${CURRENT_TASK}
Error: ${ERROR_MSG}
Action required: Investigate and retry
EOF
fi

if [ -f "${TASKS_FILE}" ]; then
    # Use perl for portable in-place edit (sed -i differs on macOS vs Linux)
    perl -i -pe "s/\[ \] \Q${CURRENT_TASK}\E/[FAILED] ${CURRENT_TASK} — ${TIMESTAMP}/" "${TASKS_FILE}"
fi

echo "[ERROR] Task failed: ${CURRENT_TASK}. Check logs/tool_calls.log for details." >&2
