# ADR-0005: Fast-Track Pipeline Criteria

**Status:** Accepted
**Date:** 2026-06-09

## Context

The full pipeline dispatches 7 agents per task: Researcher → Coder → Reviewer → Tester → Security → Git → Memory. For many tasks — particularly small changes where the domain is already documented in `memory/facts.md` — two of those agents add latency without proportionate quality benefit:

- **Researcher:** Adds value when the domain is unknown. When `memory/facts.md` already has relevant tagged entries, the Researcher would duplicate work already captured in memory.
- **Reviewer:** Adds value for changes that introduce new behaviour, touch shared logic, or present design-level tradeoffs. For a 1-3 file mechanical change (e.g. renaming a constant, updating a config value, adding a log statement), the Reviewer catches nothing that the Tester would not.

The question was: what criteria justify skipping these two stages, and what signals should the orchestrator act on?

## Decision

**Fast-Track Pipeline:**
```
Coder → Tester → Security → Git → Memory
```
Skipped: Researcher (domain already known), Reviewer (scope too small to warrant design review).
Never skipped: Security (hard gate), Memory (system coherence).

**Criteria for fast-track (all must hold):**
1. The domain is already known — `memory/facts.md` contains tagged entries for this task's domain (verified by grep before dispatching)
2. The change is small — estimated at ≤5 files modified, no new behaviour introduced, no changes to shared interfaces or contracts
3. `hooks/classify_task.sh` returns `AMBIGUOUS` — not `FORCE_FULL`

**The orchestrator must reason explicitly** when `classify_task.sh` returns `AMBIGUOUS`: does this task introduce new behavior, touch shared logic, or carry risk not caught by pattern rules? If yes, use full pipeline. If no, fast-track is appropriate. The decision must be logged.

If `classify_task.sh` returns `FORCE_FULL`, the orchestrator has no discretion — full pipeline runs regardless of the above criteria. The classification hook's output is a gate, not a suggestion (see Golden Rule 9).

## Alternatives considered

- **Skip only Researcher (keep Reviewer):** Saves one agent dispatch, retains design review. Rejected as insufficient — the primary latency on small tasks is often the round-trip, not any individual stage. If the change is small enough that Researcher is unnecessary, it is typically small enough that Reviewer provides minimal value.
- **Skip everything except Security + Git + Memory:** Maximum speed, minimum cost. Rejected because Coder without Tester means no test coverage on the change. Security needs working, tested code to evaluate. Tester is never optional.
- **Let the orchestrator decide each stage individually:** Too much discretion leads to inconsistent behaviour across sessions. The two-track model (full vs fast-track) is a named, documented choice with explicit criteria — easier to reason about and audit.
- **Always run the full pipeline:** Eliminates the fast-track complexity. Rejected because the cost and latency of Researcher + Reviewer on every task regardless of size is wasteful at scale.

## Consequences

- Fast-track saves approximately 2 agent dispatches per qualifying task (Researcher + Reviewer) — roughly 28% reduction in dispatches for a 7-agent pipeline.
- The orchestrator bears the judgment burden for `AMBIGUOUS` tasks. A conservative orchestrator will rarely use fast-track; an aggressive one may overuse it. The logged decision creates an audit trail.
- Fast-tracked tasks that produce bugs would have had Reviewer coverage in the full pipeline. This is the accepted trade-off — the criteria are designed to identify cases where that coverage would have found nothing.
- `FORCE_FULL` classification always overrides fast-track criteria. The classification hook is the authoritative signal.

## Revisit trigger

If fast-tracked tasks produce a disproportionate number of bugs that a Reviewer would have caught (identifiable by correlating `agent_calls.log` fast-track entries with post-merge bug reports), tighten the fast-track criteria — specifically consider requiring Reviewer for any change that touches more than 2 files.
