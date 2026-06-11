#!/bin/bash
# Classifies current task complexity before orchestrator dispatch.
# Writes FORCE_FULL or AMBIGUOUS to .claude/tmp/task_mode.
# Logs verdict and reason to logs/tool_calls.log.

source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
TASK_FILE="$PROJECT_ROOT/TASKS.md"
VERDICT_FILE="${CLAUDE_TMP_DIR}/task_mode"
HASH_FILE="${CLAUDE_TMP_DIR}/task_mode_hash"
LOG_FILE="$PROJECT_ROOT/logs/tool_calls.log"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
FILE_LIMIT="${FAST_TRACK_FILE_LIMIT:-5}"

mkdir -p "$PROJECT_ROOT/logs"

export CLASSIFY_PROJECT_ROOT="$PROJECT_ROOT"
# Extract current in-progress task ID for logging
CLASSIFY_TASK_ID=$(grep -B5 "\*\*Status:\*\* in_progress" "$TASK_FILE" 2>/dev/null | grep -oE "TASK-[0-9]+" | head -1 || echo "unknown")
export CLASSIFY_TASK_ID
# Read run_id from pipeline_state.json if available — graceful fallback to empty string
CLASSIFY_RUN_ID="$(current_run_id)"
export CLASSIFY_RUN_ID

# Required by Claude hook protocol — read and discard stdin
INPUT=$(cat)

# Bail early for read-only tools — classification only matters when files change
TOOL_NAME=$(echo "$INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_name',''))" 2>/dev/null || echo "")
case "$TOOL_NAME" in
    Read|WebFetch|WebSearch|ListMcpResourcesTool|ReadMcpResourceTool|Agent|Skill|ToolSearch) exit 0 ;;
esac

# Skip classification while a pipeline run is active — reclassifying mid-run
# can overwrite .claude/tmp/task_mode and steer the NEXT task's pipeline choice.
if [ "$(state_field status)" = "running" ]; then
    exit 0
fi

# Hash the current in_progress task to detect task changes
# Use only the task title (stable across agent edits to the task block)
TASK_CONTENT=$(grep -B2 "\*\*Status:\*\* in_progress" "$TASK_FILE" 2>/dev/null | grep -E "^###|^TASK-" | head -1)
if [ -z "$TASK_CONTENT" ]; then
    TASK_HASH="none"
else
    TASK_HASH=$(printf '%s' "$TASK_CONTENT" | cksum | awk '{print $1}')
fi
CACHED_HASH=$(cat "$HASH_FILE" 2>/dev/null || echo "")

# Skip re-classifying if verdict already exists for this task
if [ -f "$VERDICT_FILE" ] && [ "$TASK_HASH" = "$CACHED_HASH" ]; then
    exit 0
fi
echo "$TASK_HASH" > "$HASH_FILE"

# Collect all changed file paths (staged, unstaged, and untracked)
# Exclude build artifacts that are always dirty in common project types
GIT_STATUS=$(git status --short 2>/dev/null)
CHANGED_FILES=$(printf '%s\n' "$GIT_STATUS" | awk '{print $NF}' \
    | grep -vE "^(\.next|node_modules|dist|build|\.turbo|tsconfig\.tsbuildinfo|__pycache__|\.pytest_cache|\.claude/)")

force_full() {
    local reason="$1"
    printf 'FORCE_FULL' > "${VERDICT_FILE}.tmp" && mv "${VERDICT_FILE}.tmp" "$VERDICT_FILE"
    echo "${TIMESTAMP} | CLASSIFIER | PIPELINE:full | REASON:${reason}" >> "$LOG_FILE"
    export CLASSIFY_VERDICT="FORCE_FULL"
    export CLASSIFY_REASON="$reason"
    python3 - <<'PYEOF'
import json, os, sys
from pathlib import Path
from datetime import datetime, timezone
project_root = os.environ.get("CLASSIFY_PROJECT_ROOT", ".")
log_dir = Path(project_root) / "logs"
log_dir.mkdir(exist_ok=True)
record = {
    "event": "classifier",
    "verdict": os.environ.get("CLASSIFY_VERDICT", ""),
    "rule_fired": os.environ.get("CLASSIFY_REASON", ""),
    "task_id": os.environ.get("CLASSIFY_TASK_ID", "unknown"),
    "timestamp": datetime.now(timezone.utc).isoformat()
}
run_id = os.environ.get("CLASSIFY_RUN_ID", "")
if run_id:
    record["run_id"] = run_id
with (log_dir / "pipeline.jsonl").open("a") as f:
    f.write(json.dumps(record) + "\n")
PYEOF
    exit 0
}

