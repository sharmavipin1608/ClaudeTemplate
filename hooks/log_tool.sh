#!/bin/bash
# Reads tool event JSON from stdin (Claude Code hook protocol).
# Appends timestamp | tool_name to logs/tool_calls.log.
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
LOG_FILE="logs/tool_calls.log"
mkdir -p logs

# Claude Code passes event JSON on stdin: {"tool_name": "Bash", ...}
TOOL_NAME=$(python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('tool_name','unknown'))" 2>/dev/null || echo "unknown")

echo "${TIMESTAMP} | ${TOOL_NAME}" >> "${LOG_FILE}"
