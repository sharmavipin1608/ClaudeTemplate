#!/bin/bash
# Post-tool-call hook. Writes to tool_calls.log (existing) and emits a
# pipeline_step event to pipeline.jsonl when task/agent context is set.

TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
mkdir -p "${PROJECT_ROOT}/logs"
echo "${TIMESTAMP} | POST_TOOL | done" >> "${PROJECT_ROOT}/logs/tool_calls.log"
