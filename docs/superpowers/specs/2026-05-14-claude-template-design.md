# ClaudeTemplate — Design Spec
**Date:** 2026-05-14
**Status:** Approved

---

## Overview

A reusable GitHub template that ships a fully wired multi-agent Claude Code orchestration system. Every new project created from this template inherits the agent pipeline, memory system, hooks, and conventions out of the box — ready to use on day one.

**Approach:** Static snapshot (Approach 1). Each new project gets a full copy at creation time. No ongoing connection back to the template. Simple, isolated, zero maintenance overhead.

---

## 1. Repository Structure

```
ClaudeTemplate/
├── .claude/
│   └── settings.json              # hook wiring + budget + model config
├── agents/
│   ├── AGENTS.md                  # registry + routing rules
│   ├── researcher.md
│   ├── coder.md
│   ├── reviewer.md
│   ├── tester.md
│   ├── security.md
│   ├── git.md
│   ├── memory.md                  # first-class agent
│   ├── changelog.md
│   └── writer.md
├── skills/
│   ├── coding-patterns.md         # generic, not stack-specific
│   ├── api-design.md
│   ├── test-strategy.md
│   ├── git-commit.md
│   └── security-rules.md
├── memory/
│   ├── core.md                    # project identity, always loaded
│   ├── facts.md                   # tagged declarative facts
│   ├── scratchpad.md              # ephemeral working context
│   ├── session_checkpoint.md      # session recovery file
│   └── episodic/                  # daily logs (YYYY-MM-DD.md)
├── hooks/
│   ├── pre_task.sh
│   ├── post_task.sh
│   ├── log_tool.sh
│   ├── budget_guard.sh
│   └── on_error.sh
├── logs/
│   ├── tool_calls.log
│   ├── token_usage.log
│   └── traces/
├── tools/
│   ├── memory_read.py
│   ├── memory_write.py
│   └── search.py
├── scripts/
│   └── new-project.sh             # lives at ~/Projects/ on local machine
├── docs/
│   └── superpowers/
│       └── specs/                 # design docs live here
├── CLAUDE.md                      # orchestrator instructions
├── AGENTS.md                      # top-level agent registry
├── TASKS.md                       # current task queue
├── CONVENTIONS.md                 # coding style + project norms (living doc)
├── CHANGELOG.md
├── bootstrap.sh                   # project setup wizard
└── README_TEMPLATE.md             # base for new project READMEs
```

---

## 2. Memory System

### Five memory files

| File | Role | Lifecycle |
|---|---|---|
| `memory/core.md` | Project identity — name, stack, description, key people | Written by bootstrap.sh, rarely changes |
| `memory/facts.md` | Tagged declarative facts | Appended by memory agent, marked `[stale]` not deleted |
| `memory/scratchpad.md` | Ephemeral working context for current task | Written by orchestrator, cleared by memory agent after task |
| `memory/session_checkpoint.md` | Session recovery — last task, decisions, open questions, next steps | Written by memory agent after every task |
| `memory/episodic/YYYY-MM-DD.md` | Daily log of what happened and why | Written by memory agent at session end |

### facts.md format
```
[domain] fact about the project — YYYY-MM-DD
[auth] JWT secret rotates every 24h — 2026-05-14
[database] PostgreSQL 15, schema in /db/schema.sql — 2026-05-14
[stale][auth] Originally used sessions — replaced with JWT 2026-05-14
```

### Session recovery flow
When a new Claude session opens:
1. Orchestrator reads `memory/session_checkpoint.md` — "here's where we left off"
2. Greps `facts.md` for relevant `[domain]` tags — "here's what we know"
3. Reads `memory/core.md` — "here's what this project is"
4. Continues work — no context lost across session boundaries

### Memory retrieval strategy
- **Phase 1 (now):** Tag-based grep via `memory_read.py`
- **Phase 2 (facts > 100 entries):** ChromaDB vector search
- **Phase 3 (long-running projects):** Dedicated memory agent with vector store

---

## 3. Agent Pipeline

```
Researcher → Coder → Reviewer → Tester → Security → Git → Memory → Changelog
```

Writer runs on demand outside the main pipeline.

### Agent responsibilities

**`researcher.md`**
- Triggered: unknown domain, technology, or requirement
- Reads: task + `core.md` + relevant `facts.md` tags
- Outputs: findings → new tagged entries in `facts.md`
- Rule: facts and context only — no code, no opinions

