# Agent Registry

Quick routing reference for the orchestrator. Full agent prompts in `agents/`.

## Pipeline Order

### Per-Task Pipeline
Researcher → Coder → Reviewer → Tester → Security → Git → Memory

### End-of-Feature Pipeline
DevOps → Memory

> Changelog runs separately at end of day or end of sprint — not part of any pipeline.

## Pipeline Variants

| Variant | Agents | When |
|---|---|---|
| Full (default, per task) | Researcher → Coder → Reviewer → Tester → Security → Git → Memory | FORCE_FULL verdict, or orchestrator judges complex |
| Fast-Track (per task) | Coder → Tester → Security → Git → Memory | AMBIGUOUS verdict + orchestrator judges simple |
| End-of-Feature | DevOps → Memory | Memory signals `Queue: DRAINED` after the final task |

Security and Memory are never skippable in per-task variants. DevOps is never skippable in the end-of-feature pipeline.

## When to Dispatch Each Agent

| Agent | File | Trigger | Tool Scope |
|---|---|---|---|
| Researcher | `agents/researcher.md` | Unknown domain, new technology, need external context before coding | Read, WebFetch, WebSearch, Bash (grep/find only) |
| Coder | `agents/coder.md` | Any implementation task — always follows TDD | Read, Write, Edit, Bash (test runner and linter only) |
| Reviewer | `agents/reviewer.md` | After Coder completes — checks conventions and correctness | Read only |
| Tester | `agents/tester.md` | After Reviewer PASS — adds integration and acceptance tests | Read, Write, Bash (test runner only) |
| Security | `agents/security.md` | After Tester — hard gate, pipeline stops on BLOCKERS | Read, Bash (grep and diff only) |
| Git | `agents/git.md` | After Security PASS — commits and pushes | Bash (git commands only) |
| DevOps | `agents/devops.md` | After all TASKS.md tasks are `completed` (Memory signals `Queue: DRAINED`) — polls CI for the feature branch, runs smoke test | Bash (gh CLI and CI polling only), Read |
| Memory | `agents/memory.md` | After DevOps PASS — marks task `completed` in TASKS.md, updates facts, checkpoint, episodic log | Read, Write, Bash (memory_write.py and grep only) |
| Changelog | `agents/changelog.md` | End of day or end of sprint | Read, Write, Bash (git log only) |
| Writer | `agents/writer.md` | (1) Plan approved → bulk-populate TASKS.md before coding; (2) Documentation explicitly needed | Read, Write, Bash (read-only only) |

## Hooks That Affect Dispatch

| Hook | Event | Effect on pipeline |
|---|---|---|
| `hooks/telegram_approval.py` | PreToolUse (Bash only) | Routes Bash permission prompts to Telegram when `~/.claude/telegram_active` flag file exists. Toggle with `telegram` command. Falls through to native dialog if flag absent or credentials missing. |
| `hooks/classify_task.sh` | PreToolUse | Writes `FORCE_FULL` or `AMBIGUOUS` to `/tmp/task_mode` — orchestrator reads this to choose full vs fast-track pipeline |

## Dispatch Rules

1. Pass only the context the agent needs — no full history
2. Always include the relevant skill file path in the dispatch
3. Security agent is a hard gate — never skip it, never batch it with Git; on BLOCKERS mark task `blocked` in TASKS.md
4. DevOps agent is a hard gate — runs in the end-of-feature pipeline only, not per task; on CI FAILED mark all feature tasks `blocked` in TASKS.md
5. Memory agent runs after every completed per-task pipeline run, and again at end-of-feature after DevOps PASS — it owns marking tasks `completed` in TASKS.md
6. Orchestrator marks a task `in_progress` in TASKS.md at dispatch time — Memory agent marks it `completed` at the end
7. Writer runs outside the main pipeline — always spawn it after plan approval to populate TASKS.md before handing off to Coder
8. End-of-feature: when Memory signals `Queue: DRAINED`, orchestrator dispatches DevOps with branch name + all feature commit SHAs, then Memory for a final checkpoint
9. Log the pipeline variant and reason for every task — format:
   `timestamp | ORCHESTRATOR | PIPELINE:full | REASON:auth file touched`
