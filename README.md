# ClaudeTemplate

Multi-Agent Claude Code Orchestration, Ready to Use.

ClaudeTemplate is a GitHub repository template that ships a complete multi-agent orchestration system for Claude Code. Clone it, run one script, and your new project has structured agents, persistent memory, automated hooks, skill files, and Python tooling — all wired together from day one.

**[→ Architecture Reference](https://sharmavipin1608.github.io/ClaudeTemplate/)** — visual overview of the full system: pipeline variants, memory tiers, hooks, and all agents in detail.

---

## Prerequisites

ClaudeTemplate requires the **superpowers plugin** for Phase 0 planning (brainstorming and writing-plans skills). Install it once per machine before using any project bootstrapped from this template.

**Official Claude marketplace (recommended):**
```bash
/plugin install superpowers@claude-plugins-official
```

**Superpowers marketplace (alternative):**
```bash
/plugin marketplace add obra/superpowers-marketplace
/plugin install superpowers@superpowers-marketplace
```

Superpowers provides the `brainstorming` and `writing-plans` skills used in Phase 0. The `executing-plans` and `subagent-driven-development` skills are intentionally blocked for projects using this template — the orchestrator pipeline replaces them.

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
| **Agent definitions** | 10 agents: Researcher, Coder, Reviewer, Tester, Security, Git, DevOps, Memory, Changelog, Writer |
| **Memory system** | `core.md`, `facts.md`, `scratchpad.md`, `session_checkpoint.md`, episodic logs |
| **Hooks** | Pre/post task hooks, tool call logger, budget guard, error handler |
| **Skill files** | Java/coding patterns, API design, test strategy, git commit conventions, security rules |
| **Python tools** | `memory_read.py`, `memory_write.py`, `search.py` |
| **Conventions** | `CONVENTIONS.md` — living document for team norms |
| **Orchestration instructions** | `CLAUDE.md` — master instructions that wire everything together |

---

## Agent Pipeline

### Phase 0 — Planning (once per feature, requires superpowers plugin)
```
brainstorming skill → writing-plans skill → Writer agent → TASKS.md
```
brainstorming explores requirements and produces a spec doc. writing-plans reads the spec and produces a detailed implementation plan. The Writer agent converts the plan into TASKS.md entries. Both docs are saved under `docs/superpowers/` and have user review gates before proceeding.

### Full Pipeline (default, per task)
```
Researcher → Coder → Reviewer → Tester → Security → Git → Memory
```

### Fast-Track Pipeline (per task)
```
Coder → Tester → Security → Git → Memory
```
Skipped: Researcher (domain already known), Reviewer (scope too small).
Never skipped: Security (hard gate), Memory (system coherence).

### End-of-Feature Pipeline (runs once when all tasks complete)
```
DevOps → Memory
```
Triggered when the Memory agent signals `Queue: DRAINED` after the final task. DevOps polls CI for the feature branch, runs the smoke test, and either clears the feature or marks all tasks `blocked`.

> Changelog runs separately at end of day or end of sprint — not part of any pipeline.

The orchestrator reads `/tmp/task_mode` written by `hooks/classify_task.sh` to decide which per-task pipeline to use. Each agent runs in isolation — no full conversation history passed between them. Security is a hard gate per task. DevOps is a hard gate once per feature.

| Agent | Trigger | Output |
|---|---|---|
| `researcher` | Unknown domain, need context | findings → facts.md |
| `coder` | Implementation task | code only |
| `reviewer` | After coder | pass / fix list |
| `tester` | After reviewer | tests written + run |
| `security` | After tester | PASS or BLOCKERS |
| `git` | After security PASS | commit + push |
| `devops` | After all tasks complete (queue drained) | CI PASS or CI FAILED + smoke test result |
| `memory` | After git (per task) + after devops (end-of-feature) | marks task `completed` in TASKS.md + updated memory files |
| `changelog` | End of day | CHANGELOG.md updated |
| `writer` | (1) Plan approved → populate TASKS.md; (2) docs needed | populated TASKS.md or markdown docs |

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
| `hooks/session_override.sh` | Session start | Print pipeline override notice — blocks `executing-plans` and `subagent-driven-development`, permits `brainstorming` and `writing-plans` for Phase 0 |
| `hooks/telegram_approval.py` | Before Bash tool calls | Route Bash permission prompts to Telegram for remote approval — see [Telegram Approval](#telegram-approval) |
| `hooks/pre_task.sh` | Before each tool | Inject `core.md`, `session_checkpoint.md`, and `scratchpad.md` into context once per session |
| `hooks/classify_task.sh` | Before each tool (skips read-only tools) | Classify task complexity; write `FORCE_FULL` or `AMBIGUOUS` to `/tmp/task_mode` |
| `hooks/budget_guard.sh` | Before each tool | Count daily tool calls — halt or warn if over limit |
| `hooks/log_tool.sh` | Before each tool | Append `timestamp \| tool_name` to `logs/tool_calls.log` |
| `hooks/log_agent.sh` | Called by orchestrator | Append `timestamp \| agent \| START\|END` to `logs/agent_calls.log` |
| `hooks/post_task.sh` | After each tool | Append to episodic log, update facts if needed, clear scratchpad |
| `hooks/on_error.sh` | On failure | Log failure, requeue task in TASKS.md |

---

## Telegram Approval

Long pipeline runs (10+ tasks) generate many Bash permission prompts. Instead of sitting at your keyboard to approve each one, the Telegram approval hook lets you approve or deny from your phone.

**What you get on your phone:**
```
🔔 Permission Request — MyProject

🔧 Bash

bash hooks/log_agent.sh Git END 2>/dev/null;
bash hooks/log_agent.sh DevOps START 2>/dev/null ...

📝 Log Git END/DevOps START and poll CI

[ ✅ Allow ]   [ ❌ Deny ]
```

Tap a button — the message updates in place and the pipeline resumes. No timeout — it waits as long as you need, matching Claude Code's native behavior.

**Setup (2 minutes):**

1. Message `@BotFather` on Telegram → `/newbot` → copy the token
2. Message `@userinfobot` → copy your numeric chat ID
3. Save credentials (global, works across all projects):
   ```bash
   cp .env.telegram.example ~/.claude/telegram.env
   # fill in TELEGRAM_BOT_TOKEN and TELEGRAM_CHAT_ID
   ```
4. Install the toggle command:
   ```bash
   ln -sf "$(pwd)/hooks/telegram_toggle.sh" ~/.local/bin/telegram
   ```
5. Send your bot any message on Telegram to open the conversation

**Toggling on/off:**
```bash
telegram   # → Telegram approval: ON  — Bash approvals will route to Telegram
telegram   # → Telegram approval: OFF — using native Claude Code dialogs
```

Run `telegram` before stepping away from your machine, run it again when you're back. Takes effect immediately — no Claude Code restart needed.

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
│   ├── session_override.sh    # SessionStart: pipeline override for superpowers conflict
│   ├── telegram_approval.py   # PreToolUse (Bash): remote approval via Telegram
│   ├── telegram_toggle.sh     # CLI toggle: `telegram` on/off command
│   ├── pre_task.sh
│   ├── post_task.sh
│   ├── classify_task.sh
│   ├── log_tool.sh
│   ├── log_agent.sh
│   ├── on_error.sh
│   └── budget_guard.sh
├── logs/
│   ├── tool_calls.log
│   ├── agent_calls.log
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

**Model tiering.** Models are assigned explicitly per agent spawn — the `agents.default_model` setting in `.claude/settings.json` is metadata only and is not read by Claude Code at dispatch time.

| Agent | Model | Reason |
|---|---|---|
| Orchestrator | Opus | Planning, routing, pipeline decisions |
| Researcher, Coder, Reviewer, Tester, Security, Writer | Sonnet | Reasoning required |
| Git, Memory, Changelog | Haiku | Mechanical tasks only |

**Agent output contracts.** Each agent definition includes a strict `## Output to orchestrator` section capping its return message at 2–4 lines. This prevents the orchestrator's context from growing unbounded across a multi-task session — without it, full agent responses accumulate and can reach 170k+ tokens.

**CONVENTIONS.md as the living contract.** All team norms — naming, error handling, commit style, test requirements — live in one place. The Memory agent is responsible for keeping it current. New engineers read one file to get up to speed.
