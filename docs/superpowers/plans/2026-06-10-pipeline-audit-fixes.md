# Pipeline Audit Fixes — Issue Register + Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the audit findings from 2026-06-10 so the template's observability, budget guards, run-ID tracing, memory injection, and template/project separation actually work in Claude Code.

**Architecture:** The root cause of the critical findings is that agent identity and enforcement run over channels Claude Code does not honor (Bash `export`s, exit-1 "halts", stderr "injection", worktree-relative paths). The fix: a shared hook library resolves the **main** repo root (worktree-safe) and reads agent/task/run context from `pipeline_state.json` instead of env vars; halts use **exit 2** (the only blocking exit code for PreToolUse); context injection moves to **SessionStart stdout** (the only channel injected into model context); limits are parsed from `contracts/pipeline-slos.md`.

**Tech Stack:** Bash (must stay bash-3.2 compatible — macOS default: no `declare -A`, no `${var,,}`), Python 3 (stdlib only), Claude Code hooks.

---

## Context for the executor (read first)

- You are working in `/Users/vipin/Projects/ClaudeTemplate`. This repo is a **template**: `bootstrap.sh` turns a clone of it into a new project (moving `hooks/`, `agents/`, `skills/`, `tools/`, `contracts/` into `.claude/`). In the template repo itself those dirs are at the root.
- Hook scripts live in `hooks/`. They are registered in `.claude/settings.json` and invoked by Claude Code as subprocesses with a JSON payload on stdin.
- **Claude Code hook facts this plan relies on** (do not "simplify" these away):
  - PreToolUse hooks only block a tool call on **exit code 2**. Exit 1 is a non-blocking error.
  - Stdout of **SessionStart** hooks is added to the model's context. Stderr of any hook, and stdout of PreToolUse hooks, is shown to the user only — the model never sees it.
  - Env vars exported inside a Bash *tool call* do **not** persist and are never visible to hook processes.
  - Inside a git worktree, `git rev-parse --show-toplevel` returns the **worktree** root; `git rev-parse --path-format=absolute --git-common-dir` returns the main repo's `.git` dir (requires git ≥ 2.31).
  - The Stop hook payload has **no** `stop_reason` field, and hooks do not fire at all on a hard crash.
- Tests for hooks live in `hooks/tests/test_*.sh`. They are plain bash scripts that create throwaway git repos in `mktemp -d` dirs, copy the hook under test into them, and count PASS/FAIL. CI (`.github/workflows/ci.yml`) runs every `hooks/tests/test_*.sh` plus `python3 -m pytest tests/`.
- Run a single test file: `bash hooks/tests/test_<name>.sh` — it prints `Results: N passed, M failed` and exits non-zero on any failure.
- Work on a branch: `git checkout -b fix/pipeline-audit`. Commit after every task.
- There are uncommitted changes on `master` from the idle-timeout feature (`hooks/budget_guard.sh`, `hooks/log_tool.sh`, `hooks/on_error.sh`, `CLAUDE.md`). This plan **rewrites** those files; the rewrites below already include the idle-timeout feature, fixed. Branch from the current working tree as-is.

---

## Part 1 — Issue Register

Status key: `[ ]` open, `[x]` fixed by this plan, `[D]` deferred (see Part 3).

### Critical

| ID | Issue | Fixed in |
|---|---|---|
| C1 | Agent context via `export CLAUDE_TASK_ID/CLAUDE_CURRENT_AGENT` (CLAUDE.md step 10a) never reaches hooks — env vars from Bash tool calls don't propagate to hook processes. Per-agent budgets, idle attribution, and `tool_call` events in `pipeline.jsonl` are dead code. Evidence: live log has 0 `tool_call` events and 0 records with `run_id`. | Tasks 1, 4, 11 |
| C2 | `budget_guard.sh` broken three ways: (a) per-agent count uses the **daily total** (`AGENT_CALLS="${TODAYS_CALLS}"`); (b) "halt" exits 1, which does not block (needs exit 2); (c) daily count is ~3× inflated (log_tool runs on Pre+Post, plus `POST_TOOL` marker lines) and compares a **local** date against **UTC** timestamps. | Tasks 3, 4 |
| C3 | Worktree fragmentation: all hooks resolve the project root via `git rev-parse --show-toplevel`, so agents running in `.claude/worktrees/<branch>/` write logs and read `pipeline_state.json` in the worktree, not the main repo. Central logging breaks for exactly the agents that matter. | Tasks 1, 3, 4, 5, 6 |

### High

| ID | Issue | Fixed in |
|---|---|---|
| H1 | Context injection writes to stderr: `pre_task.sh` (core.md, checkpoint, scratchpad, pipeline-recovery hint, on PreToolUse) and `session_override.sh` (SessionStart). The model never sees any of it. Session-death recovery silently doesn't work. | Task 7 |
| H2 | Classifier forces FORCE_FULL whenever **any** untracked file exists (only `logs/`, `memory/`, `docs/superpowers/` excluded). Untracked `.claude/worktrees/` — created by the pipeline itself — makes fast-track permanently unreachable. Both real classifier events fired this rule. | Task 5 |
| H3 | No code-quality evaluation harness (pipeline output vs. plain-prompt baseline). Explicit project goal, 0% implemented. | **Deferred** |
| H4 | `on_error.sh` keys on a `stop_reason` field the Stop payload doesn't have → crash logging, scratchpad recovery note, and `/tmp` cleanup never fire. | Task 8 |
| H5 | Idle/loop guard: retrospective by design (fires on the *next* tool call); stale `/tmp/claude_last_tool_*` files are never cleaned → false alarms; all `/tmp` state (`task_mode`, `task_mode_hash`, `claude_last_tool_*`) is **shared across every project** built from the template. | Tasks 3, 5, 8 |
| H6 | Wall-clock SLOs defined in `contracts/pipeline-slos.md` are enforced nowhere. | Task 3 |
| H7 | Bootstrap separation leaks: (a) `logs/pipeline.jsonl` neither gitignored nor cleared — template run history ships to new projects; (b) `.github/workflows/ci.yml` carries over referencing pre-bootstrap paths → red CI on every new project's first push; (c) bootstrap removes only 1 of 5 template-specific hook tests. | Task 9 |

### Medium

| ID | Issue | Fixed in |
|---|---|---|
| M1 | `run_id` unusable: no `--run-id` filter or per-run grouping in `pipeline_analytics.py`/`trace_analyze.py`; duration pairing by `(agent, task_id)` corrupts on retries; validated envelopes are logged without an `event` field. | Tasks 6, 10 |
| M2 | `CLAUDE.md` (template) and `.claude/orchestrator.md` (bootstrapped) duplicate the whole pipeline spec and have already drifted (idle-timeout doc only in CLAUDE.md). | Task 11 syncs; structural fix **deferred** |
| M3 | `bootstrap.sh` survives in the new project; re-running it would `rm -rf .git`. | Task 9 |
| M4 | Retry counts live only in the orchestrator's working memory; `pipeline_state.json` has no retry field, so session death can violate the retry-once rule. | Task 2 |
| M5 | No contracts for `writer`/`changelog` agents though Writer is dispatched in Phase 0 and has budget limits. | Task 10 |
| M6 | Budget limits hardcoded in `budget_guard.sh` while the SLO doc claims the file drives them; duplicate Researcher row in the SLO table. | Task 3 |

### Low

| ID | Issue | Fixed in |
|---|---|---|
| L1 | `logs/token_usage.log` is a dead artifact (empty, no writer) contradicting ADR-0007's tool-call-proxy decision. | Task 9 |
| L2 | `memory/facts.md` carries a template-provenance fact into new projects; scratchpad/checkpoint/candidates not reset by bootstrap. | Task 9 |
| L3 | Stale worktrees (`feat-24-role-profiles`, `feat-32-knowledge-taxonomy`) linger in `.claude/worktrees/` in the template repo. | Task 9 |
| L4 | `post_task.sh` writes a `POST_TOOL | done` line nothing consumes (and it inflates budget counts). | Task 4 |

**Known accepted limitation after this plan:** agent attribution comes from `pipeline_state.json`'s `current_step`, so tool calls the *orchestrator* makes while a pipeline run is active are attributed to the pending agent. This is bounded noise and beats no attribution; it is documented in `hooks/lib/common.sh`.

### Post-plan findings (2026-06-11, demo-run review)

Found by auditing a real bootstrapped run (`/tmp/audit-verify-demo`) after Tasks 1–11 landed. Items 1–6 of that review were addressed in PRs #70–#73 and branch `fix/issue-6-classify-mid-run`; the remaining item is:

| ID | Issue | Fixed in |
|---|---|---|
| 8 | The run's own classification is missing from its trace: the classifier verdict that decides a run's pipeline fires on the PreToolUse of the `init_pipeline_state.sh` Bash call — **before** `pipeline_state.json` exists — so those events carry no `run_id`, and `pipeline_analytics.py --run-id <id>` excludes them. Observed in the demo run: both pre-init classifier events had no `run_id`. | Task 12 |

---

## Part 2 — Implementation Plan

File map (what this plan creates/modifies):

```
hooks/lib/common.sh                    CREATE   worktree-safe root + state-file context readers
hooks/init_pipeline_state.sh           MODIFY   started_at field; use common.sh
hooks/advance_pipeline_state.sh        MODIFY   retries tracking; use common.sh
hooks/budget_guard.sh                  REWRITE  SLO-file limits, per-run agent counts, exit 2, UTC, wall-clock
hooks/log_tool.sh                      REWRITE  PreToolUse-only flat log, state-file context, per-project idle file
hooks/post_task.sh                     DELETE
hooks/classify_task.sh                 MODIFY   per-project tmp, .claude/ exclusions, use common.sh
hooks/log_agent.sh                     MODIFY   use common.sh
hooks/validate_output.sh               MODIFY   use common.sh; tag envelopes with event field
hooks/session_context.sh               CREATE   SessionStart stdout injection (replaces pre_task.sh)
hooks/pre_task.sh                      DELETE
hooks/session_override.sh              MODIFY   stderr → stdout
hooks/on_error.sh                      REWRITE  honest Stop semantics, tmp cleanup, once-per-run recovery note
.claude/settings.json                  MODIFY   hook registrations
contracts/pipeline-slos.md             REWRITE  dedupe, parseable wall-clock table
contracts/writer.json                  CREATE
contracts/changelog.json               CREATE
bootstrap.sh                           MODIFY   separation fixes
.gitignore                             MODIFY
tools/pipeline_analytics.py            MODIFY   --run-id, runs summary, FIFO pairing
tools/trace_analyze.py                 MODIFY   --run-id
CLAUDE.md / .claude/orchestrator.md / hooks/README.md   MODIFY  doc sync
hooks/tests/test_common.sh             CREATE
hooks/tests/test_budget_guard.sh       CREATE
hooks/tests/test_log_tool.sh           CREATE
hooks/tests/test_worktree_logging.sh   CREATE
hooks/tests/test_session_context.sh    CREATE
hooks/tests/test_on_error.sh           CREATE
hooks/tests/test_idle_timeout.sh       REWRITE
hooks/tests/test_pipeline_state.sh     MODIFY
hooks/tests/test_classify_task.sh      MODIFY
hooks/tests/test_run_id.sh             MODIFY   (setup only)
hooks/tests/test_validate_output.sh    MODIFY   (setup only)
tests/test_pipeline_analytics.py       MODIFY   add run-id filter test
```

---

### Task 1: Shared hook library (`hooks/lib/common.sh`) — fixes C1 (mechanism), C3

**Files:**
- Create: `hooks/lib/common.sh`
- Test: `hooks/tests/test_common.sh`

- [ ] **Step 1: Write the failing test**

Create `hooks/tests/test_common.sh`:

```bash
#!/bin/bash
# Tests for hooks/lib/common.sh: worktree-safe root resolution and
# pipeline_state.json context readers.
set -euo pipefail

PASS=0; FAIL=0
PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CLEANUP_DIRS=()
trap 'rm -rf "${CLEANUP_DIRS[@]:-}"' EXIT

assert_eq() {
    local name="$1" expected="$2" actual="$3"
    if [ "$actual" = "$expected" ]; then
        echo "PASS: $name"; PASS=$((PASS+1))
    else
        echo "FAIL: $name — expected '$expected', got '$actual'"; FAIL=$((FAIL+1))
    fi
}

setup_repo() {
    local tmpdir
    tmpdir=$(mktemp -d)
    CLEANUP_DIRS+=("$tmpdir")
    (
        cd "$tmpdir"
        git init -q
        git config user.email "test@test.com"
        git config user.name "Test"
        mkdir -p hooks/lib
        cp "$PROJECT_ROOT/hooks/lib/common.sh" hooks/lib/
        git add . && git commit -q -m "init"
    )
    echo "$tmpdir"
}

# Test 1: PROJECT_ROOT is the repo root even from a subdirectory
DIR=$(setup_repo)
mkdir -p "$DIR/src/deep"
GOT=$(cd "$DIR/src/deep" && source ../../hooks/lib/common.sh && echo "$PROJECT_ROOT")
assert_eq "root resolved from subdirectory" "$(cd "$DIR" && pwd -P)" "$GOT"

# Test 2: inside a git worktree, PROJECT_ROOT is the MAIN repo root
DIR=$(setup_repo)
(cd "$DIR" && git worktree add -q wt -b test-wt)
GOT=$(cd "$DIR/wt" && source hooks/lib/common.sh && echo "$PROJECT_ROOT")
assert_eq "worktree resolves to main root" "$(cd "$DIR" && pwd -P)" "$GOT"

# Test 3: context readers from a running pipeline state
DIR=$(setup_repo)
cat > "$DIR/pipeline_state.json" <<'EOF'
{"task_id":"TASK-007","pipeline":"full","run_id":"abc-123","current_step":"coder","completed_steps":["researcher"],"status":"running"}
EOF
GOT=$(cd "$DIR" && source hooks/lib/common.sh && current_agent)
assert_eq "current_agent reads current_step when running" "coder" "$GOT"
GOT=$(cd "$DIR" && source hooks/lib/common.sh && current_task_id)
assert_eq "current_task_id reads task_id when running" "TASK-007" "$GOT"
GOT=$(cd "$DIR" && source hooks/lib/common.sh && current_run_id)
assert_eq "current_run_id reads run_id" "abc-123" "$GOT"

# Test 4: env var overrides state (test/manual escape hatch)
GOT=$(cd "$DIR" && CLAUDE_CURRENT_AGENT=tester bash -c 'source hooks/lib/common.sh && current_agent')
assert_eq "CLAUDE_CURRENT_AGENT env overrides state" "tester" "$GOT"

# Test 5: completed pipeline → no current agent/task
python3 - <<EOF
import json
d = json.load(open("$DIR/pipeline_state.json")); d["status"] = "completed"
json.dump(d, open("$DIR/pipeline_state.json", "w"))
EOF
GOT=$(cd "$DIR" && source hooks/lib/common.sh && current_agent)
assert_eq "no agent when pipeline completed" "" "$GOT"

# Test 6: missing state file → empty strings, no crash
rm -f "$DIR/pipeline_state.json"
GOT=$(cd "$DIR" && source hooks/lib/common.sh && current_task_id)
assert_eq "no task when state file missing" "" "$GOT"
GOT=$(cd "$DIR" && source hooks/lib/common.sh && current_run_id)
assert_eq "no run_id when state file missing" "" "$GOT"

# Test 7: sourcing creates the per-project tmp dir
DIR=$(setup_repo)
(cd "$DIR" && source hooks/lib/common.sh)
if [ -d "$DIR/.claude/tmp" ]; then
    echo "PASS: CLAUDE_TMP_DIR created"; PASS=$((PASS+1))
else
    echo "FAIL: .claude/tmp not created"; FAIL=$((FAIL+1))
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash hooks/tests/test_common.sh`
Expected: fails immediately (`cp: .../hooks/lib/common.sh: No such file`).

