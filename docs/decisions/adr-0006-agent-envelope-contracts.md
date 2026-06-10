# ADR-0006: Agent Envelope Contracts and Output Validation Gate

**Status:** Accepted
**Date:** 2026-06-09

## Context

Before PR #42, agents returned prose text. The orchestrator parsed this free-form output to decide the next routing step. This created several failure modes: an agent could return a perfectly correct analysis but in a format the orchestrator didn't recognise, causing a silent mis-route. There was no way to distinguish "agent returned FIX_REQUIRED because the code has a bug" from "agent returned something that happened to contain the string FIX_REQUIRED in a sentence." Agents also had no obligation to include a `reason` on failure verdicts, so blocked pipelines left no diagnostic trail.

## Decision

Every agent returns a single JSON envelope conforming to a contract defined in `contracts/<agent>.json`. The contract specifies:
- `required_fields` — fields that must be present (task_id, agent, verdict, payload, next_agent, timestamp)
- `valid_verdicts` — the only allowed verdict strings for that agent
- `reason_required_on` — verdicts that require a non-empty `reason` field

`hooks/validate_output.sh` validates every envelope against its contract before the orchestrator routes. Invalid output causes the orchestrator to mark the task `blocked` and stop the pipeline — the agent cannot silently produce garbage and have it propagate downstream. Validated envelopes are also appended to `logs/pipeline.jsonl` automatically by `validate_output.sh`, so the structured log always contains only validated records.

Agent definitions were updated to output JSON only — no prose before or after the envelope.

Pipeline state is tracked in `pipeline_state.json` via `init_pipeline_state.sh` and `advance_pipeline_state.sh`, written atomically. On session recovery, `pre_task.sh` reads `pipeline_state.json` and emits a `RECOVERY:` block so the orchestrator knows exactly which step was interrupted.

## Alternatives considered

- **Schema-less JSON (just require valid JSON, no contract):** Catches parse errors but not semantic errors. A `verdict: "BLOCKED"` from the Coder agent (which should never return BLOCKED) would pass validation. Rejected.
- **Prose with structured markers (e.g. `VERDICT: PASS`):** Easy for agents to produce, hard to parse reliably. Ambiguous when the word appears in explanatory text. Rejected.
- **gRPC / typed schemas:** More rigorous but requires a schema compiler and adds significant tooling overhead for a shell-driven pipeline. Rejected.

## Consequences

- Agents can no longer express partial or ambiguous outputs — every run ends in a valid verdict or a blocked task with a logged reason.
- Adding a new verdict to an agent requires updating both the agent definition and its contract file — two places to change instead of one.
- `validate_output.sh` is a required step in the orchestrator loop; skipping it risks routing on unvalidated output.
- Pipeline trace (`pipeline.jsonl`) is guaranteed to contain only validated records — analytics tools can assume the log is structurally clean.

## Revisit trigger

If Claude Code gains native structured output support (typed returns from Agent tool calls), the shell-based validation layer could be replaced with harness-level schema enforcement.
