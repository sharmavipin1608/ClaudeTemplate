# ADR-0001: Sequential Pipeline Order

**Status:** Accepted
**Date:** 2026-06-09

## Context

The ClaudeTemplate orchestrator dispatches a series of agents to complete each development task. A decision was needed on whether agents should run sequentially or in parallel, and what order sequential stages should follow. The core constraint is that each stage must be able to rely on the previous stage having already done its job — a Reviewer that runs before the Coder produces anything has nothing to review; a Security agent that runs before tests pass may gate on code that will be rewritten anyway.

## Decision

Agents run in a strictly sequential pipeline in this order:

```
Researcher → Coder → Reviewer → Tester → Security → Git → Memory
```

The rationale for each adjacency:

- **Researcher before Coder:** Coder receives domain knowledge and relevant facts before writing any code, avoiding rework caused by discovering constraints mid-implementation.
- **Coder before Reviewer:** Reviewer has a complete diff to evaluate rather than a partial or speculative one. Reviewer verdict (`PASS` / `FIX_REQUIRED`) routes back to Coder for a single retry if needed.
- **Reviewer before Tester:** Tests are written against code that has already passed a logic and design review. This prevents writing tests for code that will be rewritten.
- **Tester before Security:** Security scans real, tested, working code — not a draft. A Security gate on untested code would frequently flag issues that are artifacts of incomplete implementation.
- **Security before Git:** Git only runs after Security returns `PASS`. This guarantees no code with known security blockers is ever committed.
- **Git before Memory:** Memory preserves the final state including the commit SHA. Running Memory before Git would checkpoint an uncommitted state.

## Alternatives considered

- **Parallel stages (e.g. Reviewer + Tester in parallel):** Faster wall-clock time but errors compound. If Reviewer returns `FIX_REQUIRED`, any tests written in parallel are wasted. Parallel execution also complicates verdict routing since two agents would return simultaneously and the orchestrator would need to resolve conflicting signals.
- **Security first (before Coder):** Would block before any code exists. Security needs a diff to evaluate.
- **No Reviewer stage:** Cheaper (one fewer agent dispatch per task) but loses the design-level feedback loop. The Reviewer is the only stage that catches logic issues before tests are written — skipping it shifts debugging cost to Tester and later stages.

## Consequences

- Pipeline takes longer than a parallel arrangement for the same number of agents.
- Each stage has full context from all prior stages, reducing total rework.
- A `Security: BLOCKED` verdict stops all downstream work cleanly — Git and Memory never run, so no partial state is committed or checkpointed.
- The Reviewer retry loop (one `FIX_REQUIRED` allowed before marking `blocked`) is possible only because Reviewer runs before Tester; a retry after tests are written would require discarding test work.

## Revisit trigger

If average full-pipeline time regularly exceeds 30 minutes, evaluate which adjacent stages can be parallelised without compounding errors. Start with Researcher + early Coder work, since Researcher output is read-only (no routing dependency on its verdict).