- [ ] **Step 3: Implement `hooks/lib/common.sh`**

```bash
#!/bin/bash
# hooks/lib/common.sh — shared helpers sourced by every hook script.
#
# Provides:
#   PROJECT_ROOT     — MAIN repository root (worktree-safe)
#   CLAUDE_TMP_DIR   — per-project tmp dir for hook runtime state
#   state_field F    — top-level field F from pipeline_state.json ("" if absent)
#   current_agent    — active pipeline agent ("" when no pipeline is running)
#   current_task_id  — active task id ("" when no pipeline is running)
#   current_run_id   — run_id of the active pipeline run ("" if none)
#
# Worktree note: agents run in git worktrees under .claude/worktrees/.
# `git rev-parse --show-toplevel` returns the WORKTREE root there, which
# fragments logs and state. `--git-common-dir` always points at the main
# repo's .git, so dirname of it is the main root. Requires git >= 2.31.
#
# Attribution caveat: current_agent is pipeline_state.json's current_step,
# so orchestrator tool calls made while a run is active are attributed to
# the pending agent. CLAUDE_CURRENT_AGENT / CLAUDE_TASK_ID env vars, when
# present (tests, manual runs), take precedence.

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
        state_field current_step
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
```

- [ ] **Step 4: Run the test — all pass**

Run: `bash hooks/tests/test_common.sh`
Expected: `Results: 9 passed, 0 failed` (Tests 3 and 6 contain multiple asserts).

- [ ] **Step 5: Commit**

```bash
git add hooks/lib/common.sh hooks/tests/test_common.sh
git commit -m "feat(hooks): add shared lib — worktree-safe root + state-file agent context (C1, C3)"
```

---

### Task 2: Durable run metadata — `started_at` + `retries` — fixes M4, enables H6

**Files:**
- Modify: `hooks/init_pipeline_state.sh`
- Modify: `hooks/advance_pipeline_state.sh`
- Test: `hooks/tests/test_pipeline_state.sh`

- [ ] **Step 1: Add failing tests**

In `hooks/tests/test_pipeline_state.sh`, inside `setup_repo()`, after the line `cp "$PROJECT_ROOT/hooks/advance_pipeline_state.sh" hooks/`, add:

```bash
        mkdir -p hooks/lib
        cp "$PROJECT_ROOT/hooks/lib/common.sh" hooks/lib/
```

Then append these tests **before** the final `echo ""` / `echo "Results: ..."` lines:

```bash
# Test: init records started_at as ISO-8601 UTC
DIR=$(setup_repo)
(cd "$DIR" && bash hooks/init_pipeline_state.sh TASK-001 full)
STARTED=$(python3 -c "import json; print(json.load(open('$DIR/pipeline_state.json')).get('started_at',''))")
if echo "$STARTED" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8}Z$'; then
    echo "PASS: init records started_at"; PASS=$((PASS+1))
else
    echo "FAIL: started_at missing or malformed: '$STARTED'"; FAIL=$((FAIL+1))
fi

# Test: re-running a completed step counts as a retry and re-opens the step
DIR=$(setup_repo)
(cd "$DIR" && bash hooks/init_pipeline_state.sh TASK-001 full)
(cd "$DIR" && bash hooks/advance_pipeline_state.sh researcher coder)
(cd "$DIR" && bash hooks/advance_pipeline_state.sh coder reviewer)
(cd "$DIR" && bash hooks/advance_pipeline_state.sh reviewer coder)   # FIX_REQUIRED → back to coder
RETRY=$(python3 -c "import json; print(json.load(open('$DIR/pipeline_state.json')).get('retries',{}).get('coder',0))")
assert_field "retry re-opens the step (current_step=coder)" "$DIR" "current_step" "coder"
if [ "$RETRY" = "1" ]; then
    echo "PASS: retries.coder == 1 after backward transition"; PASS=$((PASS+1))
else
    echo "FAIL: retries.coder expected 1, got '$RETRY'"; FAIL=$((FAIL+1))
fi
COMPLETED=$(python3 -c "import json; print(json.load(open('$DIR/pipeline_state.json'))['completed_steps'])")
if echo "$COMPLETED" | grep -q "coder"; then
    echo "FAIL: coder still in completed_steps after retry: $COMPLETED"; FAIL=$((FAIL+1))
else
    echo "PASS: coder removed from completed_steps on retry"; PASS=$((PASS+1))
fi
```

- [ ] **Step 2: Run to verify the new tests fail**

Run: `bash hooks/tests/test_pipeline_state.sh`
Expected: previous tests pass; the 3 new asserts FAIL (`started_at` empty, `retries` missing).

- [ ] **Step 3: Implement**

In `hooks/init_pipeline_state.sh`, replace:

```bash
PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
```

with:

```bash
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
```

and in its Python heredoc add `started_at` to the state dict, directly under `"run_id"`:

```python
    "run_id": os.environ["INIT_RUN_ID"],
    "started_at": os.environ["INIT_TIMESTAMP"],
```

In `hooks/advance_pipeline_state.sh`, replace the same `PROJECT_ROOT=` line with the same `source` line, and in its Python heredoc insert **before** the `if completed not in state["completed_steps"]:` block:

```python
retries = state.setdefault("retries", {})
if next_step != "done" and next_step in state["completed_steps"]:
    retries[next_step] = retries.get(next_step, 0) + 1
    state["completed_steps"].remove(next_step)
```

- [ ] **Step 4: Run the test — all pass**

Run: `bash hooks/tests/test_pipeline_state.sh`
Expected: all pass (the pre-existing `pre_task.sh` RECOVERY test still passes — it is retargeted in Task 7).

- [ ] **Step 5: Commit**

```bash
git add hooks/init_pipeline_state.sh hooks/advance_pipeline_state.sh hooks/tests/test_pipeline_state.sh
git commit -m "feat(state): record started_at and durable retry counts in pipeline_state.json (M4)"
```

---

### Task 3: Rewrite `budget_guard.sh` — fixes C2a/C2c, H5 (path), H6, M6

**Files:**
- Rewrite: `hooks/budget_guard.sh`
- Rewrite: `contracts/pipeline-slos.md`
- Create: `hooks/tests/test_budget_guard.sh`
- Rewrite: `hooks/tests/test_idle_timeout.sh`

- [ ] **Step 1: Rewrite `contracts/pipeline-slos.md`** (parseable tables, deduped):

```markdown
# Pipeline SLO Contracts

Explicit performance envelopes for the agent pipeline, enforced by
`hooks/budget_guard.sh`. **The tables below are the source of truth** —
the script parses them at runtime; edit limits here, never in the script.

Soft limit breach → warning on stderr (visible to the user).
Hard limit breach in `CLAUDE_BUDGET_MODE=halt` → the tool call is blocked
(hook exit 2) and the reason is fed back to the model.

---

## Per-agent tool call budgets (per pipeline run)

| Agent | Soft limit | Hard limit | Rationale |
|---|---|---|---|
| researcher | 15 | 25 | Broad exploration expected |
| coder | 20 | 35 | Implementation + file reads |
| reviewer | 10 | 15 | Read-heavy, minimal writes |
| tester | 15 | 25 | Test writing + execution |
| security | 8 | 12 | Targeted diff analysis |
| git | 5 | 8 | Mechanical only |
| memory | 5 | 8 | File updates only |
| devops | 10 | 18 | CI polling + smoke tests |
| writer | 12 | 20 | Document generation |

---

## Per-task pipeline wall-clock budget (seconds)

Measured against `started_at` in `pipeline_state.json`.

| Pipeline | Warn (s) | Halt (s) |
|---|---|---|
| fast-track | 300 | 600 |
| full | 900 | 1800 |

---

## Daily aggregate

- Warn at 80% of `CLAUDE_DAILY_CALL_LIMIT` (default 500 → warn at 400)
- Halt at 100% of `CLAUDE_DAILY_CALL_LIMIT`
- Counted in UTC from `logs/tool_calls.log` (tool lines only)

---

## How budget_guard.sh resolves context

Agent identity, run_id, pipeline type, and start time are read from
`pipeline_state.json` (maintained by `init_pipeline_state.sh` /
`advance_pipeline_state.sh`). No environment variables are required;
`CLAUDE_CURRENT_AGENT` overrides the state file for tests and manual runs.
```

- [ ] **Step 2: Write the failing tests**

Create `hooks/tests/test_budget_guard.sh`:

```bash
#!/bin/bash
# Tests for budget_guard.sh: SLO-file-driven limits, per-run per-agent
# counting from pipeline.jsonl, exit-2 blocking, UTC daily count, wall-clock.
set -euo pipefail

PASS=0; FAIL=0
PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CLEANUP_DIRS=()
trap 'rm -rf "${CLEANUP_DIRS[@]:-}"' EXIT

assert_exit() {
    local name="$1" expected="$2" actual="$3"
    if [ "$actual" -eq "$expected" ]; then
        echo "PASS: $name"; PASS=$((PASS+1))
    else
        echo "FAIL: $name — expected exit $expected, got $actual"; FAIL=$((FAIL+1))
    fi
}

assert_stderr_contains() {
    local name="$1" pattern="$2" output="$3"
    if echo "$output" | grep -qF "$pattern"; then
        echo "PASS: $name"; PASS=$((PASS+1))
    else
        echo "FAIL: $name — expected '$pattern' in: $output"; FAIL=$((FAIL+1))
    fi
}

assert_stderr_not_contains() {
    local name="$1" pattern="$2" output="$3"
    if echo "$output" | grep -qF "$pattern"; then
        echo "FAIL: $name — did not expect '$pattern' in: $output"; FAIL=$((FAIL+1))
    else
        echo "PASS: $name"; PASS=$((PASS+1))
    fi
}

setup_repo() {
    local tmpdir
    tmpdir=$(mktemp -d)
    CLEANUP_DIRS+=("$tmpdir")
    (
        cd "$tmpdir"
        git init -q
        git config user.email "test@test.com"
        git config user.name "Test"
        mkdir -p hooks/lib contracts logs
        cp "$PROJECT_ROOT/hooks/budget_guard.sh" hooks/
        cp "$PROJECT_ROOT/hooks/lib/common.sh" hooks/lib/
        cp "$PROJECT_ROOT/contracts/pipeline-slos.md" contracts/
        git add . && git commit -q -m "init"
    )
    echo "$tmpdir"
}

write_state() {
    # args: dir agent run_id pipeline started_at
    cat > "$1/pipeline_state.json" <<EOF
{"task_id":"TASK-001","pipeline":"$4","run_id":"$3","current_step":"$2","completed_steps":[],"status":"running","started_at":"$5"}
EOF
}

seed_tool_calls() {
    # args: dir agent run_id count
    python3 - "$1" "$2" "$3" "$4" <<'PYEOF'
import json, sys
d, agent, run_id, n = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4])
with open(d + "/logs/pipeline.jsonl", "a") as f:
    for _ in range(n):
        f.write(json.dumps({"event": "tool_call", "tool": "Bash", "agent": agent,
                            "task_id": "TASK-001", "run_id": run_id,
                            "timestamp": "2026-06-10T10:00:00Z"}) + "\n")
PYEOF
}

run_guard() {
    # args: dir mode → sets GUARD_EXIT and GUARD_STDERR
    GUARD_EXIT=0
    GUARD_STDERR=$(cd "$1" && CLAUDE_BUDGET_MODE="$2" bash hooks/budget_guard.sh <<< '{}' 2>&1 >/dev/null) || GUARD_EXIT=$?
}

NOW_ISO=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Test 1: agent at hard limit, halt mode → exit 2 (blocking)
DIR=$(setup_repo)
write_state "$DIR" security run-1 full "$NOW_ISO"
seed_tool_calls "$DIR" security run-1 12
run_guard "$DIR" halt
assert_exit "security hard limit + halt → exit 2" 2 "$GUARD_EXIT"
assert_stderr_contains "hard limit message names agent" "Agent 'security' hard limit" "$GUARD_STDERR"

# Test 2: same, warn mode → exit 0, warning printed
run_guard "$DIR" warn
assert_exit "security hard limit + warn → exit 0" 0 "$GUARD_EXIT"
assert_stderr_contains "warn mode still reports" "Agent 'security' hard limit" "$GUARD_STDERR"

# Test 3: other agents' calls don't count against the active agent
DIR=$(setup_repo)
write_state "$DIR" security run-1 full "$NOW_ISO"
seed_tool_calls "$DIR" coder run-1 12
run_guard "$DIR" halt
assert_exit "coder calls don't trip security limit" 0 "$GUARD_EXIT"
assert_stderr_not_contains "no agent limit message" "hard limit" "$GUARD_STDERR"

# Test 4: calls from a previous run don't count
DIR=$(setup_repo)
write_state "$DIR" security run-NEW full "$NOW_ISO"
seed_tool_calls "$DIR" security run-OLD 12
run_guard "$DIR" halt
assert_exit "previous run's calls don't count" 0 "$GUARD_EXIT"

# Test 5: editing the SLO file changes the limit — no script edit
DIR=$(setup_repo)
write_state "$DIR" security run-1 full "$NOW_ISO"
sed -i.bak 's/^| security | 8 | 12 |/| security | 2 | 3 |/' "$DIR/contracts/pipeline-slos.md"
seed_tool_calls "$DIR" security run-1 3
run_guard "$DIR" halt
assert_exit "SLO file edit lowers hard limit to 3" 2 "$GUARD_EXIT"

# Test 6: soft limit → warning, exit 0
DIR=$(setup_repo)
write_state "$DIR" coder run-1 full "$NOW_ISO"
seed_tool_calls "$DIR" coder run-1 20
run_guard "$DIR" halt
assert_exit "soft limit does not block" 0 "$GUARD_EXIT"
assert_stderr_contains "soft limit warning printed" "soft limit" "$GUARD_STDERR"

# Test 7: daily count ignores CLASSIFIER/POST_TOOL/STOP lines, uses UTC
DIR=$(setup_repo)
TODAY_UTC=$(date -u +"%Y-%m-%d")
{
    echo "${TODAY_UTC}T10:00:00Z | Bash"
    echo "${TODAY_UTC}T10:00:01Z | Read"
    echo "${TODAY_UTC}T10:00:02Z | CLASSIFIER | PIPELINE:full | REASON:test"
    echo "${TODAY_UTC}T10:00:03Z | POST_TOOL | done"
    echo "${TODAY_UTC}T10:00:04Z | STOP | end"
} > "$DIR/logs/tool_calls.log"
GUARD_EXIT=0
GUARD_STDERR=$(cd "$DIR" && CLAUDE_BUDGET_MODE=halt CLAUDE_DAILY_CALL_LIMIT=3 bash hooks/budget_guard.sh <<< '{}' 2>&1 >/dev/null) || GUARD_EXIT=$?
assert_exit "marker lines excluded from daily count (2 < 3)" 0 "$GUARD_EXIT"
echo "${TODAY_UTC}T10:00:05Z | Edit" >> "$DIR/logs/tool_calls.log"
GUARD_EXIT=0
GUARD_STDERR=$(cd "$DIR" && CLAUDE_BUDGET_MODE=halt CLAUDE_DAILY_CALL_LIMIT=3 bash hooks/budget_guard.sh <<< '{}' 2>&1 >/dev/null) || GUARD_EXIT=$?
assert_exit "3rd tool line trips daily halt → exit 2" 2 "$GUARD_EXIT"

# Test 8: wall-clock budget — full pipeline running 2000s → halt
DIR=$(setup_repo)
OLD_ISO=$(python3 -c "from datetime import datetime,timezone,timedelta; print((datetime.now(timezone.utc)-timedelta(seconds=2000)).strftime('%Y-%m-%dT%H:%M:%SZ'))")
write_state "$DIR" coder run-1 full "$OLD_ISO"
run_guard "$DIR" halt
assert_exit "wall-clock 2000s > full halt 1800s → exit 2" 2 "$GUARD_EXIT"
assert_stderr_contains "wall-clock message" "wall-clock" "$GUARD_STDERR"

# Test 9: wall-clock fine when fresh
DIR=$(setup_repo)
write_state "$DIR" coder run-1 full "$NOW_ISO"
run_guard "$DIR" halt
assert_exit "fresh pipeline passes wall-clock" 0 "$GUARD_EXIT"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
```