file_matches() { echo "$CHANGED_FILES" | grep -qiE "$1"; }

# ── Hard rules: file path patterns ────────────────────────────────────
# Exclude memory/ to avoid false positives from session_checkpoint.md
git diff --cached --name-only 2>/dev/null \
    | grep -v "^memory/" \
    | grep -qiE "auth|jwt|session|password|secret|token|oauth" \
    && force_full "auth/security file touched"
file_matches "payment|billing|stripe|invoice|pricing"        && force_full "payment file touched"
file_matches "migration|schema\.|flyway|liquibase"           && force_full "database schema/migration file"
file_matches "Dockerfile|docker-compose|\.github/workflows"  && force_full "infra/CI file touched"
file_matches "^hooks/"                                        && force_full "hooks/ directory changed"
file_matches "CLAUDE\.md|AGENTS\.md"                         && force_full "orchestrator config changed"

# ── Structural signals ─────────────────────────────────────────────────
DELETED=$(printf '%s' "$GIT_STATUS" | grep -cE "^\s*D")
NEW_FILES=$(printf '%s' "$GIT_STATUS" \
    | grep -vE "(logs/|memory/|docs/superpowers/|\.claude/|pipeline_state\.json)" \
    | grep -cE "^(A|\?\?)")
MODIFIED_COUNT=$(printf '%s' "$GIT_STATUS" | grep -cE "^\s*M")

[ "${DELETED:-0}" -gt 0 ]                    && force_full "file(s) deleted"
[ "${NEW_FILES:-0}" -gt 0 ]                  && force_full "new file(s) created"
[ "${MODIFIED_COUNT:-0}" -gt "$FILE_LIMIT" ] && force_full "modified file count (${MODIFIED_COUNT}) exceeds limit (${FILE_LIMIT})"

# ── Dependency manifest changes ────────────────────────────────────────
if git rev-parse HEAD &>/dev/null; then
    MANIFEST_DIFF=$(git diff HEAD -- package.json requirements.txt go.mod pom.xml 2>/dev/null; \
                    git diff --cached HEAD -- package.json requirements.txt go.mod pom.xml 2>/dev/null)
    [ -n "$MANIFEST_DIFF" ] && force_full "dependency manifest changed"
fi

# ── Sensitive keywords in task description ─────────────────────────────
TASK_DESC=$(grep -B2 -A10 "\*\*Status:\*\* in_progress" "$TASK_FILE" 2>/dev/null || echo "")
echo "$TASK_DESC" | grep -qiE "pii|gdpr|privacy|user.?data|email.?template|base\s+class" && \
    force_full "sensitive domain keyword in task description"

# No hard rule fired — ambiguous, orchestrator decides
printf 'AMBIGUOUS' > "${VERDICT_FILE}.tmp" && mv "${VERDICT_FILE}.tmp" "$VERDICT_FILE"
echo "${TIMESTAMP} | CLASSIFIER | PIPELINE:ambiguous | REASON:no hard rules matched" >> "$LOG_FILE"
export CLASSIFY_VERDICT="AMBIGUOUS"
export CLASSIFY_REASON="no hard rules matched"
python3 - <<'PYEOF'
import json, os
from pathlib import Path
from datetime import datetime, timezone
project_root = os.environ.get("CLASSIFY_PROJECT_ROOT", ".")
log_dir = Path(project_root) / "logs"
log_dir.mkdir(exist_ok=True)
record = {
    "event": "classifier",
    "verdict": os.environ.get("CLASSIFY_VERDICT", ""),
    "rule_fired": os.environ.get("CLASSIFY_REASON", ""),
    "task_id": os.environ.get("CLASSIFY_TASK_ID", "unknown"),
    "timestamp": datetime.now(timezone.utc).isoformat()
}
run_id = os.environ.get("CLASSIFY_RUN_ID", "")
if run_id:
    record["run_id"] = run_id
with (log_dir / "pipeline.jsonl").open("a") as f:
    f.write(json.dumps(record) + "\n")
PYEOF
exit 0
