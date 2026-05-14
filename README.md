# ClaudeTemplate

Multi-Agent Claude Code Orchestration, Ready to Use.

ClaudeTemplate is a GitHub repository template that ships a complete multi-agent orchestration system for Claude Code. Clone it, run one script, and your new project has structured agents, persistent memory, automated hooks, skill files, and Python tooling — all wired together from day one.

**[→ Architecture Reference](docs/ARCHITECTURE.html)** — visual overview of the full system: pipeline variants, memory tiers, hooks, and all agents in detail.

---

## Quick Start

### Path A — GitHub template

1. Click **"Use this template"** on the ClaudeTemplate GitHub page
2. Clone your new repository
3. Run `./bootstrap.sh`

### Path B — Local convenience script

```bash
# Install once
cp scripts/new-project.sh ~/Projects/new-project.sh
chmod +x ~/Projects/new-project.sh
# Edit the script and set TEMPLATE_REPO_URL to your ClaudeTemplate fork URL

# Use every time you start a new project
~/Projects/new-project.sh
```

Both paths end with `./bootstrap.sh`, which asks a few questions and configures everything.

---

## What You Get

| Category | Contents |
|---|---|
| **Agent definitions** | 8 agents: Researcher, Coder, Reviewer, Tester, Security, Git, Memory, Changelog |
| **Memory system** | `core.md`, `facts.md`, `scratchpad.md`, `session_checkpoint.md`, episodic logs |
| **Hooks** | Pre/post task hooks, tool call logger, budget guard, error handler |
| **Skill files** | Java/coding patterns, API design, test strategy, git commit conventions, security rules |
| **Python tools** | `memory_read.py`, `memory_write.py`, `search.py` |
| **Conventions** | `CONVENTIONS.md` — living document for team norms |
| **Orchestration instructions** | `CLAUDE.md` — master instructions that wire everything together |

---

## Agent Pipeline

```
Researcher → Coder → Reviewer → Tester → Security → Git → Memory → Changelog
```

Each agent runs in isolation. The orchestrator passes only the context each agent needs — no full conversation history. The Security agent is a hard gate: the pipeline stops if it returns blockers.

| Agent | Trigger | Output |
|---|---|---|
| `researcher` | Unknown domain, need context | findings → facts.md |
| `coder` | Implementation task | code only |
| `reviewer` | After coder | pass / fix list |
| `tester` | After reviewer | tests written + run |
| `security` | After tester | PASS or BLOCKERS |
| `git` | After security PASS | commit + push |
| `memory` | After git, on significant decisions | updated memory files |
| `changelog` | End of day | CHANGELOG.md updated |

---

## Memory System

| File | Role | Load strategy |
|---|---|---|
| `memory/core.md` | Project identity, stack, architecture | Always load — never changes |
| `memory/facts.md` | Tagged declarative facts | Grep by tag, never load fully |
| `memory/scratchpad.md` | Working context for current task | Load fully, wipe after each task |
| `memory/session_checkpoint.md` | Session recovery state | Load when resuming a paused session |
| `memory/episodic/YYYY-MM-DD.md` | Daily event logs | Load only for retros or debugging |

Facts are tagged for cheap retrieval:

```bash
grep "\[auth\]" memory/facts.md
grep "\[database\]" memory/facts.md
```

---

## Hooks

Hooks run automatically around every tool call. Defined in `.claude/settings.json`.

| Hook | Runs | Purpose |
|---|---|---|
| `hooks/pre_task.sh` | Before each tool | Load core.md, grep relevant facts, load scratchpad |
| `hooks/post_task.sh` | After each tool | Append to episodic log, update facts if needed, clear scratchpad |
| `hooks/log_tool.sh` | Before each tool | Append `timestamp \| AGENT \| TOOL` to `logs/tool_calls.log` |
| `hooks/budget_guard.sh` | Before each tool | Check daily token spend — halt if over limit |
| `hooks/on_error.sh` | On failure | Log failure, requeue task in TASKS.md |

---

## Python Tools

| Script | Description |
|---|---|
| `tools/memory_read.py` | Read a memory file by name, or grep facts.md by tag |
| `tools/memory_write.py` | Append or overwrite entries in memory files |
| `tools/search.py` | Fuzzy or exact search across all memory files |

