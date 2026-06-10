#!/bin/bash
# SessionStart hook — injects project memory and pipeline recovery state
# into the model's context. SessionStart STDOUT is added to context;
# stderr (and PreToolUse stdout) is not — which is why this replaced the
# old pre_task.sh PreToolUse/stderr approach.

source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

cat > /dev/null  # consume stdin per hook protocol

MEMORY_DIR="${PROJECT_ROOT}/memory"

if [ -f "${MEMORY_DIR}/core.md" ]; then
    echo "=== PROJECT CORE ==="
    cat "${MEMORY_DIR}/core.md"
    echo "===================="
fi

if [ -f "${MEMORY_DIR}/session_checkpoint.md" ]; then
    CHECKPOINT_SIZE=$(wc -c < "${MEMORY_DIR}/session_checkpoint.md")
    if [ "${CHECKPOINT_SIZE}" -gt 50 ]; then
        echo "=== SESSION CHECKPOINT ==="
        cat "${MEMORY_DIR}/session_checkpoint.md"
        echo "=========================="
    fi
fi

if [ -f "${MEMORY_DIR}/scratchpad.md" ]; then
    SCRATCHPAD_SIZE=$(wc -c < "${MEMORY_DIR}/scratchpad.md")
    if [ "${SCRATCHPAD_SIZE}" -gt 100 ]; then
        echo "=== SCRATCHPAD ==="
        cat "${MEMORY_DIR}/scratchpad.md"
        echo "=================="
    fi
fi

# Pipeline recovery: if a run was mid-flight when the last session ended,
# tell the orchestrator exactly where to resume.
if [ "$(state_field status)" = "running" ]; then
    TASK="$(state_field task_id)"
    STEP="$(state_field current_step)"
    DONE="$(state_field completed_steps)"
    echo "=== PIPELINE RECOVERY ==="
    echo "RECOVERY: Task ${TASK} was in progress at step '${STEP}'. Resume from '${STEP}' — do not restart the pipeline."
    echo "Completed steps: ${DONE}"
    echo "========================="
fi

exit 0
