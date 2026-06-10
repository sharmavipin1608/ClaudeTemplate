# ADR-0011: Stack-Specific Overlays for Conventions and Agent Definitions

**Status:** Accepted
**Date:** 2026-06-09

## Context

The template's agent definitions (Coder, Tester, Security) and `CONVENTIONS.md` are language-agnostic by default. A Python project and a Node.js project need different linting commands, test runners, import conventions, and security checks. Before PR #51, every team bootstrapping the template had to manually edit agent definitions and conventions for their stack — a tedious step that was easy to skip, leaving agents with generic guidance that produced lower-quality output.

Two options for stack-specific guidance:
1. **Separate agent file sets per stack** — e.g. `agents/python/coder.md`, `agents/nodejs/coder.md`. Complete but creates maintenance burden: every change to the base Coder logic requires updating N stack variants.
2. **Overlay files merged at bootstrap** — base agent definitions stay generic; stack-specific additions are appended at bootstrap time. Single source of truth for base logic; stack differences isolated to small overlay files.

## Decision

Overlays are stored in two locations:
- `agents/overlays/<stack>.md` — appended to `agents/coder.md`, `agents/tester.md`, and `agents/security.md` at bootstrap
- `conventions/<stack>.md` — appended to `CONVENTIONS.md` at bootstrap

Bootstrap Step 3b auto-detects the stack from `TECH_STACK` (set by the user in Step 1). If a matching overlay exists, bootstrap asks for confirmation and merges. If the auto-detection produces no match, the user is prompted to choose manually.

Initial overlays ship for `python` and `nodejs`. New stacks require adding two files: `agents/overlays/<stack>.md` and `conventions/<stack>.md`.

The merge is an append with a `---` separator, not a deep merge. The overlay cannot override base agent rules — it can only add stack-specific commands, patterns, and examples. This is intentional: base rules (TDD cycle, JSON envelope output, security gate behaviour) must not be suppressible by a stack overlay.

## Alternatives considered

- **Per-stack agent file sets:** Maximum flexibility but 3× maintenance burden per new stack. Changes to base Coder logic require editing every stack variant. Rejected.
- **Runtime stack detection (agent reads TECH_STACK from core.md and self-adapts):** Puts the intelligence in the agent prompt rather than the template. Works but produces longer, more complex agent prompts that are harder to audit. Rejected.
- **User edits agent files manually after bootstrap:** The status quo before this PR. High friction; frequently skipped. Rejected.

## Consequences

- An overlay cannot remove or override base agent instructions — only add to them. If a stack requires a fundamentally different approach (e.g. a language with no conventional test runner), the overlay cannot express that; the user must edit the base file.
- Bootstrap applies overlays once, permanently. If the stack changes mid-project (uncommon but possible), the old overlay content remains appended and must be manually cleaned up.
- Overlays are appended during bootstrap, so they move to `.claude/agents/` alongside the base definitions after Step 7. The original `agents/overlays/` directory in the template is not present in bootstrapped projects.

## Revisit trigger

When more than 5 stacks are supported, consider whether append-only overlays are sufficient or whether a proper merge/inheritance model is needed.