**`coder.md`**
- Triggered: any implementation task
- Reads: task + `scratchpad.md` + `CONVENTIONS.md` + `skills/coding-patterns.md`
- Follows TDD at unit level: failing test → implement → refactor
- Outputs: code + unit tests
- Rule: stop and flag ambiguity to orchestrator — never assume

**`reviewer.md`**
- Triggered: after coder completes
- Reads: diff + `CONVENTIONS.md` + `skills/api-design.md`
- Outputs: `PASS` or fix list + convention candidates
- Rule: separates "must fix" (blocks pipeline) from "suggested" (→ CONVENTIONS.md)

**`tester.md`**
- Triggered: after reviewer PASS
- Reads: code + `CONVENTIONS.md` + `skills/test-strategy.md`
- Writes integration tests, edge cases, acceptance criteria
- Outputs: tests + full suite results
- Rule: all tests must pass before handoff to security

**`security.md`**
- Triggered: after tester
- Reads: diff + `skills/security-rules.md`
- Outputs: `PASS` or `BLOCKERS`
- Rule: hard gate — never skipped, `BLOCKERS` stops pipeline completely

**`git.md`**
- Triggered: after security PASS
- Reads: diff + `skills/git-commit.md` + `CONVENTIONS.md` (git section)
- Outputs: commit created + pushed
- Rule: follow commit conventions, never force push

**`memory.md`** ← first-class agent
- Triggered: after git (pipeline) + ad-hoc on any significant decision
- Reads: task output + `scratchpad.md` + `facts.md` + `CONVENTIONS.md`
- Outputs:
  - New tagged entries → `facts.md`
  - Updated `session_checkpoint.md`
  - Entry → today's `episodic/YYYY-MM-DD.md`
  - `scratchpad.md` cleared
  - Convention candidates flagged to orchestrator
- Rule: always write checkpoint; mark facts `[stale]` never delete

**`changelog.md`**
- Triggered: end of day or end of sprint
- Reads: `git log` + today's episodic log
- Outputs: `CHANGELOG.md` updated, grouped by feature
- Rule: write for a human reading months later — not a git log dump

**`writer.md`**
- Triggered: when docs are explicitly needed
- Reads: task + `core.md` + relevant code + `CONVENTIONS.md` (docs section)
- Outputs: markdown documentation
- Rule: no implementation, docs only

---

## 4. TDD + Superpowers Integration

The superpowers plugin and the custom agent system operate at different levels:

| Layer | Behavior |
|---|---|
| Orchestrator (main session) | Uses superpowers skills: brainstorming, writing-plans, executing-plans, verification-before-completion |
| Sub-agents (dispatched) | Skip skills via `<SUBAGENT-STOP>` — focused, isolated, no overhead |

**TDD is preserved:** The coder agent follows TDD principles internally (red → green → refactor at unit level). The tester agent adds an independent layer of integration and acceptance tests on top. The superpowers TDD skill informs the coder agent's prompt design but is not invoked at runtime by sub-agents.

---

## 5. CONVENTIONS.md

A living document — not a one-time setup artifact.

**Bootstrap.sh generates:** Well-structured file with generic defaults and `# TODO` markers. First task in `TASKS.md` is always: "Review and fill in CONVENTIONS.md."

**Actively maintained by:**
- **Reviewer agent:** flags violations AND suggests new convention entries when patterns emerge
- **Memory agent:** promotes decisions from scratchpad to CONVENTIONS.md candidates
- **Orchestrator:** approves and writes promoted conventions

**Sections:**
- Code Style (naming, formatting, language patterns)
- Architecture (folder structure, patterns to use/avoid)
- Testing (unit vs. integration, coverage expectations)
- Git (branch naming, commit style, PR size)
- API/Interface Design (request/response structure, error format)
- Agent Rules (project-specific must-do / must-not-do)
- Docs (documentation style and what to document)

---

## 6. Bootstrap Flow

### Two entry points, same end state

**Path A — GitHub:** "Use this template" → clone new repo → run `bootstrap.sh`

**Path B — Local script:** Run `~/Projects/new-project.sh` → enter project name → script clones template → auto-runs `bootstrap.sh`

