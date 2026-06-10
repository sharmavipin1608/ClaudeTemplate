#!/bin/bash
# Stop hook. Fires when Claude finishes responding. The Stop payload has
# no stop_reason field and hooks do not run at all on a hard crash, so
# this CANNOT detect abnormal termination. What it does instead:
#   1. Always clear per-agent idle timestamps — a stopped session is not
#      "idle", and stale files caused false alarms in the next session.
#   2. If a pipeline run is still marked running, leave one recovery note
#      per run_id — the orchestrator stopped mid-pipeline.
# (Session-start recovery is handled by session_context.sh reading
#  pipeline_state.json — that is the primary recovery path.)

source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

cat > /dev/null  # consume stdin per hook protocol

TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
LOG_FILE="${PROJECT_ROOT}/logs/tool_calls.log"
mkdir -p "${PROJECT_ROOT}/logs"

# 1. Clear idle timestamps
rm -f "${CLAUDE_TMP_DIR}"/last_tool_* 2>/dev/null || true

# 2. Mid-pipeline stop → recovery note, once per run
if [ "$(state_field status)" = "running" ]; then
    RUN_ID="$(state_field run_id)"
    MARKER="${CLAUDE_TMP_DIR}/stop_noted_${RUN_ID:-unknown}"
    if [ ! -f "$MARKER" ]; then
        touch "$MARKER"
        TASK="$(state_field task_id)"
        STEP="$(state_field current_step)"
        echo "${TIMESTAMP} | STOP | pipeline_incomplete task:${TASK} step:${STEP}" >> "${LOG_FILE}"
        if [ -f "${PROJECT_ROOT}/memory/scratchpad.md" ]; then
            cat >> "${PROJECT_ROOT}/memory/scratchpad.md" << EOF

## SESSION STOPPED MID-PIPELINE (${TIMESTAMP})
Task ${TASK} was at step '${STEP}' (run ${RUN_ID}).
Action required: resume from '${STEP}' — see pipeline_state.json.
EOF
        fi
    fi
fi

exit 0
