#!/bin/bash
# Classifies current task complexity before orchestrator dispatch.
# Writes FORCE_FULL or AMBIGUOUS to /tmp/task_mode.
# Logs verdict and reason to logs/tool_calls.log.

PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
TASK_FILE="$PROJECT_ROOT/TASKS.md"
VERDICT_FILE="/tmp/task_mode"
HASH_FILE="/tmp/task_mode_hash"
LOG_FILE="$PROJECT_ROOT/logs/tool_calls.log"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
FILE_LIMIT="${FAST_TRACK_FILE_LIMIT:-5}"

mkdir -p "$PROJECT_ROOT/logs"

# Required by Claude hook protocol — read and discard stdin
INPUT=$(cat)

# Hash the current in_progress task to detect task changes
TASK_CONTENT=$(grep -A5 "\*\*Status:\*\* in_progress" "$TASK_FILE" 2>/dev/null)
if [ -z "$TASK_CONTENT" ]; then
    TASK_HASH="none"
else
    TASK_HASH=$(printf '%s' "$TASK_CONTENT" | cksum | awk '{print $1}')
fi
CACHED_HASH=$(cat "$HASH_FILE" 2>/dev/null || echo "")

# Skip re-classifying if verdict already exists for this task
if [ -f "$VERDICT_FILE" ] && [ "$TASK_HASH" = "$CACHED_HASH" ] && [ "$TASK_HASH" != "none" ]; then
    exit 0
fi
echo "$TASK_HASH" > "$HASH_FILE"

# Collect all changed file paths (staged, unstaged, and untracked)
GIT_STATUS=$(git status --short 2>/dev/null)
CHANGED_FILES=$(printf '%s\n' "$GIT_STATUS" | awk '{print $NF}')

force_full() {
    local reason="$1"
    printf 'FORCE_FULL' > "${VERDICT_FILE}.tmp" && mv "${VERDICT_FILE}.tmp" "$VERDICT_FILE"
    echo "${TIMESTAMP} | CLASSIFIER | PIPELINE:full | REASON:${reason}" >> "$LOG_FILE"
    exit 0
}

file_matches() { echo "$CHANGED_FILES" | grep -qiE "$1"; }

# ── Hard rules: file path patterns ────────────────────────────────────
file_matches "auth|jwt|session|password|secret|token|oauth"  && force_full "auth/security file touched"
file_matches "payment|billing|stripe|invoice|pricing"        && force_full "payment file touched"
file_matches "migration|schema\.|flyway|liquibase"           && force_full "database schema/migration file"
file_matches "Dockerfile|docker-compose|\.github/workflows"  && force_full "infra/CI file touched"
file_matches "^hooks/"                                        && force_full "hooks/ directory changed"
file_matches "CLAUDE\.md|AGENTS\.md"                         && force_full "orchestrator config changed"

# ── Structural signals ─────────────────────────────────────────────────
DELETED=$(printf '%s' "$GIT_STATUS" | grep -cE "^\s*D")
NEW_FILES=$(printf '%s' "$GIT_STATUS" | grep -cE "^(A|\?\?)")
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
exit 0
