# ADR-0002: Security Agent Runs Standalone as a Hard Gate

**Status:** Accepted
**Date:** 2026-06-09

## Context

The orchestrator dispatches agents by composing a context payload and calling the Agent tool. Multiple agents can be batched into a single subagent call to save dispatch overhead. Security is the only pipeline stage whose output determines whether the pipeline continues or halts entirely — a `BLOCKED` verdict must prevent Git from running. The question was whether Security could be batched with adjacent stages (e.g. Tester or Git) for efficiency.

The routing logic reads the `verdict` field from each agent's JSON envelope. If two agents return in the same response, the orchestrator receives a single blob and must extract two separate verdicts. There is no guaranteed structure for this — the parsing is fragile and easy to get wrong, especially if one agent's output is verbose and the other's verdict is buried.

## Decision

Security always runs as a standalone agent dispatch. It is never batched with any other agent. The pipeline strictly separates it:

```
... → Tester → [Security standalone] → Git → ...
```

On `verdict: BLOCKED`:
1. The orchestrator marks the task `blocked` in `TASKS.md`.
2. The blocking reasons are logged.
3. The pipeline stops — Git is never dispatched.

On `verdict: PASS`:
1. The orchestrator advances to Git.

Git is explicitly forbidden from running in the same subagent call as Security, even sequentially within one call.

## Alternatives considered

- **Batch Security with Tester:** Saves one agent dispatch per task. Rejected because Tester verdict must be resolved first (a `FAIL` routes back to Coder), and Security should only scan code that has already passed tests. If batched, Security would scan code that might still be rewritten.
- **Batch Security with Git (Security → Git in one call):** Rejected because if Security returns `BLOCKED`, Git would still be present in the same execution context and could commit before the orchestrator's routing logic fires. The separation is a structural guarantee, not just a convention.
- **Trust orchestrator to parse both verdicts from a combined response:** Rejected because multi-agent response parsing is ambiguous without a strongly-typed protocol. A parsing bug would silently allow code with blockers to be committed.

## Consequences

- One extra agent dispatch per task compared to a batched arrangement.
- The Security gate is structurally guaranteed: no code is ever committed when Security returns `BLOCKED`, regardless of orchestrator logic errors.
- Adding new pipeline stages around Security (e.g. a Compliance agent) requires explicitly placing them either before or after the Security standalone slot — the isolation makes the boundary visible.

## Revisit trigger

If a structured multi-agent response protocol is introduced that guarantees per-agent verdict parsing with typed fields and schema validation (e.g. a harness-level envelope schema), the batching restriction could be reconsidered. Until then, the standalone requirement stands.
