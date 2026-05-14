# Agent Registry

Quick routing reference for the orchestrator. Full agent prompts in `agents/`.

## Pipeline Order

Researcher → Coder → Reviewer → Tester → Security → Git → Memory → Changelog

## Pipeline Variants

| Variant | Agents | When |
|---|---|---|
| Full (default) | Researcher → Coder → Reviewer → Tester → Security → Git → Memory | FORCE_FULL verdict, or orchestrator judges complex |
| Fast-Track | Coder → Tester → Security → Git → Memory | AMBIGUOUS verdict + orchestrator judges simple |

Security and Memory are never skippable in either variant.

## When to Dispatch Each Agent

| Agent | File | Trigger |
|---|---|---|
| Researcher | `agents/researcher.md` | Unknown domain, new technology, need external context before coding |
| Coder | `agents/coder.md` | Any implementation task — always follows TDD |
| Reviewer | `agents/reviewer.md` | After Coder completes — checks conventions and correctness |
| Tester | `agents/tester.md` | After Reviewer PASS — adds integration and acceptance tests |
| Security | `agents/security.md` | After Tester — hard gate, pipeline stops on BLOCKERS |
| Git | `agents/git.md` | After Security PASS — commits and pushes |
| Memory | `agents/memory.md` | After Git — updates facts, checkpoint, episodic log |
| Changelog | `agents/changelog.md` | End of day or end of sprint |
| Writer | `agents/writer.md` | When documentation is explicitly needed |

## Dispatch Rules

1. Pass only the context the agent needs — no full history
2. Always include the relevant skill file path in the dispatch
3. Security agent is a hard gate — never skip it
4. Memory agent runs after every completed pipeline task
5. Writer runs on demand, outside the main pipeline
6. Log the pipeline variant and reason for every task — format:
   `timestamp | ORCHESTRATOR | PIPELINE:full | REASON:auth file touched`
