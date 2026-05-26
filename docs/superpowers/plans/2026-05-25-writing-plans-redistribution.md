# Writing-Plans Responsibility Redistribution — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Redistribute responsibilities from the `writing-plans` plugin skill into the appropriate project-level agent files so each agent owns the work it is built for.

**Architecture:** Create a project-level `skills/writing-plans.md` that overrides the plugin by producing thin task contracts (intent + acceptance criteria + file map, no code). Update `CLAUDE.md` to reference the project file instead of the plugin. Enrich `TASKS.md` format and agent files so acceptance criteria flow from plan → TASKS.md → each agent as the source of truth for implementation and review.

**Tech Stack:** Markdown files only — no code, no test runner. Verification is manual file inspection after each edit.

---

## File Map

| File | Action | Responsibility |
|---|---|---|
| `skills/writing-plans.md` | Create | Project-level plan skill — produces task contracts, no code |
| `CLAUDE.md` | Modify | Phase 0 Step 2 — reference project file instead of plugin |
| `TASKS.md` | Modify | Format section — add `Files` and `Acceptance Criteria` fields |
| `agents/writer.md` | Modify | Transcribe files + acceptance criteria into TASKS.md entries |
| `agents/coder.md` | Modify | Derive TDD cycle from acceptance criteria, not plan code |
| `agents/tester.md` | Modify | Use acceptance criteria as test specification source |
| `agents/reviewer.md` | Modify | Add spec coverage check + type consistency check |

---

### Task 1: Create `skills/writing-plans.md`

**Files:**
- Create: `skills/writing-plans.md`

- [ ] **Step 1: Create the file with this exact content**

```markdown
# Writing Plans

## Overview

Write implementation plans as **task contracts** — intent, acceptance criteria, and file map per task. No code. No TDD step sequences. The plan defines WHAT each task builds and HOW success is measured; agents decide HOW to implement.

Assume the reader is a skilled developer who knows nothing about the codebase or domain.

**Announce at start:** "I'm using the project writing-plans skill to create the implementation plan."

**Save plans to:** `docs/superpowers/plans/YYYY-MM-DD-<feature-name>.md`

## Scope Check

If the spec covers multiple independent subsystems, suggest breaking into separate plans — one per subsystem. Each plan should produce working, testable software on its own.

## File Structure

Before defining tasks, map out which files will be created or modified and what each one is responsible for. Lock in decomposition decisions here.

- Each file has one clear responsibility
- Files that change together should live together
- Follow existing patterns in the codebase

Present this as a table:

| File | Action | Responsibility |
|---|---|---|
| `path/to/file.py` | Create | One-line description |
| `path/to/existing.py` | Modify | One-line description |

## Plan Document Header

Every plan MUST start with this header:

\`\`\`markdown
# [Feature Name] Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** [One sentence describing what this builds]

**Architecture:** [2-3 sentences about approach]

**Tech Stack:** [Key technologies/libraries]

---
\`\`\`

## Task Structure

Each task is a **contract** — intent, file map, and acceptance criteria. No implementation code. Agents derive the HOW from the WHAT.

\`\`\`markdown
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
\`\`\`

## No Placeholders

Every task must contain real intent and testable criteria. These are plan failures:

- "TBD", "TODO", "implement later", "fill in details"
- Vague criteria: "handles errors correctly", "works as expected", "is performant"
- Criteria that cannot be verified by reading code or running a test

Each acceptance criterion must be a concrete, verifiable statement: given a specific input or condition, the system produces a specific observable output or behavior.

## Self-Review

After writing the complete plan, check it against the spec:

**1. Spec coverage:** Can you point to a task for every requirement in the spec? List any gaps and add tasks for them.

**2. Placeholder scan:** Search for any of the failure patterns above. Fix them.

If you find issues, fix them inline.

## Execution Handoff

After saving the plan, offer execution choice:

> "Plan complete and saved to `docs/superpowers/plans/<filename>.md`. Two execution options:
>
> **1. Subagent-Driven (recommended)** — fresh subagent per task, review between tasks
>
> **2. Inline Execution** — execute tasks in this session with checkpoints
>
> Which approach?"

If Subagent-Driven chosen: use `superpowers:subagent-driven-development`
If Inline Execution chosen: use `superpowers:executing-plans`
```

- [ ] **Step 2: Verify the file was created**

```bash
cat skills/writing-plans.md
```

Expected: file content matches what was written above. No truncation.

- [ ] **Step 3: Commit**

```bash
git add skills/writing-plans.md
git commit -m "feat: add project-level writing-plans skill override with task contracts"
```

---

### Task 2: Update `CLAUDE.md` — Phase 0 Step 2