### `new-project.sh` (lives at `~/Projects/`)
```bash
# Asks for project name
# git clone <template-repo-url> ~/Projects/<name>
# cd ~/Projects/<name>
# ./bootstrap.sh
```

### `bootstrap.sh` steps
1. Prompt: project name (pre-filled from folder name), tech stack, one-line description, GitHub visibility
2. Replace placeholders: `{{PROJECT_NAME}}`, `{{TECH_STACK}}`, `{{DESCRIPTION}}`, `{{DATE}}`
3. Populate `memory/core.md` with project identity
4. Write `CONVENTIONS.md` with generic defaults + TODO markers
5. Write `TASKS.md` with first task: "Review and fill in CONVENTIONS.md"
6. Generate `README.md` from `README_TEMPLATE.md`
7. Remove bootstrap artifacts: delete `README_TEMPLATE.md`, `rm -rf .git`
8. `git init` → initial commit: `"chore: init project from ClaudeTemplate"`
9. Prompt: "Create GitHub repo? (y/n)" → if yes: `gh repo create <name> --private` → `git push`

---

## 7. Hooks

Wired in `.claude/settings.json`, run automatically on every tool call.

| Hook | Trigger | What it does |
|---|---|---|
| `pre_task.sh` | PreToolUse | Reads checkpoint, greps relevant facts, loads scratchpad |
| `post_task.sh` | PostToolUse | Logs tool call, flags decisions, updates scratchpad |
| `log_tool.sh` | Pre + PostToolUse | Appends `timestamp \| AGENT \| TOOL \| task_id` to `logs/tool_calls.log` |
| `budget_guard.sh` | PreToolUse | Checks daily token spend; warns or halts based on `BUDGET_MODE` |
| `on_error.sh` | Stop (on failure) | Logs error, writes to scratchpad, requeues task in TASKS.md with `[FAILED]` |

---

## 8. Python Tools

All stdlib only — no external dependencies.

**`memory_read.py`**
- `--tag auth` — grep facts.md by tag(s), skip stale by default
- `--file core|scratchpad|checkpoint` — read a full memory file
- `--include-stale` — include stale entries

**`memory_write.py`**
- `--tag auth --fact "..."` — append tagged entry with timestamp to facts.md
- `--stale "old fact text"` — mark existing entry as stale
- `--checkpoint "..."` — overwrite session_checkpoint.md

**`search.py`**
- Searches across memory files for a query string
- `--files facts,episodic` — limit scope
- `--fuzzy` — approximate matching via difflib
- Returns: file, line number, matched text, surrounding context

---

## 9. `settings.json`

```json
{
  "hooks": {
    "PreToolUse": [
      { "command": "bash hooks/pre_task.sh" },
      { "command": "bash hooks/budget_guard.sh" },
      { "command": "bash hooks/log_tool.sh $TOOL_NAME $AGENT_NAME" }
    ],
    "PostToolUse": [
      { "command": "bash hooks/post_task.sh" },
      { "command": "bash hooks/log_tool.sh $TOOL_NAME $AGENT_NAME" }
    ],
    "Stop": [
      { "command": "bash hooks/on_error.sh" }
    ]
  },
  "budget": {
    "daily_token_limit": 100000,
    "mode": "warn"
  },
  "memory": {
    "checkpoint_on_task_complete": true,
    "stale_facts_after_days": 30
  },
  "agents": {
    "default_model": "claude-sonnet-4-6",
    "orchestrator_model": "claude-opus-4-7"
  }
}
```

---

## 10. Key Design Decisions

| Decision | Rationale |
|---|---|
| Static snapshot (no submodules) | Zero maintenance overhead; template improvements are conscious pull decisions |
| Memory agent is first-class in pipeline | Session continuity is too critical to leave to hooks alone |
| `session_checkpoint.md` as recovery file | Survives session close; new sessions reconstruct context from files alone |
| Coder does TDD at unit level, tester adds integration layer | Preserves TDD discipline while gaining independent test review |
| CONVENTIONS.md is a living document | Conventions evolve with the project; system actively curates them |
| Orchestrator uses Opus, sub-agents use Sonnet | Reasoning power where planning happens; speed + cost efficiency for execution |
| `BUDGET_MODE=warn` default | Never block mid-task; switch to `halt` for strict enforcement |
| Skills lazy-loaded per agent | No prompt bloat; each agent gets only what it needs |
