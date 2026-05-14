# Task Queue

Tasks are processed top-to-bottom. Each task goes through the full agent pipeline.

## Format

```
### [TASK-ID] Task Title
**Status:** pending | in_progress | done | blocked | failed
**Priority:** high | medium | low
**Agent:** researcher | coder | tester | etc.
**Tags:** [domain] tags matching facts.md
**Depends on:** TASK-ID (if any)

Task description — what needs to be done and why.
```

## Tasks

### [TASK-001] Review and fill in CONVENTIONS.md
**Status:** pending
**Priority:** high
**Agent:** writer
**Tags:** [conventions]

Review the generated CONVENTIONS.md and fill in all `# TODO` markers with project-specific decisions. This file is a living document — the reviewer and memory agents will actively maintain it throughout the project lifecycle.

### [TASK-002] Populate memory/core.md
**Status:** pending
**Priority:** high
**Agent:** writer
**Tags:** [core]

Verify that bootstrap.sh correctly populated memory/core.md with project identity. Add any missing details: key team members, external dependencies, architectural constraints, third-party services.
