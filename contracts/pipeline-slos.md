# Pipeline SLO Contracts

Explicit performance envelopes for the agent pipeline. `hooks/budget_guard.sh` enforces per-agent hard limits. Exceeding a soft limit emits a warning; exceeding a hard limit halts the agent.

---

## Per-agent tool call budgets

| Agent | Soft limit | Hard limit | Rationale |
|---|---|---|---|
| Researcher | 15 | 25 | Broad exploration expected |
| Coder | 20 | 35 | Implementation + file reads |
| Reviewer | 10 | 15 | Read-heavy, minimal writes |
| Tester | 15 | 25 | Test writing + execution |
| Security | 8 | 12 | Targeted diff analysis |
| Git | 5 | 8 | Mechanical only |
| Memory | 5 | 8 | File updates only |
| DevOps | 10 | 18 | CI polling + smoke tests |
| Writer | 12 | 20 | Document generation |
| Researcher | 15 | 25 | Domain analysis |

---

## Per-task pipeline wall-clock budget

- Fast-track: warn > 5 min, halt > 10 min
- Full pipeline: warn > 15 min, halt > 30 min

---

## Daily aggregate

- Warn at 80% of `CLAUDE_DAILY_CALL_LIMIT` (default 500 → warn at 400)
- Halt at 100% of `CLAUDE_DAILY_CALL_LIMIT`

---

## How budget_guard.sh uses this file

`budget_guard.sh` reads the active agent name from the environment variable `CLAUDE_CURRENT_AGENT` (set by the orchestrator before dispatching each agent). If set, it applies the per-agent hard limit. If unset, it falls through to the daily aggregate check only.

To enforce per-agent limits, the orchestrator must export:
```bash
export CLAUDE_CURRENT_AGENT=coder  # before dispatching Coder agent
```
