#!/bin/bash
# Fires on Claude Code Stop event. Reads stop_reason from stdin JSON.
# Defaults to end_turn (fail-safe) — only acts when stop_reason is explicitly not end_turn.
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
LOG_FILE="logs/tool_calls.log"
mkdir -p logs

INPUT=$(cat)
# Default to "end_turn" so an unparseable or missing stop_reason never false-fires.
STOP_REASON=$(echo "$INPUT" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('stop_reason','end_turn'))" 2>/dev/null || echo "end_turn")

# Normal completion or unparseable — nothing to do
if [ "$STOP_REASON" = "end_turn" ]; then
    exit 0
fi

# Extract background_tasks list (added in Claude Code 2.1.147)
BG_TASKS=$(echo "$INPUT" | python3 -c "
import json, sys
d = json.load(sys.stdin)
tasks = d.get('background_tasks', [])
if tasks:
    print('\n'.join(f\"  - {t.get('id','?')}: {t.get('status','?')}\" for t in tasks))
" 2>/dev/null || echo "")

# Unexpected stop (max_tokens, error, etc.) — log and note in scratchpad for next session
echo "${TIMESTAMP} | STOP | ${STOP_REASON}" >> "${LOG_FILE}"

if [ -f "memory/scratchpad.md" ]; then
    if [ -n "$BG_TASKS" ]; then
        cat >> "memory/scratchpad.md" << EOF

## SESSION ENDED UNEXPECTEDLY (${TIMESTAMP})
Stop reason: ${STOP_REASON}
Background tasks at stop:
${BG_TASKS}
Action required: Review what was in progress and resume
EOF
    else
        cat >> "memory/scratchpad.md" << EOF

## SESSION ENDED UNEXPECTEDLY (${TIMESTAMP})
Stop reason: ${STOP_REASON}
Action required: Review what was in progress and resume
EOF
    fi
fi

echo "[STOP] Session ended with reason '${STOP_REASON}'. See memory/scratchpad.md." >&2

# Clean up per-agent idle timeout timestamp files
rm -f /tmp/claude_last_tool_* 2>/dev/null || true
