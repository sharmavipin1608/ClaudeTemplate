# ADR-0007: Tool Call Count as Cost Proxy for Budget Enforcement

**Status:** Accepted
**Date:** 2026-06-09

## Context

The pipeline needs a way to prevent runaway sessions from consuming unbounded API spend. The natural unit to track is token count — input + output tokens directly determine API cost. However, Claude Code hooks do not expose token counts. Neither `PreToolUse` nor `PostToolUse` hook payloads include token usage for the turn that triggered them.

A budget enforcement mechanism was still required. Without one, a misconfigured task or a looping agent has no external check.

## Decision

Tool call count is used as a cost proxy. `budget_guard.sh` counts lines in `logs/tool_calls.log` dated today and enforces two thresholds:

- **Daily aggregate:** configurable via `CLAUDE_DAILY_CALL_LIMIT` (default 500). Warns at 80%, halts or warns at 100% depending on `CLAUDE_BUDGET_MODE`.
- **Per-agent:** hard limits defined in a lookup table inside `budget_guard.sh` (e.g. Security: hard=12, Coder: hard=35). Enabled when `CLAUDE_CURRENT_AGENT` is set in the environment before agent dispatch.

`contracts/pipeline-slos.md` documents the rationale for each per-agent limit. The soft limit is the expected upper bound for a well-scoped task; the hard limit is where something has clearly gone wrong.

`CLAUDE_BUDGET_MODE=halt` stops the pipeline when a limit is reached. The default is `warn` so that legitimate complex tasks are not silently blocked — the operator must opt into enforcement.

## Alternatives considered

- **Wait for token count exposure in hooks:** Blocks budget enforcement indefinitely on an API capability outside the project's control. Rejected as a primary strategy; can be adopted if/when available.
- **Estimate tokens from prompt text length:** Complex and brittle — token count is not proportional to character count across all inputs. Would require maintaining an approximation library. Rejected.
- **No budget enforcement at all:** Acceptable for solo use but makes team use and unattended runs unsafe. Rejected.

## Consequences

- Tool call count is a coarse proxy: a task with many small reads costs less than a task with few large generations, but both produce the same call count. The proxy is directionally correct but not precise.
- Per-agent limits use today's total call count as the agent-specific count when no finer-grained tracking exists — this is conservative (over-counts) but safe.
- When Claude Code exposes token counts in hooks, the lookup table in `budget_guard.sh` should be replaced with token-based thresholds and this ADR superseded.

## Revisit trigger

Claude Code exposes per-turn token usage in hook payloads.
