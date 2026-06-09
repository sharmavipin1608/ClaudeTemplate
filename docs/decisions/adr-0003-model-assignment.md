# ADR-0003: Agent Model Assignment by Role

**Status:** Accepted
**Date:** 2026-06-09

## Context

Claude Code allows each subagent dispatch to specify a `model` parameter. The template supports three model tiers with materially different capability and cost profiles: `opus` (most capable, highest cost), `sonnet` (strong reasoning, moderate cost), and `haiku` (fast and cheap, limited reasoning depth). Using the most capable model for every agent is unnecessarily expensive. Using the cheapest for every agent degrades result quality at the stages that most require it.

The `agents.default_model` field in `settings.json` is metadata only — Claude Code does not read it to set subagent models. The orchestrator must always specify `model` explicitly when dispatching each agent.

## Decision

Model assignments are fixed by role:

| Agent | Model | Reason |
|---|---|---|
| Orchestrator | `opus` | Plans the full feature, makes pipeline routing decisions, resolves ambiguity — requires the deepest reasoning |
| Researcher | `sonnet` | Synthesises domain knowledge from codebase and memory; needs solid analytical reasoning |
| Coder | `sonnet` | Produces the implementation diff; code quality depends on reasoning depth |
| Reviewer | `sonnet` | Must catch logic errors, design issues, and edge cases — **never haiku**; this is a hard constraint |
| Tester | `sonnet` | Edge case coverage requires reasoning about failure modes |
| Security | `sonnet` | Hard gate; a missed vulnerability is worse than the cost difference; **never haiku** |
| DevOps | `sonnet` | CI polling, smoke test validation, and deployment checks require judgment |
| Git | `haiku` | Mechanical operations only: format commit message, run git commands |
| Memory | `haiku` | File updates only: write to facts.md, update session checkpoint |
| Changelog | `haiku` | Text formatting only: summarise git log into CHANGELOG.md |
| Writer | `sonnet` | Document generation (TASKS.md population, specs) requires judgment about completeness |

The rule "Reviewer never runs on haiku" is a hard constraint, not a guideline. The Reviewer is the only pipeline stage that catches logic and design issues before tests are written. A haiku Reviewer produces false confidence — it passes code that a sonnet Reviewer would have flagged.

## Alternatives considered

- **All sonnet:** Simpler to reason about, no per-agent model decision. Rejected because Opus cost for the orchestrator is justified (it plans the entire feature), and Haiku is genuinely sufficient for Git, Memory, and Changelog operations.
- **All haiku:** Cheap but Reviewer misses design issues. Rejected. The cost savings do not offset the quality loss at gate stages.
- **Dynamic selection based on task complexity:** The orchestrator classifies each task as `FORCE_FULL` or `AMBIGUOUS` (via `classify_task.sh`). In principle, a simple task could use cheaper models. Rejected for now because the classification is about pipeline track selection, not model tier. Adding a second dimension of model-per-task-complexity creates combinatorial routing rules that are hard to reason about. Revisit if cost becomes a primary constraint.

## Consequences

- Cost scales predictably with task count, not task complexity. Each full-pipeline task always dispatches one Opus call (orchestrator) and a fixed number of Sonnet and Haiku calls.
- The hard "never haiku for Reviewer/Security" rule is enforced by convention in the orchestrator prompt, not by tooling. A future harness-level enforcement (e.g. model validation in `validate_output.sh`) would be more robust.
- Changelog generation at end-of-day is cheap (Haiku + Memory also Haiku) and does not contribute meaningfully to per-task cost.

## Revisit trigger

When a new model family ships with significantly different capability/cost ratios — particularly if a future "haiku" tier matches current sonnet reasoning quality — re-evaluate whether Reviewer and Security can move to the cheaper tier.