**Files:**
- Modify: `CLAUDE.md` (line 30)

- [ ] **Step 1: Replace the writing-plans invocation line**

Find this line in `CLAUDE.md`:

```
2. Invoke the **writing-plans** skill — read the approved spec, produce the implementation plan to `docs/superpowers/plans/YYYY-MM-DD-<feature-name>.md`, wait for user approval
```

Replace with:

```
2. Read and follow `skills/writing-plans.md` — read the approved spec, produce the implementation plan to `docs/superpowers/plans/YYYY-MM-DD-<feature-name>.md`, wait for user approval
```

- [ ] **Step 2: Verify**

```bash
grep -n "writing-plans" CLAUDE.md
```

Expected: the Phase 0 line now reads "Read and follow `skills/writing-plans.md`". The plugin is not referenced in Phase 0.

- [ ] **Step 3: Commit**

```bash
git add CLAUDE.md
git commit -m "feat: route orchestrator to project writing-plans skill instead of plugin"
```

---

### Task 3: Update `TASKS.md` — Format Section

**Files:**
- Modify: `TASKS.md` (Format section, lines 6–16)

- [ ] **Step 1: Replace the format block**

Find the existing format block:

```
## Format

```
### [TASK-ID] Task Title
**Status:** pending | in_progress | completed | blocked | failed
**Priority:** high | medium | low
**Agent:** researcher | coder | tester | etc.
**Tags:** [domain] tags matching facts.md
**Depends on:** TASK-ID (if any)

Task description — what needs to be done and why.
```
```

Replace with:

```
## Format

```
### [TASK-ID] Task Title
**Status:** pending | in_progress | completed | blocked | failed
**Priority:** high | medium | low
**Agent:** researcher | coder | tester | etc.
**Tags:** [domain] tags matching facts.md
**Depends on:** TASK-ID (if any)
**Files:** `path/to/file.py`, `tests/path/to/test.py`
**Acceptance Criteria:**
- Given X, when Y, then Z
- Edge case: when A, system does B

One sentence description — what needs to be done and why.
```
```

- [ ] **Step 2: Verify**

```bash
grep -n "Acceptance Criteria\|Files:" TASKS.md
```

Expected: both fields appear in the Format section.

- [ ] **Step 3: Commit**

```bash
git add TASKS.md
git commit -m "feat: add Files and Acceptance Criteria fields to TASKS.md format"
```

---

### Task 4: Update `agents/writer.md` — Richer TASKS.md Population

**Files:**
- Modify: `agents/writer.md` (Trigger 1 section)

- [ ] **Step 1: Replace the "You produce" block under Trigger 1**

Find the existing "You produce" block under "1. Plan sign-off — populate TASKS.md":

```markdown
**You produce:**
A fully populated `TASKS.md` with one entry per task from the plan. Use this format for each entry:

```
### [TASK-NNN] <title>
**Status:** pending
**Priority:** <high|medium|low>
**Tags:** [<domain>]
**Description:** <one sentence>
```

Rules:
- Preserve any existing entries already in TASKS.md (do not overwrite completed or in_progress tasks)
- Number tasks sequentially from the highest existing TASK-NNN + 1
- Use `pending` for all new entries — never `in_progress` or `completed`
- Keep descriptions to one sentence — detail lives in the plan doc
```

Replace with:

```markdown
**You produce:**
A fully populated `TASKS.md` with one entry per task from the plan. Transcribe `Files` and `Acceptance Criteria` directly from each plan task contract — do not infer or rewrite them. Derive the one-sentence description from the task's `**Intent:**` field.

Use this format for each entry:

```
### [TASK-NNN] <title>
**Status:** pending
**Priority:** <high|medium|low>
**Agent:** <agent from plan>
**Tags:** [<domain>]
**Depends on:** TASK-NNN (if any)
**Files:** `path/to/file.py`, `tests/path/to/test.py`
**Acceptance Criteria:**
- Given X, when Y, then Z
- Edge case: when A, system does B

One sentence from the plan task's Intent field.
```

Rules:
- Preserve any existing entries already in TASKS.md (do not overwrite completed or in_progress tasks)
- Number tasks sequentially from the highest existing TASK-NNN + 1
- Use `pending` for all new entries — never `in_progress` or `completed`
- Transcribe Files and Acceptance Criteria verbatim from the plan — TASKS.md is the agent's source of truth, not the plan doc
```

- [ ] **Step 2: Verify**

```bash
grep -n "Acceptance Criteria\|Transcribe\|verbatim" agents/writer.md
```

Expected: all three terms appear in the Trigger 1 section.

