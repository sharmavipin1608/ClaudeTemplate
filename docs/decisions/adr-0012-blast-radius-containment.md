# ADR-0012: Blast Radius Containment — Three-Layer Defence

**Status:** Accepted
**Date:** 2026-06-10

## Context

The pipeline dispatches agents that write files, commit code, and push to remote repositories. If any agent hallucinates or misbehaves — most critically the Security agent — the consequences can be irreversible: vulnerable code reaches a remote repo, incorrect facts pollute future agent prompts, or wrong architectural decisions get baked into committed code.

Three failure modes need different mitigations:

1. **Unknown risk** — no one has reasoned about what the worst case actually is, so it cannot be planned for
2. **Excessive agent reach** — agents have access to tools beyond their scope; a misbehaving agent can affect systems it was never supposed to touch
3. **No intervention point** — irreversible actions (git push) execute automatically with no human checkpoint

A single mechanism cannot address all three. Each requires a distinct layer.

## Decision

Blast radius is contained through three complementary layers, each targeting a different failure mode:

**Layer 1 — Documentation: know what's at stake (issue #63)**
Every agent definition includes a `## Blast Radius` section naming the concrete worst-case scenario if it hallucinates, and at least one containment mechanism that limits the damage. This is not operational — it produces no code change. Its purpose is to make risk legible so that future contributors understand what they are gating on and cannot accidentally weaken a gate without seeing the consequence written down next to it.

The Security agent's blast radius section explicitly marks it as the highest-risk gate: a hallucinated PASS results in a vulnerable diff being committed and pushed. This justifies why Security is never skippable, never batched, and never run in parallel with Git (see ADR-0002).

**Layer 2 — Scoping: limit agent reach (issue #56)**
Each agent definition includes a `## Tool Restrictions` section listing the tools it may and must not use. Claude Code does not enforce per-agent tool scoping at the harness level, so this is convention enforcement via the agent prompt. An agent prompt that explicitly prohibits Bash will rarely deviate; without the prohibition, there is no signal that deviation is wrong.

This limits the blast radius of a misbehaving agent to its intended scope — a Reviewer that cannot use Write cannot corrupt files even if its reasoning goes wrong.

**Layer 3 — Gate: stop the irreversible action (issue #64)**
The orchestrator prompts for human confirmation before dispatching the Git agent after a Security PASS. The gate shows task ID and files changed; the human confirms or denies. A denial marks the task `blocked` and stops the pipeline.

This is the only layer that can stop a Security hallucination after it happens. Layers 1 and 2 reduce the probability and scope of failure; Layer 3 is the last line of defence before code leaves the machine.

`CLAUDE_AUTO_PUSH=true` disables the gate for automated pipelines. The default is gated (opt-out, not opt-in).

## Why three layers instead of one

Each layer addresses a different failure mode and would leave gaps if applied alone:

- Layer 1 alone: documents risk but stops nothing
- Layer 2 alone: limits scope but a Security hallucination still pushes through
- Layer 3 alone: catches pushes but gives no context about *why* the push is risky without Layer 1, and does nothing for in-pipeline damage (wrong facts, bad code) that happens before the push

Together: contributors understand the stakes (Layer 1), agents cannot stray outside their scope (Layer 2), and a human can intervene before the point of no return (Layer 3).

## Alternatives considered

- **Single hard gate at Security only:** Strengthening Security's prompt doesn't prevent hallucination — it reduces frequency but cannot eliminate it. Rejected as sole mitigation.
- **Automated diff scanning before push (additional Security pass):** Running Security twice adds cost and latency without addressing the core problem that Security can hallucinate. Rejected.
- **No push gate, rely on PR review:** Code is already in the remote before review happens. Rejected — the whole point is to catch it before it leaves.

## Consequences

- Every agent file requires maintenance of both a `## Blast Radius` section and a `## Tool Restrictions` section. Adding a new agent requires filling both.
- The push gate adds a required human interaction in the default pipeline. Unattended/automated runs must set `CLAUDE_AUTO_PUSH=true` explicitly.
- Layer 2 (tool scoping) is convention-only until Claude Code supports per-agent tool scoping natively; if native scoping is added, the agent prompt restrictions should be replaced with harness-level enforcement and this ADR updated.

## Revisit trigger

Claude Code adds native per-agent tool permission scoping — Layer 2 switches from convention to enforcement and this ADR should be updated to reflect that.
