#!/bin/bash
# hooks/lib/common.sh — shared helpers sourced by every hook script.
#
# Provides:
#   PROJECT_ROOT     — MAIN repository root (worktree-safe)
#   CLAUDE_TMP_DIR   — per-project tmp dir for hook runtime state
#   state_field F    — top-level field F from pipeline_state.json ("" if absent)
#   current_agent    — active agent name, or "orchestrator" when routing between agents ("" when no pipeline is running)
#   current_task_id  — active task id ("" when no pipeline is running)
#   current_run_id   — run_id of the active pipeline run ("" if none)
#
# Worktree note: agents run in git worktrees under .claude/worktrees/.
# `git rev-parse --show-toplevel` returns the WORKTREE root there, which
# fragments logs and state. `--git-common-dir` always points at the main
# repo's .git, so dirname of it is the main root. Requires git >= 2.31.
#
# Attribution: current_agent returns "orchestrator" when pipeline is running
# but no agent is active (agent_active=false in state). Returns the agent name
# only when log_agent START has fired and log_agent END has not yet fired.
# CLAUDE_CURRENT_AGENT / CLAUDE_TASK_ID env vars, when present (tests, manual
# runs), take precedence.

resolve_project_root() {
    local common
    common=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)
    if [ -n "$common" ]; then
        dirname "$common"
    else
        pwd
    fi
}

PROJECT_ROOT="$(resolve_project_root)"
CLAUDE_TMP_DIR="${PROJECT_ROOT}/.claude/tmp"
mkdir -p "$CLAUDE_TMP_DIR"

state_field() {
    python3 - "$1" <<PYEOF 2>/dev/null || echo ""
import json, sys
try:
    d = json.load(open("${PROJECT_ROOT}/pipeline_state.json"))
    v = d.get(sys.argv[1], "")
    print("" if v is None else v)
except Exception:
    print("")
PYEOF
}

current_agent() {
    if [ -n "${CLAUDE_CURRENT_AGENT:-}" ]; then
        echo "$CLAUDE_CURRENT_AGENT"
        return
    fi
    if [ "$(state_field status)" = "running" ]; then
        if [ "$(state_field agent_active)" = "True" ]; then
            state_field current_step
        else
            echo "orchestrator"
        fi
    else
        echo ""
    fi
}

current_task_id() {
    if [ -n "${CLAUDE_TASK_ID:-}" ]; then
        echo "$CLAUDE_TASK_ID"
        return
    fi
    if [ "$(state_field status)" = "running" ]; then
        state_field task_id
    else
        echo ""
    fi
}

current_run_id() {
    state_field run_id
}
