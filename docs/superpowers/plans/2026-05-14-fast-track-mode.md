# Fast-Track Mode Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add intelligent pipeline routing that skips Researcher and Reviewer agents for simple tasks, cutting token cost to near-zero for clear cases.

**Architecture:** A bash classifier hook (`classify_task.sh`) pattern-matches changed files and the current task description against hard rules, writing a verdict (`FORCE_FULL` or `AMBIGUOUS`) to `/tmp/task_mode`. The orchestrator reads this verdict before dispatch and routes to either the full pipeline or the fast-track pipeline (Coder → Tester → Security → Git → Memory). Hard-rule cases cost zero extra tokens (bash only); ambiguous cases add ~200 tokens to the orchestrator's existing dispatch call.

**Tech Stack:** bash, Claude Code hook system (PreToolUse), git

---

## File Map

| File | Action | Responsibility |
|---|---|---|
| `hooks/classify_task.sh` | Create | Hard-rule classifier — writes verdict to `/tmp/task_mode` |
| `hooks/tests/test_classify_task.sh` | Create | Integration test suite for the classifier |
| `.claude/settings.json` | Modify | Register `classify_task.sh` in PreToolUse hooks |
| `CLAUDE.md` | Modify | Orchestrator routing step + golden rule #8 |
| `AGENTS.md` | Modify | Pipeline variants table + dispatch rule #6 |

---

### Task 1: Write and test classify_task.sh

**Files:**
- Create: `hooks/classify_task.sh`
- Create: `hooks/tests/test_classify_task.sh`

- [ ] **Step 1: Create the test harness**

Create `hooks/tests/test_classify_task.sh`:

```bash
#!/bin/bash
# Integration tests for classify_task.sh
set -euo pipefail

PASS=0; FAIL=0
PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

setup_repo() {
    local tmpdir
    tmpdir=$(mktemp -d)
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
```

- [ ] **Step 2: Run tests — confirm they all fail**

```bash
chmod +x hooks/tests/test_classify_task.sh
mkdir -p hooks/tests
bash hooks/tests/test_classify_task.sh 2>&1 | head -20
```

Expected: errors like `hooks/classify_task.sh: No such file or directory` — the script doesn't exist yet.

- [ ] **Step 3: Write classify_task.sh**

Create `hooks/classify_task.sh`:

```bash
#!/bin/bash
# Classifies current task complexity before orchestrator dispatch.
# Writes FORCE_FULL or AMBIGUOUS to /tmp/task_mode.
# Logs verdict and reason to logs/tool_calls.log.

TASK_FILE="TASKS.md"
VERDICT_FILE="/tmp/task_mode"
HASH_FILE="/tmp/task_mode_hash"
LOG_FILE="logs/tool_calls.log"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
FILE_LIMIT="${FAST_TRACK_FILE_LIMIT:-5}"

mkdir -p logs

# Required by Claude hook protocol — read and discard stdin
INPUT=$(cat)

# Hash the current in_progress task to detect task changes
TASK_HASH=$(grep -A5 "\*\*Status:\*\* in_progress" "$TASK_FILE" 2>/dev/null | cksum | awk '{print $1}' || echo "none")
CACHED_HASH=$(cat "$HASH_FILE" 2>/dev/null || echo "")

# Skip re-classifying if verdict already exists for this task
if [ -f "$VERDICT_FILE" ] && [ "$TASK_HASH" = "$CACHED_HASH" ] && [ "$TASK_HASH" != "none" ]; then
    exit 0
fi
echo "$TASK_HASH" > "$HASH_FILE"

# Collect all changed file paths (staged, unstaged, and untracked)
CHANGED_FILES=$(git status --short 2>/dev/null | awk '{print $NF}')

force_full() {
    local reason="$1"
    echo "FORCE_FULL" > "$VERDICT_FILE"
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
DELETED=$(git status --short 2>/dev/null | grep -cE "^( D|D )" || echo "0")
NEW_FILES=$(git status --short 2>/dev/null | grep -cE "^(A |\?\?)" || echo "0")
MODIFIED_COUNT=$(git status --short 2>/dev/null | grep -cE "^( M|M )" || echo "0")

[ "$DELETED" -gt 0 ]                    && force_full "file(s) deleted"
[ "$NEW_FILES" -gt 0 ]                  && force_full "new file(s) created"
[ "$MODIFIED_COUNT" -gt "$FILE_LIMIT" ] && force_full "modified file count (${MODIFIED_COUNT}) exceeds limit (${FILE_LIMIT})"

# ── Dependency manifest changes ────────────────────────────────────────
MANIFEST_DIFF=$(git diff HEAD -- package.json requirements.txt go.mod pom.xml 2>/dev/null; \
                git diff --cached HEAD -- package.json requirements.txt go.mod pom.xml 2>/dev/null)
[ -n "$MANIFEST_DIFF" ] && force_full "dependency manifest changed"

# ── Sensitive keywords in task description ─────────────────────────────
TASK_DESC=$(awk '/\*\*Status:\*\* in_progress/{f=1} f{print} /^###/{if(f && NR>1)exit}' "$TASK_FILE" 2>/dev/null || echo "")
echo "$TASK_DESC" | grep -qiE "pii|gdpr|privacy|user.?data|email.?template|interface|abstract|base.*class" && \
    force_full "sensitive domain keyword in task description"

# No hard rule fired — ambiguous, orchestrator decides
echo "AMBIGUOUS" > "$VERDICT_FILE"
echo "${TIMESTAMP} | CLASSIFIER | PIPELINE:ambiguous | REASON:no hard rules matched" >> "$LOG_FILE"
exit 0
```

