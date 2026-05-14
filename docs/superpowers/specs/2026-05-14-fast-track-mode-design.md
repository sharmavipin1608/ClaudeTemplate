# Fast-Track Mode Design

**Date:** 2026-05-14
**Status:** Approved
**Branch:** feature/fast-track-mode

---

## Overview

Fast-track mode reduces token cost and pipeline overhead for low-complexity tasks by routing them through a shortened agent pipeline. A bash classifier script enforces hard rules deterministically; the orchestrator handles ambiguous edge cases inline with no extra LLM call.

---

## Pipeline Variants

### Full Pipeline (default)
```
Researcher → Coder → Reviewer → Tester → Security → Git → Memory
```

### Fast-Track Pipeline
```
Coder → Tester → Security → Git → Memory
```

**Skipped agents:** Researcher (domain already known), Reviewer (scope too small to warrant design review)

**Never skippable:** Security (hard gate), Memory (system coherence)

---

## Architecture

```
Task dispatch starts
        │
        ▼
classify_task.sh  (PreToolUse hook)
        │
        ├─ Hard rule matched? ──► verdict: FORCE_FULL
        │
        └─ No match ──────────► verdict: AMBIGUOUS
        │
        ▼
Orchestrator reads /tmp/task_mode
        │
        ├─ FORCE_FULL ──► Full pipeline (log which rule fired)
        │
        └─ AMBIGUOUS ──► Orchestrator reasons inline (~200 tokens)
                                │
                                ├─ Judges complex ──► Full pipeline (log reason)
                                └─ Judges simple ──► Fast-track (log reason)
```

---

## Component 1: `hooks/classify_task.sh`

Runs as a PreToolUse hook before orchestrator dispatch. Checks changed file paths and git status — never reads file contents.

Writes verdict to `/tmp/task_mode`: either `FORCE_FULL` or `AMBIGUOUS`.
Logs which rule fired (if any) to `logs/tool_calls.log`.

### Hard Rules — any match triggers FORCE_FULL

**File path patterns (against changed files):**
```
auth|jwt|session|password|secret|token|oauth
payment|billing|stripe|invoice|pricing
migration|schema\.|flyway|liquibase
Dockerfile|docker-compose|\.github/workflows
hooks/
CLAUDE\.md|AGENTS\.md
```

**Structural signals (from git status):**
- Any file deleted (`D` in git status)
- Changed file count > 5 (configurable via `FAST_TRACK_FILE_LIMIT` env var, default: 5)
- Any new file created (`??` in git status)

**Dependency signals (diff of manifest files):**
- New lines added to `package.json`, `requirements.txt`, `go.mod`, or `pom.xml`
- Major version bump (`X.y.z → X+1.y.z`) in any manifest

**Sensitive domain keywords (in task description):**
```
pii|gdpr|privacy|user.?data|email.?template
interface|abstract|base.*class
```

---

## Component 2: Orchestrator Routing (CLAUDE.md)

New "Complexity Classification" step inserted between "read memory" and "dispatch agent":

```
4. READ /tmp/task_mode

   IF FORCE_FULL:
     → Log: "Full pipeline: [rule that fired]" to logs/tool_calls.log
     → Dispatch full pipeline

   IF AMBIGUOUS:
     → Reason: does this task introduce new behavior, touch shared logic,
       or carry risk not caught by pattern rules?
     → IF yes → full pipeline (log reason)
     → IF no  → fast-track (log reason)
```

### New Golden Rule (Rule #8)
> **Classification is a gate, not a suggestion** — if `classify_task.sh` returns FORCE_FULL, the orchestrator does not override it.

---

## Component 3: AGENTS.md Updates

Add pipeline variants table and update dispatch rules:

**Routing reference:**

| Verdict | Triggered by | Pipeline |
|---|---|---|
| `FORCE_FULL` | Hard rule match in `classify_task.sh` | Full |
| `AMBIGUOUS → complex` | Orchestrator inline judgment | Full |
| `AMBIGUOUS → simple` | Orchestrator inline judgment | Fast-track |

**New dispatch rule (Rule #6):**
> Log the pipeline variant and reason for every task — format: `timestamp | ORCHESTRATOR | PIPELINE:full | REASON:auth file touched`

---

## Component 4: `.claude/settings.json`

Register `classify_task.sh` in the PreToolUse hooks array alongside existing hooks:

```json
{
  "hooks": {
    "PreToolUse": [
      { "command": "bash hooks/pre_task.sh" },
      { "command": "bash hooks/classify_task.sh" },
      { "command": "bash hooks/log_tool.sh $TOOL_NAME $AGENT_NAME" },
      { "command": "bash hooks/budget_guard.sh" }
    ]
  }
}
```

`classify_task.sh` runs after `pre_task.sh` (which loads task context) so the task description is available when classification runs.

---

## Token Cost Profile

| Case | Extra tokens |
|---|---|
| Hard rule fires (FORCE_FULL) | 0 — bash only |
| Clean ambiguous → fast-track | ~200 — added to existing orchestrator call |
| Ambiguous → escalates to full | ~200 — same |

No separate classification LLM call is ever made.

---

## Audit Trail

Every task logs its routing decision:
```
2026-05-14T10:23:01Z | ORCHESTRATOR | PIPELINE:fast-track | REASON:small config change, no patterns matched
2026-05-14T10:45:12Z | ORCHESTRATOR | PIPELINE:full | REASON:auth file touched
```

Review weekly to tune classifier sensitivity.

---

## Files Changed

| File | Change |
|---|---|
| `hooks/classify_task.sh` | New — hard-rule classifier |
| `.claude/settings.json` | Register new hook in PreToolUse |
| `CLAUDE.md` | Add routing step + golden rule #8 |
| `AGENTS.md` | Add pipeline variants, routing table, dispatch rule #6 |
