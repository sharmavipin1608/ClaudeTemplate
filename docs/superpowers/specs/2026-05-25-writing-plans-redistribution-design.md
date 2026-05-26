# Writing-Plans Responsibility Redistribution — Design Spec

**Date:** 2026-05-25
**Status:** Approved

---

## Problem

The `superpowers:writing-plans` plugin skill currently does too much. It writes actual test code, actual implementation code, and performs spec coverage and type consistency reviews. This pre-computes work that belongs to the Coder, Tester, and Reviewer agents — making the plan code stale before implementation begins and reducing agents to copy-paste workers rather than reasoning agents.

## Goal

Redistribute responsibilities so `writing-plans` produces **task contracts** (intent + acceptance criteria + file map, no code), and each agent owns the work appropriate to its role.

---

## Scope

### Files Changed

| File | Action | Reason |
|---|---|---|
| `skills/writing-plans.md` | Create | Project-level override of the plugin skill — thinned to produce task contracts |
| `CLAUDE.md` | Update | Phase 0 Step 2 references project file instead of invoking plugin |
| `TASKS.md` | Update | Format section adds `Files` and `Acceptance Criteria` fields |
| `agents/writer.md` | Update | Transcribes acceptance criteria and files into TASKS.md entries |
| `agents/coder.md` | Update | Explicitly derives implementation from acceptance criteria, not plan code |
| `agents/tester.md` | Update | Uses acceptance criteria as test specification source |
| `agents/reviewer.md` | Update | Absorbs spec coverage check and type consistency check |

### Not Changed

- Superpowers plugin skill files (untouched)
- `agents/researcher.md`, `agents/security.md`, `agents/git.md`, `agents/devops.md`, `agents/memory.md`, `agents/changelog.md`
- All hook scripts
- `skills/coding-patterns.md`, `skills/api-design.md`, `skills/test-strategy.md`, `skills/security-rules.md`, `skills/git-commit.md`

---

## Design

### 1. `skills/writing-plans.md` — Thinned Project Override

Copied from `superpowers:writing-plans` plugin SKILL.md and stripped of:
- Bite-sized TDD step structure (write failing test → run → implement → run → commit)
- Actual code blocks in task steps
- Self-review of type consistency (moves to Reviewer)
- Self-review of spec coverage (moves to Reviewer)

Retains:
- Plan document header format (Goal, Architecture, Tech Stack)
- File structure mapping section (which files, one responsibility each)
- Scope check (flag multi-subsystem specs)
- No-placeholders rule (applies to intent and criteria, not code)
- Execution handoff section (subagent-driven vs inline options)

**New task structure per plan — task contracts:**

```markdown
### Task N: [Component Name]

**Intent:** One sentence — what this builds and why.

**Files:**
- Create: `exact/path/to/file.py`
- Modify: `exact/path/to/existing.py`
- Test: `tests/exact/path/to/test.py`

**Acceptance Criteria:**
- [ ] Given X, when Y, then Z
- [ ] Edge case: when A, system does B
- [ ] Error case: when C, returns D

**Depends on:** Task N-1 (if applicable)
**Agent:** coder | researcher | writer
```

No code blocks. No TDD step sequences. Each criterion is a testable statement of expected behavior.

### 2. `CLAUDE.md` — Phase 0 Step 2 Update

**Current:**
> "Invoke the **writing-plans** skill — read the approved spec, produce the implementation plan..."

**New:**
> "Read and follow `skills/writing-plans.md` — read the approved spec, produce the implementation plan to `docs/superpowers/plans/YYYY-MM-DD-<feature-name>.md`, wait for user approval"

This routes the orchestrator to the project-level file instead of triggering `superpowers:writing-plans` via the Skill tool.

### 3. `TASKS.md` — Richer Format

Two fields added to the task format: `Files` and `Acceptance Criteria`. The Writer agent populates these from the plan contract. This makes TASKS.md the single source of truth each agent works from — no agent needs to re-read the plan doc.

**Updated format:**

```
### [TASK-NNN] Task Title
**Status:** pending | in_progress | completed | blocked | failed
**Priority:** high | medium | low
**Agent:** researcher | coder | tester | etc.
**Tags:** [domain] tags matching facts.md
**Depends on:** TASK-NNN (if any)
**Files:** `path/to/file.py`, `tests/path/to/test.py`
**Acceptance Criteria:**
- Given X, when Y, then Z
- Edge case: when A, system does B

One sentence description of what needs to be done and why.
```

### 4. `agents/writer.md` — Richer TASKS.md Population

When triggered for plan sign-off (Trigger 1), the Writer now transcribes `Files` and `Acceptance Criteria` from each plan task contract directly into the TASKS.md entry. No inference — straight transcription from the plan.

The one-sentence description in TASKS.md is derived from the task's `**Intent:**` field in the plan.

### 5. `agents/coder.md` — Explicit Acceptance Criteria Source

Add one rule:

> "Derive what to implement from the task's `Acceptance Criteria` in your task entry. Do not expect pre-written implementation code. Your TDD cycle is: read a criterion → write a failing test for it → implement minimal code to pass → move to the next criterion."

This makes the acceptance criteria the driver of the TDD cycle, replacing the plan's pre-written test stubs.

### 6. `agents/tester.md` — Acceptance Criteria as Test Spec

Add one rule:

> "Use the task's `Acceptance Criteria` as your test specification. Each criterion must map to at least one integration or edge case test. Criteria not covered by the coder's unit tests are your primary target."

### 7. `agents/reviewer.md` — Absorb Two Checks

Add two responsibilities to the Reviewer's review scope:

**Spec coverage check:** For each acceptance criterion in the task entry, verify the implementation satisfies it. Flag any criterion with no corresponding code path as a required change.

**Type consistency check:** Scan the diff for inconsistent names — function names, method names, type names referenced across multiple files. Flag any mismatch (e.g., `clearLayers()` in one file vs `clearFullLayers()` in another) as a required change.

Both produce entries in the existing `REQUIRED CHANGES` block. No new output format needed.

---

## Responsibility Map (Before vs After)

| Responsibility | Before | After |
|---|---|---|
| File structure mapping | writing-plans | writing-plans (kept) |
| Test code for each task | writing-plans | Coder (TDD from criteria) |
| Implementation code for each task | writing-plans | Coder |
| Acceptance criteria | writing-plans (implicit in test code) | writing-plans (explicit), TASKS.md |
| Spec coverage check | writing-plans (self-review) | Reviewer |
| Type consistency check | writing-plans (self-review) | Reviewer |
| TASKS.md population | Writer (title + description only) | Writer (+ files + acceptance criteria) |

---

## Constraints

- The `superpowers:writing-plans` plugin is not modified — it stays as-is for other projects
- TASKS.md existing entries (completed, in_progress) are never overwritten by the Writer
- The Reviewer's new checks use the same REQUIRED CHANGES output format — no pipeline changes needed to handle them
- The Coder's TDD cycle is unchanged in structure — only the source of what to test changes (criteria instead of pre-written stubs)

---

## Out of Scope

- Changing how agents are dispatched or sequenced in the pipeline
- Modifying the Researcher, Security, Git, DevOps, or Memory agents
- Changing the brainstorming → writing-plans handoff
- Any changes to hooks or settings.json