- [ ] **Step 3: Run to verify failures**

Run: `bash hooks/tests/test_budget_guard.sh`
Expected: multiple FAILs (old guard counts daily total, exits 1, no wall-clock).

- [ ] **Step 4: Rewrite `hooks/budget_guard.sh`** (full replacement):

```bash
#!/bin/bash
# Guards tool-call volume (cost proxy), per-agent budgets, wall-clock SLOs,
# and per-agent idle timeouts. Runs on PreToolUse.
#
# Limits come from contracts/pipeline-slos.md (tables are the source of
# truth). Agent/run context comes from pipeline_state.json via
# hooks/lib/common.sh; CLAUDE_CURRENT_AGENT overrides it for tests.
#
# Env:
#   CLAUDE_DAILY_CALL_LIMIT      default 500
#   CLAUDE_BUDGET_MODE           warn|halt (default warn)
#   CLAUDE_IDLE_TIMEOUT_MINUTES  default 10
#
# Exit codes: 0 = allow (warnings on stderr), 2 = BLOCK this tool call.
# Claude Code only blocks PreToolUse on exit 2 — exit 1 does NOT block.

source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

DAILY_LIMIT="${CLAUDE_DAILY_CALL_LIMIT:-500}"
BUDGET_MODE="${CLAUDE_BUDGET_MODE:-warn}"
LOG_FILE="${PROJECT_ROOT}/logs/tool_calls.log"
PIPELINE_LOG="${PROJECT_ROOT}/logs/pipeline.jsonl"

# SLO file: .claude/contracts/ after bootstrap, contracts/ in the template
if [ -f "${PROJECT_ROOT}/.claude/contracts/pipeline-slos.md" ]; then
    SLO_FILE="${PROJECT_ROOT}/.claude/contracts/pipeline-slos.md"
else
    SLO_FILE="${PROJECT_ROOT}/contracts/pipeline-slos.md"
fi

halt_or_warn() {
    echo "$1" >&2
    if [ "${BUDGET_MODE}" = "halt" ]; then
        echo "[BUDGET] BUDGET_MODE=halt — blocking tool call." >&2
        exit 2
    fi
}

# Parse "| name | <num> | <num> |" row from an SLO table. args: name
# Prints "soft hard" (or nothing if no row matches).
slo_limits() {
    awk -F'|' -v key="$1" '
        NF >= 4 {
            name = tolower($2); gsub(/^[ \t]+|[ \t]+$/, "", name)
            a = $3; gsub(/[ \t]/, "", a)
            b = $4; gsub(/[ \t]/, "", b)
            if (name == key && a ~ /^[0-9]+$/ && b ~ /^[0-9]+$/) { print a, b; exit }
        }' "$SLO_FILE" 2>/dev/null
}

# ── Daily aggregate (UTC — log timestamps are UTC) ─────────────────────
TODAY=$(date -u +"%Y-%m-%d")
TODAYS_CALLS=0
if [ -f "${LOG_FILE}" ]; then
    # Tool lines have exactly one " | " — CLASSIFIER/POST_TOOL/STOP markers have more
    TODAYS_CALLS=$(grep -cE "^${TODAY}T[0-9:]{8}Z \| [^|]+$" "${LOG_FILE}" 2>/dev/null) || TODAYS_CALLS=0
fi

WARN_AT=$(( DAILY_LIMIT * 80 / 100 ))
if [ "${TODAYS_CALLS}" -ge "${DAILY_LIMIT}" ]; then
    halt_or_warn "[BUDGET] Daily hard limit reached: ${TODAYS_CALLS}/${DAILY_LIMIT} tool calls today."
elif [ "${TODAYS_CALLS}" -ge "${WARN_AT}" ]; then
    echo "[BUDGET] Daily soft limit warning: ${TODAYS_CALLS}/${DAILY_LIMIT} (warn at ${WARN_AT})." >&2
fi

# ── Per-agent budget (per pipeline run) ────────────────────────────────
AGENT="$(current_agent)"
RUN_ID="$(current_run_id)"
if [ -n "$AGENT" ]; then
    AGENT_LOWER=$(echo "$AGENT" | tr '[:upper:]' '[:lower:]')
    LIMITS=$(slo_limits "$AGENT_LOWER")
    SOFT=$(echo "$LIMITS" | awk '{print $1}')
    HARD=$(echo "$LIMITS" | awk '{print $2}')

    if [ -n "$HARD" ]; then
        AGENT_CALLS=$(python3 - "$AGENT" "$RUN_ID" "$PIPELINE_LOG" <<'PYEOF'
import json, sys
agent, run_id, path = sys.argv[1], sys.argv[2], sys.argv[3]
n = 0
try:
    with open(path) as f:
        for line in f:
            try:
                d = json.loads(line)
            except json.JSONDecodeError:
                continue
            if d.get("event") != "tool_call" or d.get("agent") != agent:
                continue
            if run_id and d.get("run_id") != run_id:
                continue
            n += 1
except FileNotFoundError:
    pass
print(n)
PYEOF
)
        if [ "${AGENT_CALLS:-0}" -ge "${HARD}" ]; then
            halt_or_warn "[BUDGET] Agent '${AGENT}' hard limit reached: ${AGENT_CALLS} calls this run (hard=${HARD})."
        elif [ -n "$SOFT" ] && [ "${AGENT_CALLS:-0}" -ge "${SOFT}" ]; then
            echo "[BUDGET] Agent '${AGENT}' soft limit warning: ${AGENT_CALLS} calls this run (soft=${SOFT}, hard=${HARD})." >&2
        fi
    fi

    # ── Per-agent idle timeout (retrospective: evaluated on the NEXT call) ──
    LAST_TOOL_FILE="${CLAUDE_TMP_DIR}/last_tool_${AGENT}"
    if [ -f "$LAST_TOOL_FILE" ]; then
        LAST_TS=$(cat "$LAST_TOOL_FILE" 2>/dev/null || echo "")
        if [ -n "$LAST_TS" ]; then
            NOW_TS=$(date +%s)
            IDLE_SECS=$(( NOW_TS - LAST_TS ))
            IDLE_LIMIT=$(( ${CLAUDE_IDLE_TIMEOUT_MINUTES:-10} * 60 ))
            if [ "$IDLE_SECS" -ge "$IDLE_LIMIT" ]; then
                halt_or_warn "[BUDGET] Agent '${AGENT}' idle for ${IDLE_SECS}s (limit=${IDLE_LIMIT}s — no tool call detected)."
            fi
        fi
    fi
fi

# ── Wall-clock SLO for the active pipeline run ─────────────────────────
if [ "$(state_field status)" = "running" ]; then
    PIPELINE="$(state_field pipeline)"
    STARTED_AT="$(state_field started_at)"
    if [ -n "$PIPELINE" ] && [ -n "$STARTED_AT" ]; then
        WALL=$(slo_limits "$(echo "$PIPELINE" | tr '[:upper:]' '[:lower:]')")
        WALL_WARN=$(echo "$WALL" | awk '{print $1}')
        WALL_HALT=$(echo "$WALL" | awk '{print $2}')
        if [ -n "$WALL_HALT" ]; then
            START_EPOCH=$(python3 -c "from datetime import datetime; print(int(datetime.fromisoformat('${STARTED_AT}'.replace('Z','+00:00')).timestamp()))" 2>/dev/null || echo "")
            if [ -n "$START_EPOCH" ]; then
                ELAPSED=$(( $(date +%s) - START_EPOCH ))
                if [ "$ELAPSED" -ge "$WALL_HALT" ]; then
                    halt_or_warn "[BUDGET] Pipeline '${PIPELINE}' wall-clock budget exceeded: ${ELAPSED}s (halt=${WALL_HALT}s)."
                elif [ "$ELAPSED" -ge "$WALL_WARN" ]; then
                    echo "[BUDGET] Pipeline '${PIPELINE}' wall-clock warning: ${ELAPSED}s (warn=${WALL_WARN}s, halt=${WALL_HALT}s)." >&2
                fi
            fi
        fi
    fi
fi

exit 0
```

- [ ] **Step 5: Rewrite `hooks/tests/test_idle_timeout.sh`** — temp-repo based, new path, exit 2. The old Test 1 (log_tool writes the timestamp) moves to `test_log_tool.sh` in Task 4. Full replacement:

```bash
#!/bin/bash
# Tests for the per-agent idle timeout in budget_guard.sh.
# Timestamp files live in <project>/.claude/tmp/last_tool_<agent>.
set -euo pipefail

PASS=0; FAIL=0
PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CLEANUP_DIRS=()
trap 'rm -rf "${CLEANUP_DIRS[@]:-}"' EXIT

assert_exit() {
    local name="$1" expected="$2" actual="$3"
    if [ "$actual" -eq "$expected" ]; then
        echo "PASS: $name"; PASS=$((PASS+1))
    else
        echo "FAIL: $name — expected exit $expected, got $actual"; FAIL=$((FAIL+1))
    fi
}

assert_stderr_contains() {
    local name="$1" pattern="$2" output="$3"
    if echo "$output" | grep -qF "$pattern"; then
        echo "PASS: $name"; PASS=$((PASS+1))
    else
        echo "FAIL: $name — expected '$pattern' in: $output"; FAIL=$((FAIL+1))
    fi
}

assert_stderr_not_contains() {
    local name="$1" pattern="$2" output="$3"
    if echo "$output" | grep -qF "$pattern"; then
        echo "FAIL: $name — did not expect '$pattern' in: $output"; FAIL=$((FAIL+1))
    else
        echo "PASS: $name"; PASS=$((PASS+1))
    fi
}

setup_repo() {
    local tmpdir
    tmpdir=$(mktemp -d)
    CLEANUP_DIRS+=("$tmpdir")
    (
        cd "$tmpdir"
        git init -q
        git config user.email "test@test.com"
        git config user.name "Test"
        mkdir -p hooks/lib contracts logs .claude/tmp
        cp "$PROJECT_ROOT/hooks/budget_guard.sh" hooks/
        cp "$PROJECT_ROOT/hooks/lib/common.sh" hooks/lib/
        cp "$PROJECT_ROOT/contracts/pipeline-slos.md" contracts/
        git add . && git commit -q -m "init"
    )
    echo "$tmpdir"
}

run_guard() {
    # args: dir mode minutes → sets GUARD_EXIT and GUARD_STDERR
    GUARD_EXIT=0
    GUARD_STDERR=$(cd "$1" && CLAUDE_CURRENT_AGENT=coder CLAUDE_BUDGET_MODE="$2" CLAUDE_IDLE_TIMEOUT_MINUTES="$3" \
        bash hooks/budget_guard.sh <<< '{}' 2>&1 >/dev/null) || GUARD_EXIT=$?
}

# Test 1: fresh timestamp → no warning, exit 0
DIR=$(setup_repo)
date +%s > "$DIR/.claude/tmp/last_tool_coder"
run_guard "$DIR" warn 10
assert_exit "fresh timestamp exits 0" 0 "$GUARD_EXIT"
assert_stderr_not_contains "fresh timestamp — no idle warning" "idle" "$GUARD_STDERR"

# Test 2: stale timestamp + warn → warning, exit 0
DIR=$(setup_repo)
echo $(( $(date +%s) - 700 )) > "$DIR/.claude/tmp/last_tool_coder"
run_guard "$DIR" warn 10
assert_exit "stale + warn exits 0" 0 "$GUARD_EXIT"
assert_stderr_contains "stale + warn prints idle warning" "Agent 'coder' idle" "$GUARD_STDERR"

# Test 3: stale timestamp + halt → exit 2 (blocking)
DIR=$(setup_repo)
echo $(( $(date +%s) - 700 )) > "$DIR/.claude/tmp/last_tool_coder"
run_guard "$DIR" halt 10
assert_exit "stale + halt exits 2" 2 "$GUARD_EXIT"

# Test 4: no timestamp file (first call) → no warning
DIR=$(setup_repo)
run_guard "$DIR" warn 10
assert_exit "no file exits 0" 0 "$GUARD_EXIT"
assert_stderr_not_contains "no file — no idle warning" "idle" "$GUARD_STDERR"

# Test 5: custom threshold — 90s old with 1-minute limit fires
DIR=$(setup_repo)
echo $(( $(date +%s) - 90 )) > "$DIR/.claude/tmp/last_tool_coder"
run_guard "$DIR" warn 1
assert_stderr_contains "90s old, 1-min limit fires" "Agent 'coder' idle" "$GUARD_STDERR"

# Test 6: custom threshold — 30s old with 1-minute limit does not fire
DIR=$(setup_repo)
echo $(( $(date +%s) - 30 )) > "$DIR/.claude/tmp/last_tool_coder"
run_guard "$DIR" warn 1
assert_stderr_not_contains "30s old, 1-min limit silent" "idle" "$GUARD_STDERR"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
```

