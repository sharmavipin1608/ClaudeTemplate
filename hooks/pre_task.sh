#!/bin/bash
# Load relevant memory context before each tool call.
# Outputs to stderr so it appears in Claude's context without polluting stdout.
MEMORY_DIR="memory"

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
