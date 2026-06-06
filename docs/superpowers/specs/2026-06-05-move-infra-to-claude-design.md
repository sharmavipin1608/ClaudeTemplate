---
title: Move Claude infrastructure to .claude/ and split CLAUDE.md
date: 2026-06-05
issue: "#28"
status: approved
---

## Problem

`agents/`, `hooks/`, `skills/`, and `tools/` land at project root after bootstrap, indistinguishable from application source. `CLAUDE.md` is 294 lines mixing project identity (changes per project) with pipeline machinery (identical across all projects).

## Decision

Approach A — pre-authored orchestrator.md in template.

- Template keeps dirs at root unchanged (template continues to work for ClaudeTemplate development)
- `.claude/orchestrator.md` is pre-authored in the template with paths updated for the new layout
- `bootstrap.sh` new Step 7/9: moves `agents/`, `hooks/`, `skills/`, `tools/` into `.claude/`; updates hook paths in `settings.json`; patches `classify_task.sh` internal path pattern; writes slim `CLAUDE.md`
- `memory/` stays at root (live project data, not static tooling)
- `logs/` stays at root (not in scope)

## What moves

| Directory | After bootstrap |
|---|---|
| `agents/` | `.claude/agents/` |
| `hooks/` | `.claude/hooks/` |
| `skills/` | `.claude/skills/` |
| `tools/` | `.claude/tools/` |
| `memory/` | root (unchanged) |
| `logs/` | root (unchanged) |

## Slim CLAUDE.md shape (~12 lines)

```
# CLAUDE.md — Project Instructions
## Project Identity
- Project, Stack, conventions, agents, tasks
@.claude/orchestrator.md
```

## Internal hook path change

`classify_task.sh` has a hardcoded `file_matches "^hooks/"` rule. Bootstrap patches it to `^\.claude/hooks/` after the move.

## Verification (4-phase)

1. **Bootstrap path checks** — `ls agents/` returns "No such file", `ls .claude/agents/` succeeds, `grep -c '"bash hooks/'` returns 0, `wc -l CLAUDE.md` < 25
2. **Hook smoke test** — each `.claude/hooks/*.sh` script exits 0 when invoked directly
3. **Minimal pipeline run** — bootstrap test project (Python, one task: `greet(name)` function), run full pipeline, verify: hooks log entries, agent timing logged, code produced, pytest passes, task `completed`, git commit exists, facts.md updated
4. **@-import check** — confirm `@.claude/orchestrator.md` resolves in a Claude Code session opened in the bootstrapped project