- [ ] **Step 6: Run both test files — all pass**

Run: `bash hooks/tests/test_budget_guard.sh && bash hooks/tests/test_idle_timeout.sh`
Expected: both print `0 failed`.

- [ ] **Step 7: Commit**

```bash
git add hooks/budget_guard.sh contracts/pipeline-slos.md hooks/tests/test_budget_guard.sh hooks/tests/test_idle_timeout.sh
git commit -m "fix(guards): SLO-file limits, per-run agent counts, exit-2 halts, UTC daily count, wall-clock SLO (C2, H5, H6, M6)"
```

---

### Task 4: Rewrite `log_tool.sh`, delete `post_task.sh` — fixes C1 (attribution), C2c, C3, L4

**Files:**
- Rewrite: `hooks/log_tool.sh`
- Delete: `hooks/post_task.sh`
- Modify: `.claude/settings.json` (remove PostToolUse block)
- Create: `hooks/tests/test_log_tool.sh`

- [ ] **Step 1: Write the failing test**

Create `hooks/tests/test_log_tool.sh`:

```bash
#!/bin/bash
# Tests for log_tool.sh: PreToolUse-only flat logging, state-file agent
# context, pipeline.jsonl tool_call events, worktree-safe central logging.
set -euo pipefail

PASS=0; FAIL=0
PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CLEANUP_DIRS=()
trap 'rm -rf "${CLEANUP_DIRS[@]:-}"' EXIT

assert_eq() {
    local name="$1" expected="$2" actual="$3"
    if [ "$actual" = "$expected" ]; then
        echo "PASS: $name"; PASS=$((PASS+1))
    else
        echo "FAIL: $name — expected '$expected', got '$actual'"; FAIL=$((FAIL+1))
    fi
}

setup_repo() {
    local tmpdir
    tmpdir=$(mktemp -d)
    CLEANUP_DIRS+=("$tmpdir")
    (
        cd "$tmpdir"
        git init -q
        git config user.email "test@test.com"
        git config user.name "Test"
        mkdir -p hooks/lib logs
        cp "$PROJECT_ROOT/hooks/log_tool.sh" hooks/
        cp "$PROJECT_ROOT/hooks/lib/common.sh" hooks/lib/
        git add . && git commit -q -m "init"
    )
    echo "$tmpdir"
}

# Test 1: PreToolUse event appends exactly one flat line
DIR=$(setup_repo)
(cd "$DIR" && echo '{"tool_name":"Bash","hook_event_name":"PreToolUse"}' | bash hooks/log_tool.sh)
assert_eq "PreToolUse logs one line" "1" "$(wc -l < "$DIR/logs/tool_calls.log" | tr -d ' ')"

# Test 2: PostToolUse event appends nothing
(cd "$DIR" && echo '{"tool_name":"Bash","hook_event_name":"PostToolUse"}' | bash hooks/log_tool.sh)
assert_eq "PostToolUse logs nothing" "1" "$(wc -l < "$DIR/logs/tool_calls.log" | tr -d ' ')"

# Test 3: no pipeline running → no tool_call event
if [ -f "$DIR/logs/pipeline.jsonl" ] && grep -q tool_call "$DIR/logs/pipeline.jsonl"; then
    echo "FAIL: tool_call event written without active pipeline"; FAIL=$((FAIL+1))
else
    echo "PASS: no tool_call event without active pipeline"; PASS=$((PASS+1))
fi

# Test 4: running pipeline → tool_call event with agent + run_id from state file
cat > "$DIR/pipeline_state.json" <<'EOF'
{"task_id":"TASK-009","pipeline":"full","run_id":"run-xyz","current_step":"coder","completed_steps":[],"status":"running"}
EOF
(cd "$DIR" && echo '{"tool_name":"Edit","hook_event_name":"PreToolUse"}' | bash hooks/log_tool.sh)
LAST=$(tail -1 "$DIR/logs/pipeline.jsonl")
assert_eq "event is tool_call" "tool_call" "$(echo "$LAST" | python3 -c 'import json,sys; print(json.load(sys.stdin)["event"])')"
assert_eq "agent from state file" "coder" "$(echo "$LAST" | python3 -c 'import json,sys; print(json.load(sys.stdin)["agent"])')"
assert_eq "run_id from state file" "run-xyz" "$(echo "$LAST" | python3 -c 'import json,sys; print(json.load(sys.stdin)["run_id"])')"
assert_eq "task_id from state file" "TASK-009" "$(echo "$LAST" | python3 -c 'import json,sys; print(json.load(sys.stdin)["task_id"])')"

# Test 5: idle timestamp written to .claude/tmp
if [ -f "$DIR/.claude/tmp/last_tool_coder" ]; then
    echo "PASS: idle timestamp at .claude/tmp/last_tool_coder"; PASS=$((PASS+1))
else
    echo "FAIL: idle timestamp not at .claude/tmp/last_tool_coder"; FAIL=$((FAIL+1))
fi

# Test 6: from inside a worktree, events land in the MAIN repo's logs
(cd "$DIR" && git add -A && git commit -q -m "wip" && git worktree add -q wt -b test-wt)
BEFORE=$(wc -l < "$DIR/logs/pipeline.jsonl" | tr -d ' ')
(cd "$DIR/wt" && echo '{"tool_name":"Write","hook_event_name":"PreToolUse"}' | bash hooks/log_tool.sh)
AFTER=$(wc -l < "$DIR/logs/pipeline.jsonl" | tr -d ' ')
assert_eq "worktree call appends to MAIN pipeline.jsonl" "$((BEFORE + 1))" "$AFTER"
if [ -f "$DIR/wt/logs/pipeline.jsonl" ]; then
    echo "FAIL: worktree got its own pipeline.jsonl"; FAIL=$((FAIL+1))
else
    echo "PASS: no fragmented log in the worktree"; PASS=$((PASS+1))
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
```

Note for Test 6: the committed `pipeline_state.json` and `logs/` are checked out into the worktree too — that is fine; the assertion is that the **main** log grows and the worktree log isn't created by the hook. The hook resolves `PROJECT_ROOT` to the main root, so it appends there. The worktree checkout contains the `logs/tool_calls.log` committed at "wip" — the hook must not append to it (it writes via `PROJECT_ROOT`). `pipeline.jsonl` did not exist at commit time only if the state events hadn't been written; since Test 4 wrote it before the commit, the worktree checkout will contain a copy — so the assertion uses **file growth of the main log**, and the "no fragmented log" check is meaningful because git checkout would only place a `pipeline.jsonl` in `wt/logs/` if it was committed. It was committed at "wip", so adjust: delete it from the worktree before the call: add `rm -f "$DIR/wt/logs/pipeline.jsonl"` after the `git worktree add` line.

- [ ] **Step 2: Run to verify failures**

Run: `bash hooks/tests/test_log_tool.sh`
Expected: Test 2 FAILs (old script logs on Post too), Test 4 FAILs (no state-file context), Test 5 FAILs (old path), Test 6 FAILs (worktree-local root).

- [ ] **Step 3: Rewrite `hooks/log_tool.sh`** (full replacement):

```bash
#!/bin/bash
# Logs tool calls. Reads the hook event JSON from stdin.
#
# - Flat line to logs/tool_calls.log — PreToolUse only, so each call is
#   counted exactly once (this script is also safe if registered on Post).
# - Structured tool_call event to logs/pipeline.jsonl whenever a pipeline
#   run is active. Agent/task/run context comes from pipeline_state.json
#   via hooks/lib/common.sh — no env vars required.
# - Per-agent idle timestamp to .claude/tmp/ (read by budget_guard.sh).

source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
LOG_FILE="${PROJECT_ROOT}/logs/tool_calls.log"
mkdir -p "${PROJECT_ROOT}/logs"

INPUT=$(cat)

TOOL_NAME=$(printf '%s' "$INPUT" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('tool_name','unknown'))" 2>/dev/null || echo "unknown")
HOOK_EVENT=$(printf '%s' "$INPUT" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('hook_event_name',''))" 2>/dev/null || echo "")

# Only record the Pre side — Post would double-count every call.
if [ "$HOOK_EVENT" = "PostToolUse" ]; then
    exit 0
fi

echo "${TIMESTAMP} | ${TOOL_NAME}" >> "${LOG_FILE}"

TASK_ID="$(current_task_id)"
AGENT="$(current_agent)"
if [ -n "$TASK_ID" ] && [ -n "$AGENT" ]; then
    LT_RUN_ID="$(current_run_id)"
    export LT_TOOL="$TOOL_NAME" LT_TASK="$TASK_ID" LT_AGENT="$AGENT" LT_TIMESTAMP="$TIMESTAMP" LT_PROJECT_ROOT="$PROJECT_ROOT" LT_RUN_ID
    python3 - <<'PYEOF'
import json, os
from pathlib import Path
record = {
    "event": "tool_call",
    "tool": os.environ["LT_TOOL"],
    "agent": os.environ["LT_AGENT"],
    "task_id": os.environ["LT_TASK"],
    "timestamp": os.environ["LT_TIMESTAMP"]
}
run_id = os.environ.get("LT_RUN_ID", "")
if run_id:
    record["run_id"] = run_id
p = Path(os.environ["LT_PROJECT_ROOT"]) / "logs" / "pipeline.jsonl"
with p.open("a") as f:
    f.write(json.dumps(record) + "\n")
PYEOF
fi

# Idle-timeout timestamp (read by budget_guard.sh)
if [ -n "$AGENT" ]; then
    date +%s > "${CLAUDE_TMP_DIR}/last_tool_${AGENT}"
fi
```

- [ ] **Step 4: Delete `hooks/post_task.sh` and unregister PostToolUse**

```bash
git rm hooks/post_task.sh
```

In `.claude/settings.json`, delete the entire `"PostToolUse"` block (the array with `post_task.sh` and `log_tool.sh`). Leave `SessionStart`, `PreToolUse`, and `Stop` as they are for now (Task 7 finalizes this file).

- [ ] **Step 5: Run tests — all pass**

Run: `bash hooks/tests/test_log_tool.sh && bash hooks/tests/test_idle_timeout.sh`
Expected: `0 failed` in both.

- [ ] **Step 6: Commit**

```bash
git add hooks/log_tool.sh .claude/settings.json hooks/tests/test_log_tool.sh
git commit -m "fix(logging): PreToolUse-only counting, state-file attribution, worktree-safe central log; drop post_task.sh (C1, C2c, C3, L4)"
```

---

### Task 5: Fix `classify_task.sh` — fixes H2, H5 (shared /tmp)

**Files:**
- Modify: `hooks/classify_task.sh`
- Modify: `hooks/tests/test_classify_task.sh`

- [ ] **Step 1: Add failing tests**

In `hooks/tests/test_classify_task.sh`:

(a) In `setup_repo()`, after `cp "$PROJECT_ROOT/hooks/classify_task.sh" hooks/`, add:

```bash
    mkdir -p hooks/lib
    cp "$PROJECT_ROOT/hooks/lib/common.sh" hooks/lib/
```

(b) Replace the body of `assert_verdict()` so it reads the per-project file (note `$DIR` is set globally before each call):

```bash
assert_verdict() {
    local name="$1" expected="$2"
    actual=$(cat "$DIR/.claude/tmp/task_mode" 2>/dev/null || echo "MISSING")
    if [ "$actual" = "$expected" ]; then
        echo "PASS: $name"; PASS=$((PASS+1))
    else
        echo "FAIL: $name — expected='$expected' got='$actual'"; FAIL=$((FAIL+1))
    fi
    rm -f "$DIR/.claude/tmp/task_mode" "$DIR/.claude/tmp/task_mode_hash"
}
```

(c) In Test 14 (caching), replace `echo "FORCE_FULL" > /tmp/task_mode` with `echo "FORCE_FULL" > "$DIR/.claude/tmp/task_mode"`.

(d) Append before the results footer:

```bash
# ── Test 16: untracked .claude/ content does NOT force the full pipeline ──
DIR=$(setup_repo)
(cd "$DIR"
mkdir -p .claude/worktrees/feat-auth-thing
echo "x" > .claude/worktrees/feat-auth-thing/file.txt
echo '{}' | bash hooks/classify_task.sh)
assert_verdict ".claude/worktrees/ untracked files stay AMBIGUOUS" "AMBIGUOUS"

# ── Test 17: untracked pipeline_state.json does NOT force the full pipeline ──
DIR=$(setup_repo)
(cd "$DIR"
echo '{"status":"running"}' > pipeline_state.json
echo '{}' | bash hooks/classify_task.sh)
assert_verdict "pipeline_state.json stays AMBIGUOUS" "AMBIGUOUS"
```

- [ ] **Step 2: Run to verify failures**

Run: `bash hooks/tests/test_classify_task.sh`
Expected: every test FAILs with `MISSING` (verdict still written to `/tmp/task_mode`), plus Tests 16–17 fail on the rule itself.

- [ ] **Step 3: Implement in `hooks/classify_task.sh`**

(a) Replace:

```bash
PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
TASK_FILE="$PROJECT_ROOT/TASKS.md"
VERDICT_FILE="/tmp/task_mode"
HASH_FILE="/tmp/task_mode_hash"
```

with:

```bash
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
TASK_FILE="$PROJECT_ROOT/TASKS.md"
VERDICT_FILE="${CLAUDE_TMP_DIR}/task_mode"
HASH_FILE="${CLAUDE_TMP_DIR}/task_mode_hash"
```

(b) Replace the run_id lookup:

```bash
CLASSIFY_RUN_ID=$(python3 -c "import json; d=json.load(open('${PROJECT_ROOT}/pipeline_state.json')); print(d.get('run_id',''))" 2>/dev/null || echo "")
```

with:

```bash
CLASSIFY_RUN_ID="$(current_run_id)"
```

(c) In the `CHANGED_FILES` filter, extend the exclusion group — replace:

```bash
    | grep -vE "^(\.next|node_modules|dist|build|\.turbo|tsconfig\.tsbuildinfo|__pycache__|\.pytest_cache)")
```

with:

```bash
    | grep -vE "^(\.next|node_modules|dist|build|\.turbo|tsconfig\.tsbuildinfo|__pycache__|\.pytest_cache|\.claude/)")
```

(d) In the `NEW_FILES` computation, replace:

```bash
    | grep -vE "(logs/|memory/|docs/superpowers/)" \
```

with:

