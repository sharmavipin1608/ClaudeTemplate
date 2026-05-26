# Writing Plans

## Overview

Write implementation plans as **task contracts** — intent, acceptance criteria, and file map per task. No code. No TDD step sequences. The plan defines WHAT each task builds and HOW success is measured; agents decide HOW to implement.

Write for a skilled agent who knows nothing about this codebase or domain — explain project-specific context but not general programming concepts.

**Announce at start:** "I'm using the project writing-plans skill to create the implementation plan."

**Save plans to:** `docs/superpowers/plans/YYYY-MM-DD-<feature-name>.md`

## Scope Check

If the spec covers multiple independent subsystems, suggest breaking into separate plans — one per subsystem. Each plan should produce working, testable software on its own.

Wait for user confirmation before proceeding with any single plan.

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

Include this table in the plan document body, after the header and before the first task.

## Plan Document Header

Every plan MUST start with this header:

```markdown
# [Feature Name] Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Acceptance criteria use checkbox (`- [ ]`) syntax for tracking.

**Goal:** [One sentence describing what this builds]

**Architecture:** [2-3 sentences about approach]

**Tech Stack:** [Key technologies/libraries]

---
```

## Task Structure

Each task is a **contract** — intent, file map, and acceptance criteria. No implementation code. Agents derive the HOW from the WHAT.

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

Choose `researcher` if the task requires domain discovery before implementation; `writer` for documentation-only tasks; `coder` for all implementation tasks.

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

## On Completion

After saving the plan, return to the orchestrator. Do not prompt the user for an execution mode — the orchestrator's pipeline handles task dispatch from here.
