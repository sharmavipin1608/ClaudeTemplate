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

if [ -f "${MEMORY_DIR}/core.md" ]; then
    echo "=== PROJECT CORE ===" >&2
    cat "${MEMORY_DIR}/core.md" >&2
    echo "====================" >&2
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

# Recovery check — if pipeline was in progress when session died, output resume hint
if [ -f "pipeline_state.json" ]; then
    export RECOVERY_STATE_FILE="pipeline_state.json"
    STATUS=$(python3 -c "import json,os; d=json.load(open(os.environ['RECOVERY_STATE_FILE'])); print(d.get('status',''))" 2>/dev/null || echo "")
    if [ "$STATUS" = "running" ]; then
        echo "=== PIPELINE RECOVERY ===" >&2
        python3 - <<'PYEOF'
import json, os
d = json.load(open(os.environ["RECOVERY_STATE_FILE"]))
task = d.get("task_id", "unknown")
step = d.get("current_step", "unknown")
done = d.get("completed_steps", [])
print(f"RECOVERY: Task {task} was in progress at step '{step}'. Resume from '{step}'. Completed steps: {done}.")
PYEOF
        echo "========================" >&2
    fi
fi