```bash
    | grep -vE "(logs/|memory/|docs/superpowers/|\.claude/|pipeline_state\.json)" \
```

- [ ] **Step 4: Run the test — all pass**

Run: `bash hooks/tests/test_classify_task.sh`
Expected: `0 failed` (17 test sections).

- [ ] **Step 5: Commit**

```bash
git add hooks/classify_task.sh hooks/tests/test_classify_task.sh
git commit -m "fix(classifier): per-project verdict files; stop forcing FULL on .claude/ and pipeline_state.json (H2, H5)"
```

---

### Task 6: Worktree-safe `log_agent.sh` + `validate_output.sh`, envelope event tag — fixes C3, M1 (part)

**Files:**
- Modify: `hooks/log_agent.sh`
- Modify: `hooks/validate_output.sh`
- Create: `hooks/tests/test_worktree_logging.sh`
- Modify: `hooks/tests/test_run_id.sh`, `hooks/tests/test_validate_output.sh` (setup only)

- [ ] **Step 1: Write the failing test**

Create `hooks/tests/test_worktree_logging.sh`:

```bash
#!/bin/bash
# log_agent.sh and validate_output.sh must write to the MAIN repo's logs
# even when invoked from inside a git worktree, and validated envelopes
# must carry an "event" field so analytics can see them.
set -euo pipefail

PASS=0; FAIL=0
PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CLEANUP_DIRS=()
trap 'rm -rf "${CLEANUP_DIRS[@]:-}"' EXIT

tmpdir=$(mktemp -d)
CLEANUP_DIRS+=("$tmpdir")
(
    cd "$tmpdir"
    git init -q
    git config user.email "test@test.com"
    git config user.name "Test"
    mkdir -p hooks/lib contracts logs
    cp "$PROJECT_ROOT/hooks/log_agent.sh" hooks/
    cp "$PROJECT_ROOT/hooks/validate_output.sh" hooks/
    cp "$PROJECT_ROOT/hooks/init_pipeline_state.sh" hooks/
    cp "$PROJECT_ROOT/hooks/lib/common.sh" hooks/lib/
    cp "$PROJECT_ROOT/contracts/coder.json" contracts/
    git add . && git commit -q -m "init"
    git worktree add -q wt -b test-wt
    rm -rf wt/logs
)

# Init pipeline state in the MAIN root
(cd "$tmpdir" && bash hooks/init_pipeline_state.sh TASK-001 full >/dev/null)
RUN_ID=$(python3 -c "import json; print(json.load(open('$tmpdir/pipeline_state.json'))['run_id'])")

# Test 1: log_agent.sh from inside the worktree writes to the MAIN pipeline.jsonl
(cd "$tmpdir/wt" && bash hooks/log_agent.sh coder START TASK-001 full >/dev/null)
LAST=$(tail -1 "$tmpdir/logs/pipeline.jsonl" 2>/dev/null || echo "{}")
GOT_RUN=$(echo "$LAST" | python3 -c "import json,sys; print(json.load(sys.stdin).get('run_id',''))")
if [ "$GOT_RUN" = "$RUN_ID" ]; then
    echo "PASS: worktree log_agent writes main log with run_id"; PASS=$((PASS+1))
else
    echo "FAIL: expected run_id '$RUN_ID' in main log, got '$GOT_RUN' (last: $LAST)"; FAIL=$((FAIL+1))
fi
if [ -f "$tmpdir/wt/logs/pipeline.jsonl" ]; then
    echo "FAIL: worktree got its own pipeline.jsonl"; FAIL=$((FAIL+1))
else
    echo "PASS: no fragmented log in worktree"; PASS=$((PASS+1))
fi

# Test 2: validated envelope gets event=agent_envelope and run_id, in MAIN log
ENVELOPE='{"task_id":"TASK-001","agent":"coder","verdict":"DONE","payload":{},"next_agent":"reviewer","timestamp":"2026-06-10T10:00:00Z"}'
(cd "$tmpdir/wt" && echo "$ENVELOPE" | bash hooks/validate_output.sh coder >/dev/null)
LAST=$(tail -1 "$tmpdir/logs/pipeline.jsonl")
GOT_EVENT=$(echo "$LAST" | python3 -c "import json,sys; print(json.load(sys.stdin).get('event',''))")
GOT_RUN=$(echo "$LAST" | python3 -c "import json,sys; print(json.load(sys.stdin).get('run_id',''))")
if [ "$GOT_EVENT" = "agent_envelope" ]; then
    echo "PASS: envelope tagged event=agent_envelope"; PASS=$((PASS+1))
else
    echo "FAIL: envelope event tag missing, got '$GOT_EVENT'"; FAIL=$((FAIL+1))
fi
if [ "$GOT_RUN" = "$RUN_ID" ]; then
    echo "PASS: envelope carries run_id from main state"; PASS=$((PASS+1))
else
    echo "FAIL: envelope run_id expected '$RUN_ID', got '$GOT_RUN'"; FAIL=$((FAIL+1))
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
```

- [ ] **Step 2: Run to verify failures**

Run: `bash hooks/tests/test_worktree_logging.sh`
Expected: FAILs — old scripts resolve the worktree root, and the envelope has no event tag.

- [ ] **Step 3: Implement**

In `hooks/log_agent.sh`, replace:

```bash
PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
```

with:

```bash
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
```

and replace:

```bash
RUN_ID=$(python3 -c "import json; d=json.load(open('${PROJECT_ROOT}/pipeline_state.json')); print(d.get('run_id',''))" 2>/dev/null || echo "")
```

with:

```bash
RUN_ID="$(current_run_id)"
```

In `hooks/validate_output.sh`, replace:

```bash
PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
```

with:

```bash
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
```

replace:

```bash
VALIDATE_RUN_ID=$(python3 -c "import json; d=json.load(open('${PROJECT_ROOT}/pipeline_state.json')); print(d.get('run_id',''))" 2>/dev/null || echo "")
```

with:

```bash
VALIDATE_RUN_ID="$(current_run_id)"
```

and in its Python block, right after `envelope["run_id"] = run_id` (inside the `if run_id:`), add at the same level as the `if`:

```python
    envelope.setdefault("event", "agent_envelope")
```

(Note: `validate_output.sh` uses `set -euo pipefail`; `common.sh` is safe under it.)

- [ ] **Step 4: Fix existing test setups**

`hooks/tests/test_run_id.sh` and `hooks/tests/test_validate_output.sh` copy these scripts into temp repos. In each file, find the setup function containing lines like `cp "$PROJECT_ROOT/hooks/log_agent.sh" hooks/` (use `grep -n 'cp "$PROJECT_ROOT/hooks/' hooks/tests/test_run_id.sh hooks/tests/test_validate_output.sh`) and add right after those `cp` lines:

```bash
    mkdir -p hooks/lib
    cp "$PROJECT_ROOT/hooks/lib/common.sh" hooks/lib/
```

- [ ] **Step 5: Run all four — all pass**

Run: `bash hooks/tests/test_worktree_logging.sh && bash hooks/tests/test_run_id.sh && bash hooks/tests/test_validate_output.sh && bash hooks/tests/test_pipeline_state.sh`
Expected: `0 failed` everywhere.

- [ ] **Step 6: Commit**

```bash
git add hooks/log_agent.sh hooks/validate_output.sh hooks/tests/
git commit -m "fix(logging): worktree-safe agent/envelope logging; tag envelopes with event field (C3, M1)"
```

---

### Task 7: SessionStart context injection — fixes H1

**Files:**
- Create: `hooks/session_context.sh`
- Modify: `hooks/session_override.sh` (stderr → stdout)
- Delete: `hooks/pre_task.sh`
- Modify: `.claude/settings.json` (final shape)
- Create: `hooks/tests/test_session_context.sh`
- Modify: `hooks/tests/test_pipeline_state.sh` (remove the pre_task RECOVERY test)

- [ ] **Step 1: Write the failing test**

Create `hooks/tests/test_session_context.sh`:

```bash
#!/bin/bash
# session_context.sh must print memory context and the pipeline recovery
# hint to STDOUT (SessionStart stdout is injected into model context;
# stderr is not — that was the original bug).
set -euo pipefail

PASS=0; FAIL=0
PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CLEANUP_DIRS=()
trap 'rm -rf "${CLEANUP_DIRS[@]:-}"' EXIT

setup_repo() {
    local tmpdir
    tmpdir=$(mktemp -d)
    CLEANUP_DIRS+=("$tmpdir")
    (
        cd "$tmpdir"
        git init -q
        git config user.email "test@test.com"
        git config user.name "Test"
        mkdir -p hooks/lib memory
        cp "$PROJECT_ROOT/hooks/session_context.sh" hooks/
        cp "$PROJECT_ROOT/hooks/lib/common.sh" hooks/lib/
        git add . && git commit -q -m "init"
    )
    echo "$tmpdir"
}

assert_stdout_contains() {
    local name="$1" pattern="$2" output="$3"
    if echo "$output" | grep -qF "$pattern"; then
        echo "PASS: $name"; PASS=$((PASS+1))
    else
        echo "FAIL: $name — expected '$pattern' in stdout"; FAIL=$((FAIL+1))
    fi
}

# Test 1: core.md content goes to STDOUT (not stderr)
DIR=$(setup_repo)
echo "PROJECT-CORE-SENTINEL" > "$DIR/memory/core.md"
OUT=$(cd "$DIR" && echo '{}' | bash hooks/session_context.sh 2>/dev/null)
assert_stdout_contains "core.md on stdout" "PROJECT-CORE-SENTINEL" "$OUT"
ERR=$(cd "$DIR" && echo '{}' | bash hooks/session_context.sh 2>&1 >/dev/null)
if [ -z "$ERR" ]; then
    echo "PASS: nothing on stderr"; PASS=$((PASS+1))
else
    echo "FAIL: unexpected stderr: $ERR"; FAIL=$((FAIL+1))
fi

# Test 2: recovery hint on stdout when a pipeline is mid-run
cat > "$DIR/pipeline_state.json" <<'EOF'
{"task_id":"TASK-003","pipeline":"full","run_id":"r1","current_step":"coder","completed_steps":["researcher"],"status":"running"}
EOF
OUT=$(cd "$DIR" && echo '{}' | bash hooks/session_context.sh 2>/dev/null)
assert_stdout_contains "recovery block present" "PIPELINE RECOVERY" "$OUT"
assert_stdout_contains "recovery names the step" "coder" "$OUT"
assert_stdout_contains "recovery names the task" "TASK-003" "$OUT"

# Test 3: no crash and no recovery block when state is completed
python3 - <<EOF
import json
d = json.load(open("$DIR/pipeline_state.json")); d["status"] = "completed"
json.dump(d, open("$DIR/pipeline_state.json", "w"))
EOF
OUT=$(cd "$DIR" && echo '{}' | bash hooks/session_context.sh 2>/dev/null)
if echo "$OUT" | grep -q "PIPELINE RECOVERY"; then
    echo "FAIL: recovery block shown for completed pipeline"; FAIL=$((FAIL+1))
else
    echo "PASS: no recovery block when completed"; PASS=$((PASS+1))
fi

# Test 4: small/missing memory files are skipped without error
DIR=$(setup_repo)
OUT=$(cd "$DIR" && echo '{}' | bash hooks/session_context.sh 2>/dev/null) || { echo "FAIL: crashed on empty memory"; FAIL=$((FAIL+1)); }
echo "PASS: runs cleanly with no memory files"; PASS=$((PASS+1))

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
```

- [ ] **Step 2: Run to verify it fails**

Run: `bash hooks/tests/test_session_context.sh`
Expected: fails at setup (`session_context.sh: No such file`).

- [ ] **Step 3: Create `hooks/session_context.sh`**

```bash
#!/bin/bash
# SessionStart hook — injects project memory and pipeline recovery state
# into the model's context. SessionStart STDOUT is added to context;
# stderr (and PreToolUse stdout) is not — which is why this replaced the
# old pre_task.sh PreToolUse/stderr approach.

source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

cat > /dev/null  # consume stdin per hook protocol

MEMORY_DIR="${PROJECT_ROOT}/memory"

if [ -f "${MEMORY_DIR}/core.md" ]; then
    echo "=== PROJECT CORE ==="
    cat "${MEMORY_DIR}/core.md"
    echo "===================="
fi

if [ -f "${MEMORY_DIR}/session_checkpoint.md" ]; then
    CHECKPOINT_SIZE=$(wc -c < "${MEMORY_DIR}/session_checkpoint.md")
    if [ "${CHECKPOINT_SIZE}" -gt 50 ]; then
        echo "=== SESSION CHECKPOINT ==="
        cat "${MEMORY_DIR}/session_checkpoint.md"
        echo "=========================="
    fi
fi

if [ -f "${MEMORY_DIR}/scratchpad.md" ]; then
    SCRATCHPAD_SIZE=$(wc -c < "${MEMORY_DIR}/scratchpad.md")
    if [ "${SCRATCHPAD_SIZE}" -gt 100 ]; then
        echo "=== SCRATCHPAD ==="
        cat "${MEMORY_DIR}/scratchpad.md"
        echo "=================="
    fi
fi

# Pipeline recovery: if a run was mid-flight when the last session ended,
# tell the orchestrator exactly where to resume.
if [ "$(state_field status)" = "running" ]; then
    TASK="$(state_field task_id)"
    STEP="$(state_field current_step)"
    DONE="$(state_field completed_steps)"
    echo "=== PIPELINE RECOVERY ==="
    echo "RECOVERY: Task ${TASK} was in progress at step '${STEP}'. Resume from '${STEP}' — do not restart the pipeline."
    echo "Completed steps: ${DONE}"
    echo "========================="
fi

exit 0
```

- [ ] **Step 4: Convert `hooks/session_override.sh` to stdout**

Replace `cat >&2 <<'EOF'` with `cat <<'EOF'` (the banner must reach the model, not the user pane).

- [ ] **Step 5: Delete `pre_task.sh`, finalize `settings.json`**

```bash
git rm hooks/pre_task.sh
rm -f .claude/last_session_id
```

Replace the `"hooks"` object in `.claude/settings.json` with:

```json
  "hooks": {
    "SessionStart": [
      {
        "matcher": "",
        "hooks": [
          { "type": "command", "command": "bash \"${CLAUDE_PROJECT_DIR}/hooks/session_override.sh\"" },
          { "type": "command", "command": "bash \"${CLAUDE_PROJECT_DIR}/hooks/session_context.sh\"" }
        ]
      }
    ],
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          { "type": "command", "command": "python3 \"${CLAUDE_PROJECT_DIR}/hooks/telegram_approval.py\"" }
        ]
      },
      {
        "matcher": "",
        "hooks": [
          { "type": "command", "command": "bash \"${CLAUDE_PROJECT_DIR}/hooks/classify_task.sh\"" },
          { "type": "command", "command": "bash \"${CLAUDE_PROJECT_DIR}/hooks/budget_guard.sh\"" },
          { "type": "command", "command": "bash \"${CLAUDE_PROJECT_DIR}/hooks/log_tool.sh\"" }
        ]
      }
    ],
    "Stop": [
      {
        "matcher": "",
        "hooks": [
          { "type": "command", "command": "bash \"${CLAUDE_PROJECT_DIR}/hooks/on_error.sh\"" }
        ]
      }
    ]
  }
```

