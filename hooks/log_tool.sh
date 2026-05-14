#!/bin/bash
# Usage: log_tool.sh "$TOOL_NAME" "$AGENT_NAME"
TOOL_NAME="${1:-unknown}"
AGENT_NAME="${2:-unknown}"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
LOG_FILE="logs/tool_calls.log"
mkdir -p logs
echo "${TIMESTAMP} | ${AGENT_NAME} | ${TOOL_NAME}" >> "${LOG_FILE}"
