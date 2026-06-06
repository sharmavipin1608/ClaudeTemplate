#!/bin/bash
# Called by the orchestrator (via Bash tool) to mark agent start/end.
# Usage: bash hooks/log_agent.sh <agent_name> <START|END>
#
# Writes to logs/agent_calls.log:
#   2026-05-14T10:00:00Z | researcher | START
#   2026-05-14T10:02:30Z | researcher | END
AGENT_NAME="${1:-unknown}"
EVENT="${2:-START}"
PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
LOG_FILE="${PROJECT_ROOT}/logs/agent_calls.log"
mkdir -p "${PROJECT_ROOT}/logs"

TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
echo "${TIMESTAMP} | ${AGENT_NAME} | ${EVENT}" >> "${LOG_FILE}"