Keep the `budget`, `memory`, and `agents` keys unchanged. Validate: `python3 -m json.tool .claude/settings.json > /dev/null && echo OK`.

- [ ] **Step 6: Retarget the recovery test in `test_pipeline_state.sh`**

Delete the entire block starting at the comment `# Test: pre_task.sh outputs RECOVERY block when pipeline_state.json shows running` down to (but not including) the final `echo ""` — that behavior is now covered by `test_session_context.sh` Test 2.

- [ ] **Step 7: Run — all pass**

Run: `bash hooks/tests/test_session_context.sh && bash hooks/tests/test_pipeline_state.sh`
Expected: `0 failed` in both.

- [ ] **Step 8: Commit**

```bash
git add hooks/session_context.sh hooks/session_override.sh .claude/settings.json hooks/tests/
git commit -m "fix(memory): inject context via SessionStart stdout — model never saw stderr (H1)"
```

---

### Task 8: Rewrite `on_error.sh` with honest Stop semantics — fixes H4, H5 (stale files)

**Files:**
- Rewrite: `hooks/on_error.sh`
- Create: `hooks/tests/test_on_error.sh`

- [ ] **Step 1: Write the failing test**

Create `hooks/tests/test_on_error.sh`:

```bash
#!/bin/bash
# on_error.sh (Stop hook): always clears idle timestamps; when a pipeline
# is still 'running' at stop, appends ONE recovery note per run_id.
set -euo pipefail

PASS=0; FAIL=0
PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CLEANUP_DIRS=()
trap 'rm -rf "${CLEANUP_DIRS[@]:-}"' EXIT

setup_repo() {
    local tmpdir
    tmpdir=$(mktemp -d)
    CLEANUP_DIRS+=("$tmpdir")
    (
        cd "$tmpdir"
        git init -q
        git config user.email "test@test.com"
        git config user.name "Test"
        mkdir -p hooks/lib memory logs .claude/tmp
        cp "$PROJECT_ROOT/hooks/on_error.sh" hooks/
        cp "$PROJECT_ROOT/hooks/lib/common.sh" hooks/lib/
        echo "# Scratchpad" > memory/scratchpad.md
        git add . && git commit -q -m "init"
    )
    echo "$tmpdir"
}

# Test 1: idle timestamps cleared on every stop
DIR=$(setup_repo)
echo "123" > "$DIR/.claude/tmp/last_tool_coder"
(cd "$DIR" && echo '{}' | bash hooks/on_error.sh)
if [ -f "$DIR/.claude/tmp/last_tool_coder" ]; then
    echo "FAIL: idle timestamp survived stop"; FAIL=$((FAIL+1))
else
    echo "PASS: idle timestamps cleared on stop"; PASS=$((PASS+1))
fi

# Test 2: running pipeline → recovery note in scratchpad + STOP line in log
DIR=$(setup_repo)
cat > "$DIR/pipeline_state.json" <<'EOF'
{"task_id":"TASK-005","pipeline":"full","run_id":"r9","current_step":"tester","completed_steps":["researcher","coder","reviewer"],"status":"running"}
EOF
(cd "$DIR" && echo '{}' | bash hooks/on_error.sh)
if grep -q "TASK-005" "$DIR/memory/scratchpad.md" && grep -q "tester" "$DIR/memory/scratchpad.md"; then
    echo "PASS: recovery note written to scratchpad"; PASS=$((PASS+1))
else
    echo "FAIL: no recovery note in scratchpad"; FAIL=$((FAIL+1))
fi
if grep -q "pipeline_incomplete" "$DIR/logs/tool_calls.log"; then
    echo "PASS: STOP line logged"; PASS=$((PASS+1))
else
    echo "FAIL: no STOP line in tool_calls.log"; FAIL=$((FAIL+1))
fi

# Test 3: second stop for the same run does not duplicate the note
BEFORE=$(grep -c "TASK-005" "$DIR/memory/scratchpad.md")
(cd "$DIR" && echo '{}' | bash hooks/on_error.sh)
AFTER=$(grep -c "TASK-005" "$DIR/memory/scratchpad.md")
if [ "$BEFORE" = "$AFTER" ]; then
    echo "PASS: note deduped per run_id"; PASS=$((PASS+1))
else
    echo "FAIL: duplicate recovery note"; FAIL=$((FAIL+1))
fi

# Test 4: completed pipeline → no note
DIR=$(setup_repo)
cat > "$DIR/pipeline_state.json" <<'EOF'
{"task_id":"TASK-006","pipeline":"full","run_id":"r10","current_step":null,"completed_steps":["researcher"],"status":"completed"}
EOF
(cd "$DIR" && echo '{}' | bash hooks/on_error.sh)
if grep -q "TASK-006" "$DIR/memory/scratchpad.md"; then
    echo "FAIL: note written for completed pipeline"; FAIL=$((FAIL+1))
else
    echo "PASS: no note for completed pipeline"; PASS=$((PASS+1))
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
```

- [ ] **Step 2: Run to verify failures**

Run: `bash hooks/tests/test_on_error.sh`
Expected: FAILs — old script exits at `stop_reason=end_turn` before doing anything.

- [ ] **Step 3: Rewrite `hooks/on_error.sh`** (full replacement):

```bash
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
```

- [ ] **Step 4: Run — all pass**

Run: `bash hooks/tests/test_on_error.sh`
Expected: `0 failed`.

- [ ] **Step 5: Commit**

```bash
git add hooks/on_error.sh hooks/tests/test_on_error.sh
git commit -m "fix(stop-hook): drop nonexistent stop_reason; clean idle state; once-per-run recovery note (H4, H5)"
```

---

### Task 9: Bootstrap separation fixes — fixes H7, M3, L1, L2, L3

**Files:**
- Modify: `bootstrap.sh`
- Modify: `.gitignore`
- Delete: `logs/token_usage.log`, stale logs, stale worktrees

- [ ] **Step 1: `.gitignore`** — full replacement:

```gitignore
# Python
__pycache__/
*.pyc
*.pyo
.pytest_cache/

# Hook runtime files
pipeline_state.json
pipeline_state.json.tmp
.claude/tmp/

# Logs (runtime — not committed)
logs/tool_calls.log
logs/agent_calls.log
logs/pipeline.jsonl
logs/traces/*
!logs/traces/.gitkeep

# Telegram approval hook credentials (never commit these)
.env.telegram

# OS
.DS_Store

# Local issue reference (not part of the template)
ISSUES.md
```

- [ ] **Step 2: Clean dead artifacts in the template repo**

```bash
rm -f logs/token_usage.log logs/pipeline.jsonl .claude/last_session_id
git worktree prune
rm -rf .claude/worktrees
```

(`logs/pipeline.jsonl` currently holds 4 stale smoke-test records; it is runtime telemetry and now gitignored.)

- [ ] **Step 3: Edit `bootstrap.sh` — memory reset in Step 2**

In Step 2 (after the `success "  memory/core.md written."` line), add:

```bash
# Reset working-memory files so no template history leaks into the project.
# Runs BEFORE Step 3c (pool pull) so pulled org-facts are preserved.
cat > memory/facts.md <<'EOF'
# Facts

_Format: [domain] fact — YYYY-MM-DD — reviewed_at:YYYY-MM-DD — source:<agent> — task:<TASK-ID> — scope:project|team|org_
_Mark outdated entries with [stale] prefix — never delete._
EOF

cat > memory/scratchpad.md <<'EOF'
# Scratchpad

_Current working context. Written by orchestrator at task start. Cleared by memory agent after task completion._

## Current Task
none

## Working Notes
none

## Decisions Made This Session
none
EOF

cat > memory/session_checkpoint.md <<'EOF'
# Session Checkpoint

_Written by the memory agent after every task. A new Claude session reads this first._

**Last updated:** never
**Last completed task:** none

## Current State
Project just initialized. No tasks completed yet.

## Open Questions
none

## Next Task
Review and fill in CONVENTIONS.md (see TASKS.md)
EOF
success "  Reset memory files (facts, scratchpad, checkpoint)."
```

- [ ] **Step 4: Edit `bootstrap.sh` — Step 6 cleanup**

(a) Replace the log-clearing block:

```bash
# Clear operational logs — new project starts with empty logs
[[ -f "logs/tool_calls.log"  ]] && : > logs/tool_calls.log  && success "  Cleared logs/tool_calls.log."
[[ -f "logs/agent_calls.log" ]] && : > logs/agent_calls.log && success "  Cleared logs/agent_calls.log."
```

with:

```bash
# Clear operational logs — new project starts with empty logs
[[ -f "logs/tool_calls.log"   ]] && : > logs/tool_calls.log   && success "  Cleared logs/tool_calls.log."
[[ -f "logs/agent_calls.log"  ]] && : > logs/agent_calls.log  && success "  Cleared logs/agent_calls.log."
[[ -f "logs/pipeline.jsonl"   ]] && rm -f logs/pipeline.jsonl && success "  Removed logs/pipeline.jsonl (template run history)."
```

(b) Replace the hooks-tests block:

```bash
# Remove hook test that targets ClaudeTemplate's own classify_task implementation
[[ -f "hooks/tests/test_classify_task.sh" ]] && rm -f hooks/tests/test_classify_task.sh && success "  Removed hooks/tests/test_classify_task.sh."
# Remove hooks/tests dir only if now empty
[[ -d "hooks/tests" ]] && rmdir hooks/tests 2>/dev/null && success "  Removed empty hooks/tests/." || true
```

with:

```bash
# Remove ALL hook tests — they target ClaudeTemplate's own hook implementations
[[ -d "hooks/tests" ]] && rm -rf hooks/tests && success "  Removed hooks/tests/."

# Remove template CI — it references pre-bootstrap paths (hooks/tests, tests/, contracts/)
[[ -f ".github/workflows/ci.yml" ]] && rm -f .github/workflows/ci.yml && success "  Removed template CI workflow (define project CI fresh)."
rmdir .github/workflows .github 2>/dev/null || true

# Remove per-project hook runtime state
[[ -d ".claude/tmp" ]] && rm -rf .claude/tmp && success "  Removed .claude/tmp/."
```

(c) At the **end** of Step 6 (after the `__pycache__` cleanup block), add:

```bash
# Remove this one-shot script — re-running it in a live project would
# destroy git history. (Safe: bash keeps the open fd after unlink.)
rm -f bootstrap.sh && success "  Removed bootstrap.sh."
```

- [ ] **Step 5: Verify**

```bash
bash -n bootstrap.sh && echo "syntax OK"
grep -c "rm -f bootstrap.sh" bootstrap.sh        # 1
grep -c "pipeline.jsonl" .gitignore               # 1
```

Optional end-to-end check (recommended): clone the repo to `/tmp/bt-test`, run `./bootstrap.sh` with dummy answers, then confirm: `ls hooks/tests .github/workflows bootstrap.sh logs/pipeline.jsonl 2>&1` all report "No such file", and `grep -c "template" memory/facts.md` returns 0 matches for template-era facts.

- [ ] **Step 6: Commit**

```bash
git add bootstrap.sh .gitignore
git rm --cached logs/token_usage.log 2>/dev/null || true
git add -u
git commit -m "fix(bootstrap): clear pipeline log + CI + all hook tests + memory; self-delete; ignore runtime files (H7, M3, L1-L3)"
```

---

### Task 10: Analytics run-id support + missing contracts — fixes M1, M5

**Files:**
- Modify: `tools/pipeline_analytics.py`
- Modify: `tools/trace_analyze.py`
- Create: `contracts/writer.json`, `contracts/changelog.json`
- Modify: `tests/test_pipeline_analytics.py`

- [ ] **Step 1: Write the failing test**

Append to `tests/test_pipeline_analytics.py`:

```python
import json
import subprocess
import sys
from pathlib import Path

_REPO = Path(__file__).resolve().parent.parent


def _run_analytics(args):
    return subprocess.run(
        [sys.executable, str(_REPO / "tools" / "pipeline_analytics.py"), *args],
        capture_output=True, text=True, check=True,
    ).stdout


def test_run_id_filter_excludes_other_runs(tmp_path):
    log = tmp_path / "pipeline.jsonl"
    recs = [
        {"event": "agent_start", "agent": "coder", "task_id": "TASK-1", "pipeline": "full",
         "timestamp": "2026-06-09T10:00:00Z", "run_id": "run-a"},
        {"event": "agent_end", "agent": "coder", "task_id": "TASK-1", "outcome": "DONE",
         "retry": 0, "timestamp": "2026-06-09T10:05:00Z", "run_id": "run-a"},
        {"event": "agent_end", "agent": "tester", "task_id": "TASK-2", "outcome": "FAIL",
         "reason": "other run", "retry": 0, "timestamp": "2026-06-09T11:00:00Z", "run_id": "run-b"},
    ]
    log.write_text("\n".join(json.dumps(r) for r in recs) + "\n")
    out = _run_analytics(["--log", str(log), "--run-id", "run-a"])
    assert "TASK-1" in out
    assert "TASK-2" not in out


def test_runs_summary_lists_each_run(tmp_path):
    log = tmp_path / "pipeline.jsonl"
    recs = [
        {"event": "agent_start", "agent": "coder", "task_id": "TASK-1", "pipeline": "full",
         "timestamp": "2026-06-09T10:00:00Z", "run_id": "run-a"},
        {"event": "tool_call", "tool": "Bash", "agent": "coder", "task_id": "TASK-1",
         "timestamp": "2026-06-09T10:01:00Z", "run_id": "run-a"},
        {"event": "agent_end", "agent": "coder", "task_id": "TASK-1", "outcome": "DONE",
         "retry": 0, "timestamp": "2026-06-09T10:05:00Z", "run_id": "run-a"},
        {"event": "agent_start", "agent": "coder", "task_id": "TASK-2", "pipeline": "fast-track",
         "timestamp": "2026-06-09T11:00:00Z", "run_id": "run-b"},
    ]
    log.write_text("\n".join(json.dumps(r) for r in recs) + "\n")
    out = _run_analytics(["--log", str(log)])
    assert "Runs" in out
    assert "run-a" in out and "run-b" in out


def test_retry_duration_pairing_is_fifo(tmp_path):
    # Two coder passes on the same task (retry) must yield two durations,
    # paired first-start-to-first-end — not overwrite the first start.
    log = tmp_path / "pipeline.jsonl"
    recs = [
        {"event": "agent_start", "agent": "coder", "task_id": "TASK-1", "pipeline": "full",
         "timestamp": "2026-06-09T10:00:00Z", "run_id": "run-a"},
        {"event": "agent_end", "agent": "coder", "task_id": "TASK-1", "outcome": "DONE",
         "retry": 0, "timestamp": "2026-06-09T10:01:00Z", "run_id": "run-a"},
        {"event": "agent_start", "agent": "coder", "task_id": "TASK-1", "pipeline": "full",
         "timestamp": "2026-06-09T10:10:00Z", "run_id": "run-a"},
        {"event": "agent_end", "agent": "coder", "task_id": "TASK-1", "outcome": "DONE",
         "retry": 1, "timestamp": "2026-06-09T10:12:00Z", "run_id": "run-a"},
    ]
    log.write_text("\n".join(json.dumps(r) for r in recs) + "\n")
    out = _run_analytics(["--log", str(log)])
    # N=2 durations for coder; max is 120s (not 720s, which the overwrite bug produced)
    coder_line = next(l for l in out.splitlines() if l.strip().startswith("coder"))
    assert " 2" in coder_line
    assert "120.0" in coder_line
    assert "720.0" not in out
```

