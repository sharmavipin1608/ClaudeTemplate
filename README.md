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
| **Skill files** | coding-patterns, reliability-patterns, api-design, test-strategy, security-rules, git-commit + stack overlays |
| **Contracts** | JSON schemas for all 8 agents; `validate_output.sh` enforces them at every handoff |
| **Pipeline logging** | `logs/pipeline.jsonl` — typed JSONL run trace; `pipeline_analytics.py` + `trace_analyze.py` for analysis |
| **Python tools** | `memory_read.py`, `memory_write.py`, `search.py` |
| **Conventions** | `CONVENTIONS.md` — living document for team norms |
| **Orchestration instructions** | `CLAUDE.md` — master instructions that wire everything together |

---

## Stack Support

ClaudeTemplate ships with built-in support for these stacks. When you run `bootstrap.sh`, it detects your stack from the tech stack you enter and merges the right overlays automatically.

| Stack | Auto-detected from | Coverage |
|---|---|---|
| **Python** | `python`, `django`, `fastapi`, `flask`, `pytest` | Reviewer checks, agent rules (coder/tester/security), CONVENTIONS.md overlay |
| **Node.js / TypeScript** | `node`, `nodejs`, `typescript`, `express`, `next`, `react`, `vue` | Reviewer checks, agent rules (coder/tester/security), CONVENTIONS.md overlay |
| **Java** | `java`, `spring`, `gradle`, `maven`, `junit` | Reviewer checks, agent rules (coder/tester/security), CONVENTIONS.md overlay |

"Reviewer checks" means `skills/overlays/reliability-<stack>.md` — syntax-level checks the Reviewer agent applies to every diff, on top of the base `reliability-patterns.md`.

"Agent rules" means `agents/overlays/<stack>.md` — stack-specific commands and patterns merged into the Coder, Tester, and Security agent definitions at bootstrap time.

"CONVENTIONS.md overlay" means `conventions/<stack>.md` — stack-specific coding standards merged into `CONVENTIONS.md` for your team to read.

If your stack is not listed, `bootstrap.sh` will ask you to choose one manually or skip. **To add full support for a new stack**, see [docs/adding-a-stack.md](docs/adding-a-stack.md) — it is a five-file checklist that takes about 30 minutes.

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

The orchestrator reads `.claude/tmp/task_mode` written by `hooks/classify_task.sh` to decide which per-task pipeline to use. Each agent runs in isolation — no full conversation history passed between them. Security is a hard gate per task. DevOps is a hard gate once per feature.

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
| `hooks/session_override.sh` | SessionStart | Print Phase 0 skill override notice — blocks `executing-plans` and `subagent-driven-development`, permits `brainstorming` and `writing-plans` |
| `hooks/session_context.sh` | SessionStart | Inject `core.md`, `session_checkpoint.md`, `scratchpad.md` into context; emit `session_start` to `pipeline.jsonl`; warn on cross-session orchestration |
| `hooks/telegram_approval.py` | Before Bash tool calls | Route Bash permission prompts to Telegram — Allow/Deny buttons, no timeout |
| `hooks/classify_task.sh` | Before each tool (skips read-only) | Write `FORCE_FULL` or `AMBIGUOUS` to `.claude/tmp/task_mode`. FORCE_FULL on: auth/payment/schema/infra paths; task tags `[api]` `[auth]` `[security]` `[database]`; SDK imports or network I/O exception handlers in diff; retry/backoff/poll keywords in task description |
| `hooks/budget_guard.sh` | Before each tool | Enforce daily aggregate limit and per-agent limits from `contracts/pipeline-slos.md` — halt (exit 2) or warn |
| `hooks/log_tool.sh` | Before each tool | Append `timestamp \| tool_name` to `logs/tool_calls.log`; emit `tool_call` to `logs/pipeline.jsonl` when a run is active |
| `hooks/git_guard.sh` | Before Bash tool calls | Block `git commit` / `git push` unless `pipeline_state.json` shows `current_step == "git"` |
| `hooks/log_agent.sh` | Called by orchestrator | Record agent START/END to `logs/agent_calls.log` + `pipeline.jsonl`; set `agent_active` flag for tool attribution |
| `hooks/init_pipeline_state.sh` | Called by orchestrator | Create `pipeline_state.json`; emit `pipeline_init` with run_id and classifier verdict |
| `hooks/advance_pipeline_state.sh` | Called by orchestrator | Update `current_step`; emit `pipeline_complete` when run finishes |
| `hooks/validate_output.sh` | Called by orchestrator | Validate agent envelope against `contracts/<agent>.json`; stamp real wall-clock timestamp; append to `pipeline.jsonl` |
| `hooks/on_error.sh` | Stop | Clear idle timestamps; write recovery note to `scratchpad.md` if pipeline was mid-run |

