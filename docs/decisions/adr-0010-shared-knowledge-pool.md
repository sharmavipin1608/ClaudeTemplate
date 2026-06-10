# ADR-0010: Shared Knowledge Pool as a Separate Git Repository

**Status:** Accepted
**Date:** 2026-06-10

## Context

Facts marked `scope:team` or `scope:org` are useful across multiple projects. Without a sharing mechanism, each new project bootstrapped from the template starts with zero accumulated knowledge — the same patterns get rediscovered and re-written in every project's `memory/facts.md`.

A sharing mechanism needed to satisfy three constraints:
1. **No central dependency for single-project use** — the template must work without a shared pool; it is strictly opt-in.
2. **Conflict detection before merge** — pushing a fact that contradicts an existing pool entry silently would corrupt shared knowledge.
3. **Human review for org-scoped facts** — facts at `scope:org` represent the organisation's conventions and should not be merged by an automated process without review.

## Decision

The shared pool is a separate git repository (`ClaudeKnowledge` by convention) with this structure:
```
facts/
  team.jsonl    ← scope:team facts, one JSON object per line
  org.jsonl     ← scope:org facts
conventions/
  approved.md   ← conventions promoted from candidates.md across projects
taxonomy.md     ← canonical tag list (source of truth for all projects)
```

`tools/pool_sync.py` provides three subcommands:
- `pull` — copies `taxonomy.md` and `scope:org` facts into the local project at bootstrap
- `check` — semantic conflict detection: finds near-matches in the pool for a given tag+fact pair; exits 1 if conflict found
- `push` — opens a PR against the pool repository with the new fact; never pushes directly to main

The Memory agent runs `check` before any `push`. On conflict (exit 1), it surfaces `POOL CONFLICT: <details>` and does not push — the orchestrator resolves with the user.

The pool URL is configured via `CLAUDE_POOL_URL` environment variable. If not set, all pool operations are skipped silently. Bootstrap Step 3c prompts for the URL once; if left blank, the project runs in standalone mode.

Bootstrap also pulls taxonomy from the pool so new projects start with the org's canonical tag list rather than the template default.

## Alternatives considered

- **Embed shared facts in the template repository itself:** Conflates template infrastructure with project-specific knowledge. Every template update would require a merge of accumulated facts. Rejected.
- **Shared database (Postgres, SQLite over NFS):** Requires infrastructure beyond a git repo; adds a hard dependency. Rejected for a tool designed to run locally.
- **Automatic merge without conflict check:** Fast but risks silent fact corruption. Rejected — the conflict check adds one command before a push.
- **Monorepo (all projects in one repo):** Solves sharing but eliminates project isolation. Not applicable to this template's use case.

## Consequences

- The shared pool is only as good as the review process for pool PRs. If pool PRs are never merged, the pool stays empty.
- Conflict detection uses semantic similarity (overlapping keywords), not exact match — may produce false positives on verbose facts. Teams should tune or override if this becomes noisy.
- `pool_sync.py pull` at bootstrap seeds a new project with org knowledge but also introduces facts that were true at pull time. Projects should re-pull periodically to get updated pool facts (no automated re-pull is implemented yet).
- The pool PR workflow requires `gh` CLI on the machine running the Memory agent.

## Revisit trigger

When pool facts exceed ~500 entries, replace keyword-based conflict detection with vector similarity search (ChromaDB or equivalent indexing the pool JSONL files).