- [ ] **Step 2: Run to verify failures**

Run: `python3 -m pytest tests/test_pipeline_analytics.py -v`
Expected: the 3 new tests FAIL (`--run-id` unknown argument; no Runs section; 720.0 present).

- [ ] **Step 3: Implement in `tools/pipeline_analytics.py`**

(a) In `main()`, add next to the existing arguments:

```python
    parser.add_argument("--run-id", default="", help="Only include records from this pipeline run")
```

and after `records = load_records(Path(args.log))`:

```python
    if args.run_id:
        records = [r for r in records if r.get("run_id") == args.run_id]
```

(b) In `analyze()`, fix FIFO pairing. Replace:

```python
    starts: dict[tuple, datetime] = {}
```

with:

```python
    starts: dict[tuple, list[datetime]] = defaultdict(list)
```

Replace:

```python
        if event == "agent_start" and ts:
            starts[(agent, task_id)] = ts
```

with:

```python
        if event == "agent_start" and ts:
            starts[(agent, task_id)].append(ts)
```

Replace:

```python
            if ts:
                start_ts = starts.get((agent, task_id))
                if start_ts:
                    dur = (ts - start_ts).total_seconds()
                    if dur >= 0:
                        durations[agent].append(dur)
```

with:

```python
            if ts:
                pending = starts.get((agent, task_id))
                if pending:
                    start_ts = pending.pop(0)
                    dur = (ts - start_ts).total_seconds()
                    if dur >= 0:
                        durations[agent].append(dur)
```

(c) Add a per-run summary. At the top of `analyze()` (with the other accumulators), add:

```python
    runs: dict[str, dict] = {}
```

At the top of the record loop (right after `ts = parse_ts(...)`), add:

```python
        rid = r.get("run_id", "")
        if rid:
            info = runs.setdefault(rid, {"task_id": "", "pipeline": "", "tool_calls": 0, "outcome": ""})
            if task_id:
                info["task_id"] = task_id
            if event == "agent_start" and r.get("pipeline"):
                info["pipeline"] = r["pipeline"]
            elif event == "tool_call":
                info["tool_calls"] += 1
            elif event == "agent_end":
                info["outcome"] = f"{agent}:{r.get('outcome', '')}"
```

After the "Agent Outcomes" print block, add:

```python
    # Per-run summary
    if runs:
        print("Runs")
        print(f"  {'run_id':<38} {'task':<10} {'pipeline':<11} {'tools':>5}  last outcome")
        for rid, info in runs.items():
            print(f"  {rid:<38} {info['task_id']:<10} {info['pipeline']:<11} {info['tool_calls']:>5}  {info['outcome']}")
        print()
```

(d) In `tools/trace_analyze.py`, add the same `--run-id` argument next to its existing `--last` argument in `main()`, and the same two-line filter immediately after its `load_records(...)` call.

- [ ] **Step 4: Create the missing contracts**

`contracts/writer.json`:

```json
{
  "agent": "writer",
  "required_fields": ["task_id", "agent", "verdict", "payload", "next_agent", "timestamp"],
  "valid_verdicts": ["DONE"],
  "reason_required_on": []
}
```

`contracts/changelog.json`:

```json
{
  "agent": "changelog",
  "required_fields": ["task_id", "agent", "verdict", "payload", "next_agent", "timestamp"],
  "valid_verdicts": ["DONE"],
  "reason_required_on": []
}
```

- [ ] **Step 5: Run — all pass**

Run: `python3 -m pytest tests/ -v && python3 -m json.tool contracts/writer.json > /dev/null && python3 -m json.tool contracts/changelog.json > /dev/null && echo OK`
Expected: all pytest tests pass, `OK`.

- [ ] **Step 6: Commit**

```bash
git add tools/pipeline_analytics.py tools/trace_analyze.py contracts/writer.json contracts/changelog.json tests/test_pipeline_analytics.py
git commit -m "feat(analytics): --run-id filter, per-run summary, FIFO duration pairing; add writer/changelog contracts (M1, M5)"
```

---

### Task 11: Documentation sync — fixes C1 (docs), M2 (drift), and all renames

**Files:**
- Modify: `CLAUDE.md`, `.claude/orchestrator.md`, `hooks/README.md`

Apply each edit to **both** `CLAUDE.md` and `.claude/orchestrator.md` (orchestrator.md uses `.claude/hooks/...` paths — keep that prefix there):

- [ ] **Step 1: Remove the env-var protocol.** Replace step 10a:

```
    a. `export CLAUDE_TASK_ID=<task_id> CLAUDE_CURRENT_AGENT=<agent_name>` — set context for log_tool.sh
       `bash hooks/log_agent.sh <agent_name> START <task_id> <full|fast-track>`
```

with:

```
    a. `bash hooks/log_agent.sh <agent_name> START <task_id> <full|fast-track>`
       (hooks read agent/task/run context from `pipeline_state.json` — no env vars needed)
```

