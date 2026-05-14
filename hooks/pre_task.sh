#!/bin/bash
# Injects memory context once per session — not on every tool call.
# Reads session_id from stdin JSON (Claude Code hook protocol).
MEMORY_DIR="memory"
SESSION_MARKER=".claude/last_session_id"
mkdir -p .claude

# Parse session_id from stdin
INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('session_id',''))" 2>/dev/null || echo "")

# Already injected this session — skip
if [ -n "$SESSION_ID" ]; then
    LAST=$(cat "$SESSION_MARKER" 2>/dev/null || echo "")
    if [ "$SESSION_ID" = "$LAST" ]; then
        exit 0
    fi
    echo "$SESSION_ID" > "$SESSION_MARKER"
fi

if [ -f "${MEMORY_DIR}/session_checkpoint.md" ]; then
    CHECKPOINT_SIZE=$(wc -c < "${MEMORY_DIR}/session_checkpoint.md")
    if [ "${CHECKPOINT_SIZE}" -gt 50 ]; then
        echo "=== SESSION CHECKPOINT ===" >&2
        cat "${MEMORY_DIR}/session_checkpoint.md" >&2
        echo "=========================" >&2
    fi
fi

if [ -f "${MEMORY_DIR}/scratchpad.md" ]; then
    SCRATCHPAD_SIZE=$(wc -c < "${MEMORY_DIR}/scratchpad.md")
    if [ "${SCRATCHPAD_SIZE}" -gt 100 ]; then
        echo "=== SCRATCHPAD ===" >&2
        cat "${MEMORY_DIR}/scratchpad.md" >&2
        echo "=================" >&2
    fi
fi
