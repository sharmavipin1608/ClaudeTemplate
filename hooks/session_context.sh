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

# Cross-session orchestration warning (Issue 8):
# If pipeline_state.json records a project_root that differs from the current
# session's PROJECT_ROOT, PreToolUse hooks (budget_guard, classify_task) will
# NOT fire for the other project. Warn the orchestrator so it can react.
if [ -f "$PROJECT_ROOT/pipeline_state.json" ]; then
    RUN_STATUS="$(state_field status)"
    RUN_ROOT="$(state_field project_root)"
    if [ "$RUN_STATUS" = "running" ] && [ -n "$RUN_ROOT" ] && [ "$RUN_ROOT" != "$PROJECT_ROOT" ]; then
        echo "=== CROSS-SESSION WARNING ==="
        echo "WARN: pipeline_state.json references project_root='${RUN_ROOT}' but this session runs at '${PROJECT_ROOT}'."
        echo "WARN: PreToolUse hooks (budget_guard, classify_task) will NOT fire for the other project."
        echo "WARN: See hooks/README.md → 'Cross-session orchestration'."
        echo "============================="
    fi
fi

# Emit a session_start event to pipeline.jsonl so replay tools can
# identify session boundaries.
export SC_PROJECT_ROOT="$PROJECT_ROOT"
export SC_RUN_ID
SC_RUN_ID="$(current_run_id)"
python3 - <<'PYEOF'
import json, os
from pathlib import Path
from datetime import datetime, timezone
project_root = Path(os.environ.get("SC_PROJECT_ROOT", "."))
log_dir = project_root / "logs"
log_dir.mkdir(exist_ok=True)
record = {
    "event": "session_start",
    "timestamp": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "project_root": str(project_root),
}
run_id = os.environ.get("SC_RUN_ID", "")
if run_id:
    record["run_id"] = run_id
with (log_dir / "pipeline.jsonl").open("a") as f:
    f.write(json.dumps(record) + "\n")
PYEOF

exit 0