- [ ] **Step 3: Commit**

```bash
git add agents/writer.md
git commit -m "feat: writer agent transcribes files and acceptance criteria into TASKS.md"
```

---

### Task 5: Update `agents/coder.md` — Acceptance Criteria as TDD Source

**Files:**
- Modify: `agents/coder.md` (Rules section)

- [ ] **Step 1: Add rule after the existing TDD cycle block**

The TDD cycle block ends at:

```
6. Commit when green
```

After the existing Rules section, add this as Rule 7:

```
7. Derive what to implement from the task's `Acceptance Criteria` in your task entry. Do not expect pre-written implementation code. Your TDD cycle maps directly to criteria: read one criterion → write a failing test for it → implement minimal code to pass → move to the next criterion.
```

- [ ] **Step 2: Verify**

```bash
grep -n "Acceptance Criteria" agents/coder.md
```

Expected: the new rule appears in the Rules section.

- [ ] **Step 3: Commit**

```bash
git add agents/coder.md
git commit -m "feat: coder agent derives TDD cycle from task acceptance criteria"
```

---

### Task 6: Update `agents/tester.md` — Acceptance Criteria as Test Spec

**Files:**
- Modify: `agents/tester.md` (Rules section)

- [ ] **Step 1: Add rule to the Rules section**

After the existing Rule 6 (`Use real infrastructure where possible...`), add:

```
7. Use the task's `Acceptance Criteria` as your test specification. Each criterion must map to at least one integration or edge case test. Criteria not already covered by the coder's unit tests are your primary target.
```

- [ ] **Step 2: Verify**

```bash
grep -n "Acceptance Criteria" agents/tester.md
```

Expected: the new rule appears in the Rules section.

- [ ] **Step 3: Commit**

```bash
git add agents/tester.md
git commit -m "feat: tester agent uses task acceptance criteria as test specification"
```

---

### Task 7: Update `agents/reviewer.md` — Absorb Spec Coverage and Type Consistency

**Files:**
- Modify: `agents/reviewer.md` (Role section and Rules section)

- [ ] **Step 1: Extend the "You produce" block**

Find the existing `You produce` block:

```markdown
## You produce
```
STATUS: PASS | FIX_REQUIRED

REQUIRED CHANGES (if any):
1. [file:line] Issue. Expected: X. Found: Y.
2. ...

CONVENTION CANDIDATES (if any):
- Pattern: [description]. Suggested rule: [rule text]
```
```

Replace with:

```markdown
## You produce
```
STATUS: PASS | FIX_REQUIRED

REQUIRED CHANGES (if any):
1. [file:line] Issue. Expected: X. Found: Y.
2. ...

CONVENTION CANDIDATES (if any):
- Pattern: [description]. Suggested rule: [rule text]
```

Spec coverage failures and type inconsistencies both produce entries in `REQUIRED CHANGES` — they block the pipeline the same way convention violations do.
```

- [ ] **Step 2: Add two rules to the Rules section**

After existing Rule 5 (`If a pattern appears 3+ times...`), add:

```
6. **Spec coverage:** For each acceptance criterion in the task entry, verify the implementation satisfies it. Flag any criterion with no corresponding code path as a required change: `[file] Criterion not implemented: "<criterion text>"`
7. **Type consistency:** Scan the diff for inconsistent names — function names, method names, type names used across multiple files. Flag any mismatch as a required change: `[file:line] Name mismatch: "X" here vs "Y" in [other file]`
```

- [ ] **Step 3: Verify**

```bash
grep -n "Spec coverage\|Type consistency\|criterion" agents/reviewer.md
```

Expected: all three terms appear in the Rules section.

- [ ] **Step 4: Commit**

```bash
git add agents/reviewer.md
git commit -m "feat: reviewer agent absorbs spec coverage and type consistency checks"
```

---

## Self-Review

**Spec coverage check:**

| Spec requirement | Task that implements it |
|---|---|
| Create `skills/writing-plans.md` (thinned override) | Task 1 |
| Update `CLAUDE.md` Phase 0 Step 2 | Task 2 |
| Update `TASKS.md` format with Files + Acceptance Criteria | Task 3 |
| Writer transcribes Files + Acceptance Criteria into TASKS.md | Task 4 |
| Coder derives TDD from acceptance criteria | Task 5 |
| Tester uses acceptance criteria as test spec | Task 6 |
| Reviewer absorbs spec coverage + type consistency | Task 7 |

No gaps.

**Placeholder scan:** No TBDs, TODOs, or vague steps. Every step shows exact content to write or exact command to run.

**Type consistency:** No type names or function signatures — not applicable (markdown edits only).
