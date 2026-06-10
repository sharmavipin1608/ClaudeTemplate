# ADR-0008: Dual-Log Architecture — Flat Tool Log and Structured Pipeline Trace

**Status:** Accepted
**Date:** 2026-06-09

## Context

The pipeline needed observability at two distinct levels:

1. **Every tool call** — a raw audit trail of what Claude touched, in order, with timestamps. Useful for debugging and budget counting.
2. **Pipeline-level events** — structured records of agent lifecycle (start, end, outcome, routing) and classifier decisions. Useful for analytics, latency measurement, and quality tracking.

Combining both into one log would either make the flat log too structured (verbose for simple audit use) or make the structured log too noisy (tool calls would drown out agent-level signals).

## Decision

Two separate logs with distinct purposes:

**`logs/tool_calls.log`** — flat, line-per-tool-call format: `timestamp | tool_name`. Written by `log_tool.sh` on every PreToolUse and PostToolUse event. Also used by `budget_guard.sh` for daily call counting. Gitignored — not committed.

**`logs/pipeline.jsonl`** — structured JSONL. Contains:
- `classifier` events (verdict, rule_fired, task_id) — written by `classify_task.sh`
- `agent_start` / `agent_end` events (agent, task_id, pipeline, outcome, next_agent, retry) — written by `log_agent.sh`
- `tool_call` events (tool_name, agent, task_id) when `CLAUDE_TASK_ID` + `CLAUDE_CURRENT_AGENT` are set — written by `log_tool.sh`
- Validated agent envelopes — written by `validate_output.sh`
- `outcome_link` events (task_id, caused_by) — written by the Memory agent for rework tracing

`pipeline.jsonl` is not gitignored — it accumulates the project's run history and is the input to `tools/pipeline_analytics.py`.

`CLAUDE_TASK_ID` and `CLAUDE_CURRENT_AGENT` are set by the orchestrator before each agent dispatch and unset after, providing context propagation for tool_call events without requiring changes to individual hooks.

## Alternatives considered

- **Single structured log for everything:** Tool calls (dozens per agent run) would produce far more records than agent-level events, making agent timing queries require filtering noise. Rejected.
- **One flat log for everything:** Fast to write but requires regex parsing to extract agent-level signals. Analytics would be fragile. Rejected.
- **External log aggregator (e.g. write to Loki/CloudWatch):** Adds infrastructure dependency to a self-contained template. Rejected for the template; addressed separately by Issue #23 (Telemetry Agent for bootstrapped projects).

## Consequences

- Two log files must be managed separately — different gitignore treatment, different retention policies.
- `pipeline.jsonl` records grow unbounded. There is currently no rotation or size limit. For long-running projects, this file will need periodic archiving (tracked as a gap in the audit).
- `tools/pipeline_analytics.py` and `tools/trace_analyze.py` both read `pipeline.jsonl` — they serve different audiences (analytics vs. debug) but share the same source.

## Revisit trigger

If pipeline.jsonl exceeds a size that makes analytics slow (rough threshold: >50K lines or >10MB), add rotation or move to a proper time-series store.