Usage examples:

```bash
python tools/memory_read.py --tag auth
python tools/memory_read.py --file core
python tools/search.py "JWT" --fuzzy
```

---

## Bootstrap Walkthrough

`bootstrap.sh` runs 7 steps:

1. **Replace placeholders** — substitutes `{{PROJECT_NAME}}`, `{{TECH_STACK}}`, `{{DESCRIPTION}}`, `{{DATE}}`, `{{OWNER_EMAIL}}` across all `.md`, `.sh`, `.py`, and `.json` files
2. **Write `memory/core.md`** — creates the permanent project identity record
3. **Stamp `CONVENTIONS.md`** — adds a "Last reviewed" date
4. **Generate `README.md`** — copies and fills `README_TEMPLATE.md`, then deletes the template
5. **Remove bootstrap artifacts** — deletes `README_TEMPLATE.md`, `docs/superpowers/`, and `scripts/`
6. **Fresh git history** — removes the template's `.git`, runs `git init`, makes an initial commit
7. **Optional GitHub repo** — offers to create and push a GitHub repository via `gh`

---

## Installing new-project.sh

`scripts/new-project.sh` is a machine-level convenience wrapper. Install it once per machine:

```bash
cp scripts/new-project.sh ~/Projects/new-project.sh
chmod +x ~/Projects/new-project.sh
```

Open the script and set `TEMPLATE_REPO_URL` to your ClaudeTemplate fork:

```bash
TEMPLATE_REPO_URL="https://github.com/yourname/ClaudeTemplate.git"
```

Or export it as an environment variable before running:

```bash
export TEMPLATE_REPO_URL="https://github.com/yourname/ClaudeTemplate.git"
~/Projects/new-project.sh
```

The script clones the template into `~/Projects/<project-name>` and optionally runs `bootstrap.sh` immediately.

---

## Project Structure

```
my-project/
├── .claude/
│   └── settings.json          # hooks, permissions, budget config
├── agents/
│   ├── AGENTS.md              # agent registry and routing rules
│   ├── researcher.md
│   ├── coder.md
│   ├── reviewer.md
│   ├── tester.md
│   ├── security.md
│   ├── git.md
│   ├── memory.md
│   ├── changelog.md
│   └── writer.md
├── skills/
│   ├── coding-patterns.md
│   ├── api-design.md
│   ├── test-strategy.md
│   ├── git-commit.md
│   └── security-rules.md
├── memory/
│   ├── core.md                # permanent project identity
│   ├── facts.md               # tagged declarative facts
│   ├── scratchpad.md          # ephemeral working context
│   ├── session_checkpoint.md  # session recovery
│   └── episodic/              # daily logs
├── hooks/
│   ├── pre_task.sh
│   ├── post_task.sh
│   ├── log_tool.sh
│   ├── on_error.sh
│   └── budget_guard.sh
├── logs/
│   ├── tool_calls.log
│   ├── token_usage.log
│   └── traces/
├── tools/
│   ├── memory_read.py
│   ├── memory_write.py
│   └── search.py
├── scripts/
│   └── new-project.sh         # removed by bootstrap.sh
├── TASKS.md
├── AGENTS.md
├── CONVENTIONS.md
├── CHANGELOG.md
├── CLAUDE.md
├── README.md                  # generated from README_TEMPLATE.md by bootstrap.sh
└── README_TEMPLATE.md         # removed by bootstrap.sh
```

---

## Design Decisions

**Static snapshot, not live generation.** Agent definitions, skill files, and memory live in plain Markdown files checked into the repo. There is no framework, no config DSL, no build step. Any editor and any LLM can read them.

**Memory-first context injection.** Rather than re-summarizing the project in every prompt, agents pull from structured memory files. The orchestrator greps by tag rather than loading everything, keeping context windows lean.

**Model tiering.** The orchestrator runs on Claude Opus (reasoning-heavy planning). Sub-agents run on Claude Sonnet (fast, cost-effective execution). Set your preferred models in `.claude/settings.json`.

**CONVENTIONS.md as the living contract.** All team norms — naming, error handling, commit style, test requirements — live in one place. The Memory agent is responsible for keeping it current. New engineers read one file to get up to speed.
