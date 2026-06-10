# Pipeline SLO Contracts

Explicit performance envelopes for the agent pipeline, enforced by
`hooks/budget_guard.sh`. **The tables below are the source of truth** —
the script parses them at runtime; edit limits here, never in the script.

Soft limit breach → warning on stderr (visible to the user).
Hard limit breach in `CLAUDE_BUDGET_MODE=halt` → the tool call is blocked
(hook exit 2) and the reason is fed back to the model.

---

## Per-agent tool call budgets (per pipeline run)

| Agent | Soft limit | Hard limit | Rationale |
|---|---|---|---|
| researcher | 15 | 25 | Broad exploration expected |
| coder | 20 | 35 | Implementation + file reads |
| reviewer | 10 | 15 | Read-heavy, minimal writes |
| tester | 15 | 25 | Test writing + execution |
| security | 8 | 12 | Targeted diff analysis |
| git | 5 | 8 | Mechanical only |
| memory | 5 | 8 | File updates only |
| devops | 10 | 18 | CI polling + smoke tests |
| writer | 12 | 20 | Document generation |

---

## Per-task pipeline wall-clock budget (seconds)

Measured against `started_at` in `pipeline_state.json`.

| Pipeline | Warn (s) | Halt (s) |
|---|---|---|
| fast-track | 300 | 600 |
| full | 900 | 1800 |

---

## Daily aggregate

- Warn at 80% of `CLAUDE_DAILY_CALL_LIMIT` (default 500 → warn at 400)
- Halt at 100% of `CLAUDE_DAILY_CALL_LIMIT`
- Counted in UTC from `logs/tool_calls.log` (tool lines only)

---

## How budget_guard.sh resolves context

Agent identity, run_id, pipeline type, and start time are read from
`pipeline_state.json` (maintained by `init_pipeline_state.sh` /
`advance_pipeline_state.sh`). No environment variables are required;
`CLAUDE_CURRENT_AGENT` overrides the state file for tests and manual runs.
