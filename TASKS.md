# Task Queue

Tasks are processed top-to-bottom. Each task goes through the full agent pipeline.

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

## Tasks

### [TASK-001] Verify bootstrap completed successfully
**Status:** pending
**Priority:** high
**Agent:** writer
**Tags:** [core]

Health check — confirm bootstrap.sh ran correctly before any real work starts. Check:
- No `{{PLACEHOLDER}}` strings remain in any `.md`, `.sh`, `.py`, or `.json` file
- `memory/core.md` has real project name, stack, description, owner, and date
- `CONVENTIONS.md` has a real date (not `{{DATE}}`)
- `README.md` exists and was generated from `README_TEMPLATE.md`
- `scripts/` directory has been removed
- `README_TEMPLATE.md` has been removed

If any check fails, stop and fix bootstrap before proceeding to TASK-002.

### [TASK-002] Complete memory/core.md
**Status:** pending
**Priority:** high
**Agent:** writer
**Tags:** [core]
**Depends on:** TASK-001

Fill in the sections bootstrap intentionally leaves blank — these require real project knowledge:
- `## Architecture Overview` — describe the system shape (monolith vs services, key layers, data flow)
- `## Key External Dependencies` — list third-party services, APIs, and databases with a one-line description of each

### [TASK-003] Fill in CONVENTIONS.md decisions
**Status:** pending
**Priority:** medium
**Agent:** writer
**Tags:** [conventions]
**Depends on:** TASK-001

Work through the TODO items in CONVENTIONS.md and replace them with actual project decisions. Key ones to resolve early:
- Formatter and version (black, prettier, gofmt, etc.)
- Actual folder structure for your stack
- API versioning strategy
- Coverage targets and enforcement method

These don't need to be perfect on day one — fill in what's known and leave the rest for the Memory agent to update as decisions emerge.

### [TASK-004] Review and adjust agent definitions for your stack
**Status:** pending
**Priority:** medium
**Agent:** writer
**Tags:** [agents]
**Depends on:** TASK-002

Read through `agents/coder.md`, `agents/tester.md`, and `agents/security.md` and adjust any stack-specific guidance for your tech stack. The defaults are language-agnostic — a Node.js project and a Python project need different linting commands, test runners, and security checks.