- [ ] **Step 4: Make executable and run tests**

```bash
chmod +x hooks/classify_task.sh
bash hooks/tests/test_classify_task.sh
```

Expected output:
```
PASS: no changes returns AMBIGUOUS
PASS: auth file triggers FORCE_FULL
PASS: jwt file triggers FORCE_FULL
PASS: billing file triggers FORCE_FULL
PASS: migration file triggers FORCE_FULL
PASS: Dockerfile triggers FORCE_FULL
PASS: hooks/ change triggers FORCE_FULL
PASS: AGENTS.md change triggers FORCE_FULL
PASS: deleted file triggers FORCE_FULL
PASS: 6 modified files triggers FORCE_FULL
PASS: 5 modified files returns AMBIGUOUS
PASS: package.json change triggers FORCE_FULL
PASS: pii keyword in task triggers FORCE_FULL
PASS: same task verdict is cached

Results: 14 passed, 0 failed
```

- [ ] **Step 5: Commit**

```bash
git add hooks/classify_task.sh hooks/tests/test_classify_task.sh
git commit -m "feat: add classify_task.sh with hard-rule pipeline classifier"
```

---

### Task 2: Register classify_task.sh in settings.json

**Files:**
- Modify: `.claude/settings.json:3-10`

- [ ] **Step 1: Add the hook entry**

In `.claude/settings.json`, insert `classify_task.sh` after `pre_task.sh` in the PreToolUse hooks array. The full updated hooks block:

```json
"PreToolUse": [
  {
    "matcher": "",
    "hooks": [
      { "type": "command", "command": "bash hooks/pre_task.sh" },
      { "type": "command", "command": "bash hooks/classify_task.sh" },
      { "type": "command", "command": "bash hooks/budget_guard.sh" },
      { "type": "command", "command": "bash hooks/log_tool.sh" }
    ]
  }
],
```

`classify_task.sh` runs after `pre_task.sh` (which loads session context) and before `budget_guard.sh`.

- [ ] **Step 2: Verify JSON is valid**

```bash
python3 -c "import json; json.load(open('.claude/settings.json')); print('valid')"
```

Expected: `valid`

- [ ] **Step 3: Smoke test**

```bash
rm -f /tmp/task_mode /tmp/task_mode_hash
echo '{"session_id":"smoke","tool_name":"Read","tool_input":{}}' | bash hooks/classify_task.sh
cat /tmp/task_mode
```

Expected: `AMBIGUOUS` or `FORCE_FULL` (no error, no empty output).

- [ ] **Step 4: Commit**

```bash
git add .claude/settings.json
git commit -m "feat: register classify_task.sh in PreToolUse hook pipeline"
```

---

### Task 3: Update CLAUDE.md — orchestrator routing

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: Update the Agent Pipeline section**

Find and replace the pipeline block (around line 33):

Old:
```
## 🤖 Agent Pipeline

```
Researcher → Coder → Reviewer → Tester → Security → Git → Memory → Changelog
```
```

New:
```
## 🤖 Agent Pipeline

### Full Pipeline (default)
```
Researcher → Coder → Reviewer → Tester → Security → Git → Memory → Changelog
```

### Fast-Track Pipeline
```
Coder → Tester → Security → Git → Memory
```
Skipped: Researcher (domain already known), Reviewer (scope too small)
Never skipped: Security (hard gate), Memory (system coherence)
```

- [ ] **Step 2: Update the dispatch sequence**

Find and replace the numbered steps in "Your Role (Orchestrator)" (around line 22):

Old:
```markdown
For every task:
1. Read `TASKS.md` to understand what's next
2. Read `memory/core.md` for project identity
3. Read `memory/facts.md` (or grep relevant tags) for known decisions
4. Read `memory/session_checkpoint.md` for session recovery context
5. Load `memory/scratchpad.md` for current working context
6. Delegate to the right sub-agent with a **surgical context** — only what they need
7. After task completes, update `TASKS.md` and `memory/scratchpad.md`
```