and in step 10f delete the line `` `unset CLAUDE_TASK_ID CLAUDE_CURRENT_AGENT` ``. (orchestrator.md's step 10 wording is shorter — apply the equivalent: ensure no `export CLAUDE_TASK_ID`/`unset` instructions remain; `grep -n "CLAUDE_TASK_ID" .claude/orchestrator.md` must return nothing.)

- [ ] **Step 2: Fix the task_mode path.** Replace `/tmp/task_mode` with `.claude/tmp/task_mode` everywhere: `grep -rn "/tmp/task_mode" CLAUDE.md .claude/orchestrator.md hooks/README.md` must return nothing afterwards.

- [ ] **Step 3: Update the Hooks section.** Replace the hooks JSON example with the new `settings.json` hooks object from Task 7 Step 5 (in orchestrator.md, with `.claude/hooks/` paths). Replace the hook table rows:

| Hook | Purpose |
|---|---|
| `session_override.sh` | SessionStart — prints the Phase 0 skill-override banner into model context |
| `session_context.sh` | SessionStart — injects `core.md`, `session_checkpoint.md`, `scratchpad.md`, and the pipeline recovery hint into model context (stdout) |
| `classify_task.sh` | Classify task complexity; write `FORCE_FULL` or `AMBIGUOUS` to `.claude/tmp/task_mode` |
| `budget_guard.sh` | Enforce daily call limit, per-agent budgets from `contracts/pipeline-slos.md`, pipeline wall-clock SLOs, and idle timeouts. `CLAUDE_BUDGET_MODE=halt` blocks the tool call (hook exit 2) |
| `log_tool.sh` | Append each tool call to `logs/tool_calls.log` (PreToolUse only) and a structured `tool_call` event to `logs/pipeline.jsonl` when a pipeline run is active |
| `on_error.sh` | Stop event — clears idle state; if a pipeline run is still `running`, logs it and appends one recovery note per run to `memory/scratchpad.md` |

Remove the `pre_task.sh` and `post_task.sh` rows entirely.

- [ ] **Step 4: Update Golden Rule 11.** Replace the sentence `Set `CLAUDE_CURRENT_AGENT` before dispatching each agent so the guard can apply per-agent limits.` with `Per-agent limits are applied automatically — hooks read the active agent from `pipeline_state.json`.`

- [ ] **Step 5: Update `hooks/README.md`:**
  - Execution Model: replace the events table rows with: `SessionStart → session_override.sh, session_context.sh`; `PreToolUse (Bash only) → telegram_approval.py`; `PreToolUse (all tools) → classify_task.sh, budget_guard.sh, log_tool.sh`; `Stop → on_error.sh`. Delete the PostToolUse row.
  - Replace the sentence `Output to stderr is surfaced in the Claude Code UI; stdout is discarded.` with: `Stderr is shown to the user only. SessionStart stdout is injected into the model's context. A PreToolUse hook blocks the tool call only by exiting 2 (stderr is then fed to the model).`
  - Replace the `pre_task.sh` section with a `session_context.sh` section (event: SessionStart; prints core.md/checkpoint/scratchpad and the pipeline recovery hint to stdout).
  - Delete the `post_task.sh` section.
  - Rewrite the `budget_guard.sh`, `log_tool.sh`, and `on_error.sh` sections to match the Task 3/4/8 behavior (limits from `contracts/pipeline-slos.md`; halt = exit 2; per-run agent counts from `pipeline.jsonl`; PreToolUse-only flat logging; Stop semantics).
  - Add `CLAUDE_IDLE_TIMEOUT_MINUTES | 10 | minutes without a tool call before the idle alarm` to the Configuration table; in the Logs table remove `post_task.sh` and add `logs/pipeline.jsonl | log_tool.sh, log_agent.sh, validate_output.sh, classify_task.sh | structured run trace (run_id on every event)`.

- [ ] **Step 6: Verify and commit**

```bash
grep -rn "CLAUDE_TASK_ID\|unset CLAUDE_CURRENT_AGENT\|/tmp/task_mode\|pre_task\|post_task" CLAUDE.md .claude/orchestrator.md hooks/README.md
# Expected: no matches
git add CLAUDE.md .claude/orchestrator.md hooks/README.md
git commit -m "docs: sync CLAUDE.md/orchestrator.md/hooks README with state-file context protocol (C1, M2)"
```

---

### Task 12: `pipeline_init` event — a run's trace includes its own classification (fixes #8)

**Context (read before coding):** the classifier hook fires on the PreToolUse of the very Bash call that runs `init_pipeline_state.sh`, i.e. before `pipeline_state.json` exists — so the verdict that decided this run's pipeline is logged without a `run_id` and falls outside `--run-id` filtering. The fix: `init_pipeline_state.sh` emits one run-scoped `pipeline_init` event at run birth, capturing the verdict it was launched under (read from `.claude/tmp/task_mode`) plus the orchestrator's decision reason.

**Rejected alternative — do NOT implement:** minting a "pending run_id" from `current_run_id()` in `hooks/lib/common.sh` when no state file exists. That puts a write side-effect in a read path called on every tool call, smears ambient pre-run events (possibly hours of unrelated work) into the next run's trace, and creates a stale-file lifecycle nobody owns. The `pipeline_init` event scopes correctly by construction.

This also strengthens the issue-5 fix (PR #73, mandatory pipeline-decision logging): the decision reason now lands in the structured trace, not only as a flat log line.

**Files:**
- Modify: `hooks/init_pipeline_state.sh`
- Modify: `tools/pipeline_analytics.py`
- Modify: `CLAUDE.md`, `.claude/orchestrator.md`
- Test: `hooks/tests/test_pipeline_state.sh`, `tests/test_pipeline_analytics.py`

- [ ] **Step 1: Write the failing hook tests**

Append to `hooks/tests/test_pipeline_state.sh` before the results footer:

```bash
# Test: init emits a run-scoped pipeline_init event with the classifier verdict
DIR=$(setup_repo)
mkdir -p "$DIR/.claude/tmp"
echo "AMBIGUOUS" > "$DIR/.claude/tmp/task_mode"
(cd "$DIR" && bash hooks/init_pipeline_state.sh TASK-007 fast-track "doc-only change, no shared logic")
RUN_ID=$(python3 -c "import json; print(json.load(open('$DIR/pipeline_state.json'))['run_id'])")
LAST=$(tail -1 "$DIR/logs/pipeline.jsonl" 2>/dev/null || echo "{}")
for check in \
    "event=pipeline_init" \
    "task_id=TASK-007" \
    "pipeline=fast-track" \
    "classifier_verdict=AMBIGUOUS" \
    "decision_reason=doc-only change, no shared logic" \
    "run_id=$RUN_ID"; do
    field="${check%%=*}"; expected="${check#*=}"
    actual=$(echo "$LAST" | python3 -c "import json,sys; print(json.load(sys.stdin).get('$field',''))")
    if [ "$actual" = "$expected" ]; then
        echo "PASS: pipeline_init $field"; PASS=$((PASS+1))
    else
        echo "FAIL: pipeline_init $field — expected '$expected', got '$actual'"; FAIL=$((FAIL+1))
    fi
done

# Test: no task_mode file → verdict UNKNOWN; no reason arg → null
DIR=$(setup_repo)
(cd "$DIR" && bash hooks/init_pipeline_state.sh TASK-008 full)
LAST=$(tail -1 "$DIR/logs/pipeline.jsonl" 2>/dev/null || echo "{}")
V=$(echo "$LAST" | python3 -c "import json,sys; print(json.load(sys.stdin).get('classifier_verdict',''))")
R=$(echo "$LAST" | python3 -c "import json,sys; print(json.load(sys.stdin).get('decision_reason'))")
if [ "$V" = "UNKNOWN" ] && [ "$R" = "None" ]; then
    echo "PASS: pipeline_init defaults (UNKNOWN verdict, null reason)"; PASS=$((PASS+1))
else
    echo "FAIL: pipeline_init defaults — verdict '$V', reason '$R'"; FAIL=$((FAIL+1))
fi
```

- [ ] **Step 2: Write the failing analytics test**

Append to `tests/test_pipeline_analytics.py` (the `_run_analytics` helper already exists there from Task 10):

```python
def test_pipeline_init_included_in_run_filter(tmp_path):
    log = tmp_path / "pipeline.jsonl"
    recs = [
        {"event": "pipeline_init", "task_id": "TASK-9", "pipeline": "fast-track",
         "classifier_verdict": "AMBIGUOUS", "decision_reason": "doc-only",
         "run_id": "run-z", "timestamp": "2026-06-11T08:00:00Z"},
        {"event": "agent_end", "agent": "coder", "task_id": "TASK-9", "outcome": "DONE",
         "retry": 0, "timestamp": "2026-06-11T08:05:00Z", "run_id": "run-z"},
    ]
    log.write_text("\n".join(json.dumps(r) for r in recs) + "\n")
    out = _run_analytics(["--log", str(log), "--run-id", "run-z"])
    assert "fast-track" in out   # pipeline known without any agent_start event
    assert "AMBIGUOUS" in out    # verdict visible in the Runs table
```

- [ ] **Step 3: Run both to verify they fail**

Run: `bash hooks/tests/test_pipeline_state.sh; python3 -m pytest tests/test_pipeline_analytics.py -v`
Expected: the new hook asserts FAIL (no `pipeline.jsonl` written by init, or last event isn't `pipeline_init`); the new pytest FAILs (`fast-track`/`AMBIGUOUS` absent).

- [ ] **Step 4: Implement in `hooks/init_pipeline_state.sh`**

(a) Update the header comment:

```bash
# Usage: bash hooks/init_pipeline_state.sh <task_id> <pipeline> ["<decision_reason>"]
# pipeline: full | fast-track
# decision_reason: optional one-line orchestrator reasoning for the pipeline
#                  choice (expected practice for AMBIGUOUS classifications)
```

(b) After `PIPELINE="${2:-}"` add:

```bash
DECISION_REASON="${3:-}"
```

(c) After the `source .../lib/common.sh` line add (CLAUDE_TMP_DIR exists only after the source):

```bash
export INIT_REASON="$DECISION_REASON"
export INIT_VERDICT
INIT_VERDICT=$(cat "$CLAUDE_TMP_DIR/task_mode" 2>/dev/null || echo "UNKNOWN")
```

(d) In the Python heredoc, after the `os.replace(tmp, state_file)` line, add:

```python
log_dir = os.path.join(os.path.dirname(state_file), "logs")
os.makedirs(log_dir, exist_ok=True)
event = {
    "event": "pipeline_init",
    "task_id": state["task_id"],
    "pipeline": state["pipeline"],
    "run_id": state["run_id"],
    "classifier_verdict": os.environ.get("INIT_VERDICT", "UNKNOWN"),
    "decision_reason": os.environ.get("INIT_REASON") or None,
    "timestamp": state["started_at"],
}
with open(os.path.join(log_dir, "pipeline.jsonl"), "a") as f:
    f.write(json.dumps(event) + "\n")
```

- [ ] **Step 5: Implement in `tools/pipeline_analytics.py`**

In the per-run accumulation inside `analyze()`, replace:

```python
            info = runs.setdefault(rid, {"task_id": "", "pipeline": "", "tool_calls": 0, "outcome": ""})
```

with:

```python
            info = runs.setdefault(rid, {"task_id": "", "pipeline": "", "verdict": "", "tool_calls": 0, "outcome": ""})
```

and replace:

```python
            if event == "agent_start" and r.get("pipeline"):
                info["pipeline"] = r["pipeline"]
```

with:

```python
            if event in ("agent_start", "pipeline_init") and r.get("pipeline"):
                info["pipeline"] = r["pipeline"]
            if event == "pipeline_init":
                info["verdict"] = r.get("classifier_verdict", "")
```

In the Runs print block, replace:

```python
        print(f"  {'run_id':<38} {'task':<10} {'pipeline':<11} {'tools':>5}  last outcome")
        for rid, info in runs.items():
            print(f"  {rid:<38} {info['task_id']:<10} {info['pipeline']:<11} {info['tool_calls']:>5}  {info['outcome']}")
```

with:

```python
        print(f"  {'run_id':<38} {'task':<10} {'pipeline':<11} {'verdict':<10} {'tools':>5}  last outcome")
        for rid, info in runs.items():
            print(f"  {rid:<38} {info['task_id']:<10} {info['pipeline']:<11} {info['verdict']:<10} {info['tool_calls']:>5}  {info['outcome']}")
```

- [ ] **Step 6: Run the tests — all pass**

Run: `bash hooks/tests/test_pipeline_state.sh && python3 -m pytest tests/test_pipeline_analytics.py -v`
Expected: `0 failed` / all pytest pass.

- [ ] **Step 7: Update the docs**

In `CLAUDE.md` (and `.claude/orchestrator.md` with its `.claude/hooks/` path prefix):

- Update the step-9 usage line to: `` `bash hooks/init_pipeline_state.sh <task_id> <full|fast-track> ["<decision reason>"]` ``
- In the step-7 **AMBIGUOUS** bullet, append after "Log the decision either way": `Pass the one-line reason as the third argument to init_pipeline_state.sh in step 9 — it lands in the run trace as the pipeline_init event's decision_reason.` (orchestrator.md keeps its mandatory `ORCHESTRATOR | PIPELINE:... | REASON:...` flat-log line from PR #73; the init argument is the structured copy of the same reason, not a replacement.)

Verify: `grep -n "decision reason" CLAUDE.md .claude/orchestrator.md` returns one step-9 match in each file.

- [ ] **Step 8: Commit**

```bash
git add hooks/init_pipeline_state.sh tools/pipeline_analytics.py hooks/tests/test_pipeline_state.sh tests/test_pipeline_analytics.py CLAUDE.md .claude/orchestrator.md
git commit -m "feat(trace): emit run-scoped pipeline_init event with classifier verdict and decision reason (issue 8)"
```

---

### Final verification (run after Task 12)

```bash
for t in hooks/tests/test_*.sh; do echo "== $t"; bash "$t" || exit 1; done
python3 -m pytest tests/ -v
bash -n bootstrap.sh

# End-to-end smoke of the run trace:
bash hooks/init_pipeline_state.sh TASK-999 fast-track "smoke test"
tail -1 logs/pipeline.jsonl | grep -q '"event": "pipeline_init"' && echo "pipeline_init OK"
echo '{"tool_name":"Bash","hook_event_name":"PreToolUse"}' | bash hooks/log_tool.sh
echo '{"task_id":"TASK-999","agent":"coder","verdict":"DONE","payload":{},"next_agent":"tester","timestamp":"2026-06-10T12:00:00Z"}' | bash hooks/validate_output.sh coder
RUN=$(python3 -c "import json; print(json.load(open('pipeline_state.json'))['run_id'])")
python3 tools/pipeline_analytics.py --run-id "$RUN"     # must show the run, the tool_call, the envelope
bash hooks/advance_pipeline_state.sh coder done
rm -f pipeline_state.json && git checkout -- logs/ 2>/dev/null; rm -f logs/pipeline.jsonl
```

Then merge: open a PR from `fix/pipeline-audit` to `master` (CI runs all of the above).

---

## Part 2B — Real-Environment Verification (mandatory before merge)

> **Why this section exists:** Every critical bug in this plan (C1, C2b, H1) was missed by a previous round of verification that only ran hooks directly from shell scripts. Unit tests prove hook logic is correct in isolation. They cannot prove hooks work correctly when Claude Code invokes them as subprocesses, because they bypass the actual delivery mechanism. This section cannot be skipped or substituted with unit test results.

---

### Step 1 — Bootstrap a demo project

Clone the template into a throwaway directory and run `bootstrap.sh`:

```bash
cd /tmp
git clone https://github.com/sharmavipin1608/ClaudeTemplate demo-audit-verify
cd demo-audit-verify
./bootstrap.sh
```

Answer the prompts:
- Project name: `audit-verify`
- Stack: `Node.js`
- Description: `Verification project for pipeline-audit-fixes plan`
- Owner email: any
- GitHub repo: `n` (skip)

**Expected after bootstrap:**
- `bootstrap.sh` is gone (self-deleted)
- `hooks/`, `agents/`, `skills/`, `tools/`, `contracts/` are gone from root — moved to `.claude/`
- `CLAUDE.md` is ~13 lines (project identity + `@.claude/orchestrator.md`)
- `memory/facts.md` contains no template-era facts
- `logs/pipeline.jsonl` does not exist
- `.claude/tmp/` exists and is empty
- `pipeline_state.json` does not exist

Verify: `ls hooks agents skills tools contracts bootstrap.sh 2>&1` — should all say "No such file".

---

### Step 2 — Open Claude Code and verify SessionStart context injection (fixes H1)

Open Claude Code in `/tmp/demo-audit-verify`. In the very first message Claude receives, check whether project context appears — the session_context.sh hook should have injected core.md into the model context via SessionStart stdout.

**Verification:** Ask Claude: "What project are you working on and what is the stack?"

**Pass:** Claude answers "audit-verify" and "Node.js" without being told — it received core.md via the SessionStart hook.

**Fail:** Claude says it doesn't know — session_context.sh is still writing to stderr, or the hook is not registered correctly.

Do not proceed to Step 3 if this fails.

---

### Step 3 — Run one minimal task through the pipeline and verify tool_call attribution (fixes C1)

Add a minimal task to `TASKS.md`:

```markdown
### [TASK-V01] Add a hello-world function
**Status:** pending
**Priority:** high
**Agent:** coder
**Tags:** [core]
**Acceptance Criteria:**
- Given a call to helloWorld(), it returns the string "hello world"
```

Run the fast-track pipeline for this task (Coder → Tester → Security → Git → Memory). Allow it to complete or get to at least the Coder step.

After the Coder agent has made at least 3 tool calls, open `logs/pipeline.jsonl` and run:

```bash
python3 -c "
import json
lines = [json.loads(l) for l in open('logs/pipeline.jsonl') if l.strip()]
tool_calls = [r for r in lines if r.get('event') == 'tool_call']
print(f'Total tool_call events: {len(tool_calls)}')
for r in tool_calls[:3]:
    print(f'  agent={r.get(\"agent\",\"MISSING\")}  run_id={r.get(\"run_id\",\"MISSING\")}  tool={r.get(\"tool\",\"?\")}')
"
```

**Pass:** `agent` is `coder` (not empty string `""`), `run_id` is a UUID (not `"MISSING"`), `total tool_call events` is > 0.

**Fail:** `agent` is `""` or absent — C1 is not fixed. `run_id` is `"MISSING"` — `pipeline_state.json` is not being read by the hook. `total tool_call events` is 0 — `log_tool.sh` is not firing or the pipeline is not active.

---

### Step 4 — Verify budget_guard actually blocks (fixes C2b)

In `.claude/settings.json`, temporarily set:

```json
"pipeline": {
  "auto_push": false,
  "_note": "..."
}
```

and in the environment set `CLAUDE_BUDGET_MODE=halt CLAUDE_DAILY_CALL_LIMIT=5`.

Start a new task and let it make tool calls. After the 5th tool call, Claude Code must stop and show a block message — the tool call must not execute.

**Pass:** Claude Code shows the budget_guard output and the tool call is blocked. The model receives the block reason in context.

**Fail:** Pipeline continues past 5 calls — budget_guard is exiting 1 (non-blocking) instead of 2. C2b is not fixed.

Reset `CLAUDE_DAILY_CALL_LIMIT` after this test.

---

### Step 5 — Verify worktree logging stays in the main repo (fixes C3)

While a pipeline run is active, open a terminal and manually invoke a hook from inside the worktree Claude Code creates:

```bash
cd /tmp/demo-audit-verify
# Find the active worktree (if any)
git worktree list

# From inside a worktree (or simulate it):
WORKTREE=$(git worktree list | awk 'NR==2{print $1}')
if [ -n "$WORKTREE" ]; then
  cd "$WORKTREE"
  echo '{"tool_name":"Bash","hook_event_name":"PreToolUse"}' | bash .claude/hooks/log_tool.sh
  cd /tmp/demo-audit-verify
fi
```

Check:
```bash
# Main repo's log should have grown
wc -l logs/pipeline.jsonl

# Worktree must NOT have its own log
ls "$WORKTREE/logs/pipeline.jsonl" 2>&1   # expected: No such file
```

**Pass:** The main repo's `pipeline.jsonl` grew. No `pipeline.jsonl` exists inside the worktree.

**Fail:** The worktree got its own `pipeline.jsonl` — `common.sh` is not resolving the main root correctly, or is not sourced by that hook.

---

### Step 6 — Verify classifier uses per-project tmp (fixes H2)

With the demo project open in Claude Code, check that the task_mode verdict file goes to `.claude/tmp/`, not `/tmp/`:

```bash
ls /tmp/task_mode 2>&1          # expected: No such file
ls .claude/tmp/task_mode 2>&1   # expected: exists after any tool call
```

**Pass:** `.claude/tmp/task_mode` exists, `/tmp/task_mode` does not.

**Fail:** `/tmp/task_mode` exists — `classify_task.sh` still writes to the global `/tmp/`, breaking fast-track in multi-project environments and triggering FORCE_FULL from `.claude/worktrees/` untracked files.

---

### Step 7 — Verify session recovery after interruption (fixes H1, H4)

While a task is in progress (TASK-V01 in `in_progress` state), kill the Claude Code session (Ctrl+C or close the window). Reopen Claude Code in the same directory.

**Verification:** In the first message of the new session, does Claude know that TASK-V01 was interrupted and at which step to resume?

**Pass:** Claude references TASK-V01 and the pipeline step without being told — `session_context.sh` injected the recovery hint from `pipeline_state.json` via SessionStart stdout.

**Fail:** Claude starts fresh with no awareness of the interrupted run — context injection is still broken.

---

### Pass criteria summary

All 7 steps must pass before opening the PR. Record the actual output for each step as a comment on the PR — not a summary, the raw output.

| Step | What it proves | Critical bug fixed |
|---|---|---|
| 1 | Bootstrap produces a clean project with no template bleed | H7, L1, L2 |
| 2 | Model receives SessionStart context | H1 |
| 3 | `tool_call` events have non-empty `agent` and `run_id` | C1 |
| 4 | `BUDGET_MODE=halt` actually blocks tool calls | C2b |
| 5 | Worktree hooks write to main repo logs | C3 |
| 6 | Classifier writes to `.claude/tmp/` not `/tmp/` | H2, H5 |
| 7 | Session recovery hint reaches the model after interruption | H1, H4 |

**If any step fails:** stop, fix the root cause, re-run the step, and only then continue to the next step. Do not proceed to PR with a failing step and note it as "known issue."

---

## Part 3 — Deferred (needs design, do NOT improvise)

**H3 — Code-quality evaluation harness (pipeline vs. plain prompt).** Requires its own brainstorm/spec: a benchmark task set, an A/B runner (same task through the pipeline and through a single prompt), and a scoring rubric (tests-pass rate, reviewer-rubric LLM judge, cost and wall-clock from `pipeline.jsonl`). Do not bolt a quick script onto this plan.

**M2 (structural) — Single source of truth for orchestrator docs.** The real fix is restructuring the template repo itself to the `.claude/` layout so `bootstrap.sh` stops moving directories and rewriting paths, leaving exactly one `orchestrator.md`. That changes every path in the repo and the CI workflow — separate spec.

**Attribution caveat (accepted).** Orchestrator tool calls made while a pipeline run is active are attributed to `pipeline_state.json`'s pending agent. If this proves noisy in analytics, a future change can have `log_agent.sh START/END` toggle an `agent_active: true|false` flag in the state file and attribute to `orchestrator` when false.