---

## Agent Contracts

Every agent returns a JSON envelope. `hooks/validate_output.sh` validates each envelope against `.claude/contracts/<agent>.json` before routing to the next step. An invalid envelope halts the pipeline and marks the task `blocked`.

| Agent | Verdict(s) | Required payload fields |
|---|---|---|
| `researcher` | DONE | — |
| `coder` | DONE | `files_changed`, `spec_deviations` (`[]` = spec matched exactly) |
| `reviewer` | PASS, FIX_REQUIRED | — (reason required on FIX_REQUIRED) |
| `tester` | PASS, FAIL | `test_counts`, `acceptance_criteria_covered`, `edge_cases_covered` |
| `security` | PASS, BLOCKED | `findings` (`[]` = clean; reason required on BLOCKED) |
| `git` | COMMITTED, PUSH_FAILED | — (reason required on PUSH_FAILED) |
| `devops` | PASS, CI_FAILED | — (Step 0 checks `git remote -v`; no remote → CI_FAILED, never PASS) |
| `memory` | DONE, DRAINED | — |

The validator stamps the real wall-clock `timestamp` on every envelope — agents do not supply it. Per-agent soft/hard tool call budgets live in `contracts/pipeline-slos.md`.

---

## Structured Pipeline Logging

`logs/pipeline.jsonl` is the primary observability artifact. Every run emits a typed sequence of events, all carrying `run_id`:

| Event | Emitted by | When |
|---|---|---|
| `session_start` | `session_context.sh` | Every Claude Code session start |
| `classifier` | `classify_task.sh` | When classifier fires; carries verdict and rule that fired |
| `pipeline_init` | `init_pipeline_state.sh` | Task run begins; carries run_id, pipeline type, classifier verdict |
| `agent_start` | `log_agent.sh` | Orchestrator dispatches an agent |
| `tool_call` | `log_tool.sh` | Tool use during active run, attributed to current agent |
| `agent_envelope` | `validate_output.sh` | Validated agent output with real wall-clock timestamp |
| `agent_end` | `log_agent.sh` | Agent finishes; carries verdict, next_agent, retry count |
| `pipeline_complete` | `advance_pipeline_state.sh` | Task run finishes |