New:
```markdown
For every task:
1. Read `TASKS.md` to understand what's next
2. Read `memory/core.md` for project identity
3. Read `memory/facts.md` (or grep relevant tags) for known decisions
4. Read `memory/session_checkpoint.md` for session recovery context
5. Load `memory/scratchpad.md` for current working context
6. Read `/tmp/task_mode` (written by `hooks/classify_task.sh`):
   - **FORCE_FULL** → dispatch full pipeline. Log which rule fired.
   - **AMBIGUOUS** → reason briefly: does this task introduce new behavior, touch shared logic, or carry risk not caught by pattern rules? If yes, full pipeline. If no, fast-track. Log the decision either way.
7. Delegate to first agent in chosen pipeline with **surgical context** — only what they need
8. After task completes, update `TASKS.md` and `memory/scratchpad.md`
```

- [ ] **Step 3: Add golden rule #8**

Find the Golden Rules section. The current rules end at #7. Add:

```
8. **Classification is a gate, not a suggestion** — if `hooks/classify_task.sh` returns FORCE_FULL, do not override it
```

- [ ] **Step 4: Commit**

```bash
git add CLAUDE.md
git commit -m "feat: add fast-track routing logic to orchestrator dispatch sequence"
```

---

### Task 4: Update AGENTS.md — pipeline variants and audit logging

**Files:**
- Modify: `AGENTS.md`

- [ ] **Step 1: Add Pipeline Variants section**

After the `## Pipeline Order` section (after line 7), insert:

```markdown
## Pipeline Variants

| Variant | Agents | When |
|---|---|---|
| Full (default) | Researcher → Coder → Reviewer → Tester → Security → Git → Memory | FORCE_FULL verdict, or orchestrator judges complex |
| Fast-Track | Coder → Tester → Security → Git → Memory | AMBIGUOUS verdict + orchestrator judges simple |

Security and Memory are never skippable in either variant.
```

- [ ] **Step 2: Add dispatch rule #6**

Find `## Dispatch Rules`. Current rules end at #5. Add:

```
6. Log the pipeline variant and reason for every task — format:
   `timestamp | ORCHESTRATOR | PIPELINE:full | REASON:auth file touched`
```

- [ ] **Step 3: Commit**

```bash
git add AGENTS.md
git commit -m "feat: add fast-track pipeline variant and audit log rule to AGENTS.md"
```

---

### Task 5: End-to-end verification

- [ ] **Step 1: Run full test suite**

```bash
bash hooks/tests/test_classify_task.sh
```

Expected: `Results: 14 passed, 0 failed`

- [ ] **Step 2: Validate settings.json**

```bash
python3 -c "import json; json.load(open('.claude/settings.json')); print('valid')"
```

Expected: `valid`

- [ ] **Step 3: Verify FAST_TRACK_FILE_LIMIT env var is respected**

```bash
PROJECT_ROOT="$(pwd)"
TMPDIR=$(mktemp -d)
cd "$TMPDIR"
git init -q && git config user.email "t@t.com" && git config user.name "T"
mkdir -p logs hooks
cat > TASKS.md <<'T'
### [TASK-001] Small change
**Status:** in_progress
T
git add . && git commit -q -m "init"
cp "$PROJECT_ROOT/hooks/classify_task.sh" hooks/

# Create 3 modified files — under default limit of 5, should be AMBIGUOUS
for i in 1 2 3; do echo "orig" > "f$i.js"; done
git add . && git commit -q -m "add"
for i in 1 2 3; do echo "changed" > "f$i.js"; done
git add .

rm -f /tmp/task_mode /tmp/task_mode_hash
export FAST_TRACK_FILE_LIMIT=2
echo '{}' | bash hooks/classify_task.sh
cat /tmp/task_mode
cd "$PROJECT_ROOT"
```

Expected: `FORCE_FULL` (3 modified files exceeds the overridden limit of 2)

- [ ] **Step 4: Check audit log entries**

```bash
cat logs/tool_calls.log | grep CLASSIFIER | tail -5
```

Expected lines like:
```
2026-05-14T10:23:01Z | CLASSIFIER | PIPELINE:full | REASON:auth file touched
2026-05-14T10:45:12Z | CLASSIFIER | PIPELINE:ambiguous | REASON:no hard rules matched
```

- [ ] **Step 5: Verify git log**

```bash
git log --oneline -5
```

Expected:
```
<hash> feat: add fast-track pipeline variant and audit log rule to AGENTS.md
<hash> feat: add fast-track routing logic to orchestrator dispatch sequence
<hash> feat: register classify_task.sh in PreToolUse hook pipeline
<hash> feat: add classify_task.sh with hard-rule pipeline classifier
<hash> docs: add fast-track mode design spec
```
