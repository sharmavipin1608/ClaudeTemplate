#!/bin/bash
# Integration tests for classify_task.sh
set -euo pipefail

PASS=0; FAIL=0
PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CLEANUP_DIRS=()
trap 'rm -rf "${CLEANUP_DIRS[@]:-}"' EXIT

setup_repo() {
    local tmpdir
    tmpdir=$(mktemp -d)
    CLEANUP_DIRS+=("$tmpdir")
    cd "$tmpdir"
    git init -q
    git config user.email "test@test.com"
    git config user.name "Test"
    mkdir -p logs hooks
    cat > TASKS.md <<'TASKS'
### [TASK-001] Fix button label
**Status:** in_progress
**Priority:** low
**Tags:** [ui]
TASKS
    git add TASKS.md && git commit -q -m "init"
    cp "$PROJECT_ROOT/hooks/classify_task.sh" hooks/
    git add hooks/ && git commit -q -m "add hook"
    echo "$tmpdir"
}

assert_verdict() {
    local name="$1" expected="$2"
    actual=$(cat /tmp/task_mode 2>/dev/null || echo "MISSING")
    if [ "$actual" = "$expected" ]; then
        echo "PASS: $name"; PASS=$((PASS+1))
    else
        echo "FAIL: $name — expected='$expected' got='$actual'"; FAIL=$((FAIL+1))
    fi
    rm -f /tmp/task_mode /tmp/task_mode_hash
}

# ── Test 1: No changes → AMBIGUOUS ────────────────────────────────────
DIR=$(setup_repo)
(cd "$DIR" && echo '{}' | bash hooks/classify_task.sh)
assert_verdict "no changes returns AMBIGUOUS" "AMBIGUOUS"

# ── Test 2: Auth file → FORCE_FULL ────────────────────────────────────
DIR=$(setup_repo)
(cd "$DIR" && touch auth_service.js && git add . && echo '{}' | bash hooks/classify_task.sh)
assert_verdict "auth file triggers FORCE_FULL" "FORCE_FULL"

# ── Test 3: JWT file → FORCE_FULL ─────────────────────────────────────
DIR=$(setup_repo)
(cd "$DIR" && touch jwt_helper.py && git add . && echo '{}' | bash hooks/classify_task.sh)
assert_verdict "jwt file triggers FORCE_FULL" "FORCE_FULL"

# ── Test 4: Payment file → FORCE_FULL ─────────────────────────────────
DIR=$(setup_repo)
(cd "$DIR" && touch billing_service.rb && git add . && echo '{}' | bash hooks/classify_task.sh)
assert_verdict "billing file triggers FORCE_FULL" "FORCE_FULL"

# ── Test 5: Migration file → FORCE_FULL ───────────────────────────────
DIR=$(setup_repo)
(cd "$DIR" && mkdir -p migrations && touch migrations/001_add_users.sql && git add . && echo '{}' | bash hooks/classify_task.sh)
assert_verdict "migration file triggers FORCE_FULL" "FORCE_FULL"

# ── Test 6: Dockerfile → FORCE_FULL ───────────────────────────────────
DIR=$(setup_repo)
(cd "$DIR" && touch Dockerfile && git add . && echo '{}' | bash hooks/classify_task.sh)
assert_verdict "Dockerfile triggers FORCE_FULL" "FORCE_FULL"

# ── Test 7: hooks/ change → FORCE_FULL ────────────────────────────────
DIR=$(setup_repo)
(cd "$DIR" && echo "# change" >> hooks/classify_task.sh && git add . && echo '{}' | bash hooks/classify_task.sh)
assert_verdict "hooks/ change triggers FORCE_FULL" "FORCE_FULL"

# ── Test 8: AGENTS.md change → FORCE_FULL ─────────────────────────────
DIR=$(setup_repo)
(cd "$DIR" && echo "# change" > AGENTS.md && git add . && echo '{}' | bash hooks/classify_task.sh)
assert_verdict "AGENTS.md change triggers FORCE_FULL" "FORCE_FULL"

# ── Test 9: Deleted file → FORCE_FULL ─────────────────────────────────
DIR=$(setup_repo)
(cd "$DIR" && touch utils.py && git add . && git commit -q -m "add utils" && git rm -q utils.py && echo '{}' | bash hooks/classify_task.sh)
assert_verdict "deleted file triggers FORCE_FULL" "FORCE_FULL"

# ── Test 10: >5 modified files → FORCE_FULL ───────────────────────────
DIR=$(setup_repo)
(cd "$DIR"
for i in 1 2 3 4 5 6; do echo "orig" > "file$i.js"; done
git add . && git commit -q -m "add files"
for i in 1 2 3 4 5 6; do echo "changed" > "file$i.js"; done
git add .
echo '{}' | bash hooks/classify_task.sh)
assert_verdict "6 modified files triggers FORCE_FULL" "FORCE_FULL"

# ── Test 11: Exactly 5 modified files → AMBIGUOUS ─────────────────────
DIR=$(setup_repo)
(cd "$DIR"
for i in 1 2 3 4 5; do echo "orig" > "file$i.js"; done
git add . && git commit -q -m "add files"
for i in 1 2 3 4 5; do echo "changed" > "file$i.js"; done
git add .
echo '{}' | bash hooks/classify_task.sh)
assert_verdict "5 modified files returns AMBIGUOUS" "AMBIGUOUS"

# ── Test 12: Manifest change → FORCE_FULL ─────────────────────────────
DIR=$(setup_repo)
(cd "$DIR"
echo '{}' > package.json && git add . && git commit -q -m "add pkg"
echo '{"dependencies":{"lodash":"4.0.0"}}' > package.json && git add .
echo '{}' | bash hooks/classify_task.sh)
assert_verdict "package.json change triggers FORCE_FULL" "FORCE_FULL"

# ── Test 13: PII keyword in task description → FORCE_FULL ─────────────
DIR=$(setup_repo)
(cd "$DIR"
cat > TASKS.md <<'TASKS'
### [TASK-002] Handle PII data export
**Status:** in_progress
**Priority:** high
TASKS
git add . && echo '{}' | bash hooks/classify_task.sh)
assert_verdict "pii keyword in task triggers FORCE_FULL" "FORCE_FULL"

# ── Test 14: Caching — same task not re-classified ────────────────────
DIR=$(setup_repo)
(cd "$DIR"
echo '{}' | bash hooks/classify_task.sh        # first run → AMBIGUOUS
echo "FORCE_FULL" > /tmp/task_mode             # manually override
echo '{}' | bash hooks/classify_task.sh        # second run — should use cache
)
assert_verdict "same task verdict is cached" "FORCE_FULL"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