```bash
# Replay a specific run
python3 .claude/tools/trace_analyze.py --run-id <run_id>

# Analytics across all runs (p50/p95 timing, classifier rates, block rates)
python3 .claude/tools/pipeline_analytics.py
```

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
3. Save credentials globally (bootstrap removes the per-project `.env.telegram.example` — store it in your home directory instead):
   ```bash
   cat > ~/.claude/telegram.env << 'EOF'
   TELEGRAM_BOT_TOKEN=your_token_here
   TELEGRAM_CHAT_ID=your_chat_id_here
   EOF
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
| `tools/pipeline_analytics.py` | Analytics from `logs/pipeline.jsonl`: agent timing (p50/p95), classifier verdict distribution, reviewer rejection rate, security block rate, rework rate |
| `tools/trace_analyze.py` | Human-readable pipeline run summary: agent outcomes, tool distribution, classifier verdicts by run |
| `tools/pool_sync.py` | Pull/push facts to a shared knowledge pool repo (see `docs/shared-pool.md`) |

Usage examples:

```bash
python tools/memory_read.py --tag auth
python tools/memory_read.py --file core
python tools/search.py "JWT" --fuzzy
```

---

## Bootstrap Walkthrough

`bootstrap.sh` runs 9 steps:

1. **Replace placeholders** — substitutes `{{PROJECT_NAME}}`, `{{TECH_STACK}}`, `{{DESCRIPTION}}`, `{{DATE}}`, `{{OWNER_EMAIL}}` across all `.md`, `.sh`, `.py`, and `.json` files
2. **Write `memory/core.md`** — creates the permanent project identity record
3. **Stamp `CONVENTIONS.md`** — adds a "Last reviewed" date
4. **Merge stack overlay** — detects your stack (Python / Node.js / Java) and merges the matching `conventions/<stack>.md` into `CONVENTIONS.md` and `agents/overlays/<stack>.md` into coder/tester/security agent definitions; prompts you to pick a stack if not auto-detected
5. **Generate `README.md`** — copies and fills `README_TEMPLATE.md`, then deletes the template
6. **Remove bootstrap artifacts** — deletes `README_TEMPLATE.md`, `scripts/`, `docs/superpowers/`, template HTML files, hook tests, CI workflow, `.env.*.example` files, and `ISSUES.md`; clears operational logs
7. **Move Claude infrastructure into `.claude/`** — moves `agents/`, `hooks/`, `skills/`, `tools/`, `contracts/`, `conventions/` into `.claude/` subdirectories; updates hook paths in `settings.json`; writes a slim `CLAUDE.md` (13 lines) that imports `.claude/orchestrator.md`
8. **Fresh git history** — removes the template's `.git`, runs `git init`, makes an initial commit
9. **Optional GitHub repo** — offers to create and push a GitHub repository via `gh`

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

After `bootstrap.sh` completes, your project looks like this:

```
my-project/
├── .claude/
│   ├── settings.json              # hooks, permissions, budget config
│   ├── orchestrator.md            # full pipeline/memory/hooks instructions
│   ├── agents/
│   │   ├── researcher.md, coder.md, reviewer.md, tester.md
│   │   ├── security.md, git.md, devops.md, memory.md
│   │   ├── changelog.md, writer.md
│   │   └── overlays/              # stack-specific agent rules (python/nodejs/java)
│   ├── hooks/
│   │   ├── lib/common.sh          # shared helpers (PROJECT_ROOT, state_field, current_agent)
│   │   ├── session_override.sh    # SessionStart: Phase 0 skill override notice
│   │   ├── session_context.sh     # SessionStart: inject memory + emit session_start event
│   │   ├── classify_task.sh       # PreToolUse: write FORCE_FULL|AMBIGUOUS to .claude/tmp/task_mode
│   │   ├── budget_guard.sh        # PreToolUse: daily + per-agent tool call limits
│   │   ├── log_tool.sh            # PreToolUse: tool_calls.log + pipeline.jsonl tool_call events
│   │   ├── git_guard.sh           # PreToolUse: block git commit/push outside the "git" pipeline step
│   │   ├── log_agent.sh           # called by orchestrator: START/END to agent_calls.log + pipeline.jsonl
│   │   ├── init_pipeline_state.sh # called by orchestrator: create pipeline_state.json, emit pipeline_init
│   │   ├── advance_pipeline_state.sh # called by orchestrator: advance step, emit pipeline_complete
│   │   ├── validate_output.sh     # called by orchestrator: validate envelope against contract
│   │   ├── on_error.sh            # Stop: clear idle timestamps, write recovery note
│   │   └── telegram_approval.py   # PreToolUse (Bash): remote approval via Telegram
│   ├── skills/
│   │   ├── coding-patterns.md     # → Coder
│   │   ├── reliability-patterns.md # → Reviewer (always)
│   │   ├── api-design.md          # → Reviewer (HTTP/API projects)
│   │   ├── test-strategy.md       # → Tester
│   │   ├── security-rules.md      # → Security
│   │   ├── git-commit.md          # → Git
│   │   └── overlays/              # stack-specific reliability rules
│   ├── contracts/
│   │   ├── coder.json, researcher.json, reviewer.json, tester.json
│   │   ├── security.json, git.json, devops.json, memory.json
│   │   └── pipeline-slos.md       # per-agent soft/hard tool call limits
│   ├── tools/
│   │   ├── memory_read.py, memory_write.py, search.py
│   │   ├── pipeline_analytics.py  # p50/p95 timing, classifier rates, block rates
│   │   └── trace_analyze.py       # human-readable pipeline run summary
│   └── conventions/               # stack-specific coding standards
├── memory/
│   ├── core.md                    # permanent project identity
│   ├── facts.md                   # tagged declarative facts (grep by [tag])
│   ├── scratchpad.md              # ephemeral working context (wiped per task)
│   ├── session_checkpoint.md      # session recovery state
│   └── episodic/                  # daily event logs
├── logs/
│   ├── tool_calls.log             # every tool call, flat format
│   ├── agent_calls.log            # agent START/END timing
│   └── pipeline.jsonl             # structured JSONL: full run trace
├── docs/
│   └── decisions/                 # ADRs for non-obvious architecture decisions
├── TASKS.md
├── AGENTS.md
├── CONVENTIONS.md
├── CHANGELOG.md
└── CLAUDE.md                      # 13 lines: project identity + @.claude/orchestrator.md
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
