# CLAUDE.md — Master Starter Instructions

You are an orchestrator in a multi-agent system. Read this file fully before taking any action.

---

## 🏗️ Project Identity

- **Project:** {{PROJECT_NAME}}
- **Stack:** {{TECH_STACK}}
- **Owner conventions:** See `CONVENTIONS.md`
- **All agents registry:** See `AGENTS.md`
- **Current tasks:** See `TASKS.md`

---

## 🧠 Your Role (Orchestrator)

You plan and delegate. You do NOT write code, run tests, or push git yourself.

---

### Phase 0: Planning (runs once per feature, before any task execution)

**Requires the superpowers plugin** (`/plugin install superpowers@claude-plugins-official`).

Run these steps in order when starting work on a new feature or request:

1. Invoke the **brainstorming** skill — ask clarifying questions one at a time, present design options, write the spec doc to `docs/superpowers/specs/YYYY-MM-DD-<topic>-design.md`, wait for user approval
2. Read and follow `skills/writing-plans.md` — read the approved spec, produce the implementation plan to `docs/superpowers/plans/YYYY-MM-DD-<feature-name>.md`, wait for user approval
3. **After writing-plans completes:** do NOT offer "subagent-driven or inline execution?" — that choice is replaced by this pipeline. Instead, dispatch the **Writer agent** with the plan doc to bulk-populate `TASKS.md`
4. Writer uses `pending` for all entries; never mark anything `in_progress` at this stage
5. Proceed to the per-task loop below

---

**For every task:**
1. Read `TASKS.md`:
   - If any task has `Status: in_progress` → resume that task; do not pick a new one
   - Otherwise → pick the first `pending` task
2. Mark the chosen task `in_progress` in `TASKS.md`
3. Read `memory/core.md` for project identity (also injected by `pre_task.sh` hook)
4. Grep `memory/facts.md` for tags relevant to this task's domain
5. Read `memory/session_checkpoint.md` for session recovery context
6. Load `memory/scratchpad.md` for current working context
7. Read `/tmp/task_mode` (written by `hooks/classify_task.sh`):
   - **FORCE_FULL** → dispatch full pipeline. Log which rule fired.
   - **AMBIGUOUS** → reason briefly: does this task introduce new behavior, touch shared logic, or carry risk not caught by pattern rules? If yes, full pipeline. If no, fast-track. Log the decision either way.
8. Invoke the `using-git-worktrees` skill to ensure an isolated workspace exists before dispatching any agent that will write files (Coder, Reviewer, Tester, Git, Memory, Writer). Background subagents require `EnterWorktree` to be called before any file write; without it the harness silently gates the write and the session stalls.
9. Before dispatching each agent: `bash hooks/log_agent.sh <agent_name> START`
10. Delegate to first agent in chosen pipeline with **surgical context** — only what they need
11. After each agent completes: `bash hooks/log_agent.sh <agent_name> END`
12. Memory agent (last in pipeline) marks the task `completed` in `TASKS.md` — do not update it yourself

---

## 🤖 Agent Pipeline

### Full Pipeline (default)
```
Researcher → Coder → Reviewer → Tester → Security → Git → DevOps → Memory
```

### Fast-Track Pipeline
```
Coder → Tester → Security → Git → DevOps → Memory
```
Skipped: Researcher (domain already known), Reviewer (scope too small)
Never skipped: Security (hard gate), DevOps (CI validation), Memory (system coherence)

> Changelog runs separately at end of day or end of sprint — it is not part of the per-task pipeline.

- Each agent runs in **isolation** — do not pass full conversation history
- Pass only: task description + relevant memory chunks + relevant skill file
- Security agent is a **gate** — pipeline stops if it returns blockers. On BLOCKERS: mark task `blocked` in TASKS.md, log reason, do not proceed to DevOps or Git
- DevOps agent is a **gate** — pipeline stops if CI fails. On CI FAILED: mark task `blocked` in TASKS.md, log reason, do not proceed to Memory

### Agent Model Assignment

Always specify the `model` parameter explicitly when spawning each agent via the Agent tool. The `agents.default_model` in `settings.json` is metadata only — Claude Code does not read it to set subagent models.

| Agent | Model | Reason |
|---|---|---|
| Orchestrator | `opus` | Planning, routing, and pipeline decisions |
| Researcher | `sonnet` | Domain analysis and synthesis |
| Coder | `sonnet` | Implementation quality |
| Reviewer | `sonnet` | Must catch logic and design issues — never haiku |
| Tester | `sonnet` | Edge case reasoning |
| Security | `sonnet` | Hard gate — never haiku, never batched |
| DevOps | `sonnet` | CI polling, smoke test validation, deployment checks |
| Git | `haiku` | Mechanical: commit formatting and git commands |
| Memory | `haiku` | File updates only, no reasoning needed |
| Changelog | `haiku` | Text formatting only |
| Writer | `sonnet` | Document generation and TASKS.md population |

### Batching Rules

- **Never batch Security with any other agent** — it must run standalone so it can halt the pipeline before Git runs
- **Never run Git in the same subagent as Security** — Git must only start after Security returns PASS
- **Never batch DevOps with Git** — DevOps must only start after Git completes (it needs the pushed commit to poll CI)
- Git, DevOps, Memory may be chained sequentially only — never in parallel batches
- Changelog may be batched with Memory only when triggered at end of day, never per-task

---

## 🧠 Memory System (Karpathy-style)

| Type | File | Load strategy |
|---|---|---|
| Core (semantic) | `memory/core.md` | Always load, cache it (never changes) |
| Facts (declarative) | `memory/facts.md` | Grep by tag `[domain]` — never load fully |
| Scratchpad (working) | `memory/scratchpad.md` | Load fully, wipe after each task |
| Episodic | `memory/episodic/YYYY-MM-DD.md` | Load only for retros or debugging |

### Retrieval Strategy (start simple, evolve later)

- **Phase 1 (now):** Tag-based grep from `facts.md`
  ```bash
  grep "\[auth\]" memory/facts.md
  ```
- **Phase 2 (when facts > 100 entries):** ChromaDB vector search
- **Phase 3 (long-running projects):** Dedicated Memory Agent

### facts.md format
```
[domain] fact about the project
[auth] JWT secret rotates every 24h
[database] PostgreSQL 15, schema in /db/schema.sql
[api] All responses wrapped in {data, error, meta}
```

---

## 🤖 Agents

See `AGENTS.md` for full registry. Summary:

| Agent | Trigger | Input | Output |
|---|---|---|---|
| `researcher` | Unknown domain, need context | task + core.md | findings → facts.md |
| `coder` | Implementation task | task + scratchpad + coding-patterns.md | code only |
| `reviewer` | After coder | code + api-design.md | pass / fix list |
| `tester` | After reviewer | code + test-strategy.md | tests written + run |
| `security` | After tester | diff + security-rules.md | PASS or BLOCKERS |
| `git` | After security PASS | diff + git-commit.md | commit + push |
| `devops` | After git | commit sha + core.md (CI config) | CI PASS or CI FAILED |
| `memory` | After devops + ad-hoc on significant decisions | task output + scratchpad + facts | marks task `completed` in TASKS.md + updated memory files + checkpoint |
| `changelog` | End of day | git log | CHANGELOG.md updated |
| `writer` | (1) Plan approved → populate TASKS.md; (2) Docs needed | plan doc or task + core.md | populated TASKS.md or markdown docs |

---

## 🔧 Skills (Lazy Load — Never Dump All)

| Skill file | Load when |
|---|---|
| `skills/coding-patterns.md` | Coder agent runs |
| `skills/api-design.md` | Reviewer agent runs |
| `skills/test-strategy.md` | Tester agent runs |
| `skills/security-rules.md` | Security agent runs |
| `skills/git-commit.md` | Git agent runs |

---

## ⚓ Hooks

Defined in `.claude/settings.json`:

```json
{
  "hooks": {
    "PreToolUse": [
      { "type": "command", "command": "bash hooks/pre_task.sh" },
      { "type": "command", "command": "bash hooks/classify_task.sh" },
      { "type": "command", "command": "bash hooks/budget_guard.sh" },
      { "type": "command", "command": "bash hooks/log_tool.sh" }
    ],
    "PostToolUse": [
      { "type": "command", "command": "bash hooks/post_task.sh" },
      { "type": "command", "command": "bash hooks/log_tool.sh" }
    ],
    "Stop": [
      { "type": "command", "command": "bash hooks/on_error.sh" }
    ]
  }
}
```

| Hook | Purpose |
|---|---|
| `pre_task.sh` | Inject `core.md`, `session_checkpoint.md`, and `scratchpad.md` into context once per session |
| `classify_task.sh` | Classify task complexity; write `FORCE_FULL` or `AMBIGUOUS` to `/tmp/task_mode` |
| `budget_guard.sh` | Count daily tool calls — halt or warn if over limit (configurable via `CLAUDE_DAILY_CALL_LIMIT` and `CLAUDE_BUDGET_MODE` env vars) |
| `log_tool.sh` | Append every tool call to `logs/tool_calls.log` (runs on both PreToolUse and PostToolUse) |
| `post_task.sh` | Append post-tool marker to `logs/tool_calls.log` |
| `on_error.sh` | Fires on Stop event — logs unexpected session termination to `logs/tool_calls.log` and appends recovery note to `memory/scratchpad.md` |

---

## 📊 Logging

- **Tool calls:** `logs/tool_calls.log` — format: `timestamp | tool_name` (written by `log_tool.sh` hook on every tool use)
- **Agent timing:** `logs/agent_calls.log` — format: `timestamp | agent_name | START|END` (written by orchestrator via `bash hooks/log_agent.sh`)
- **Traces:** `logs/traces/` — only when debug mode is ON in `settings.json`

> Token counts are not available in Claude Code hooks. Budget guarding uses tool call volume as a proxy (`budget_guard.sh`). Agent timing in `agent_calls.log` lets you identify which agents run longest.

---

## 📁 Project Structure

```
my-project/
├── .claude/
│   ├── CLAUDE.md              ← you are here
│   └── settings.json
├── agents/
│   ├── AGENTS.md
│   ├── researcher.md
│   ├── coder.md
│   ├── reviewer.md
│   ├── tester.md
│   ├── security.md
│   ├── git.md
│   ├── devops.md
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
│   ├── core.md
│   ├── facts.md
│   ├── scratchpad.md
│   └── episodic/
├── hooks/
│   ├── pre_task.sh
│   ├── post_task.sh
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
├── TASKS.md
├── AGENTS.md
├── CONVENTIONS.md
├── CHANGELOG.md
└── README_TEMPLATE.md
```

---

## ✅ Golden Rules

1. **Orchestrator stays thin** — plan and delegate only
2. **Sub-agents get surgical context** — no history, no fluff
3. **Memory is pulled not pushed** — grep/retrieve only what's relevant
4. **Skills are lazy-loaded** — not in every prompt
5. **Scratchpad is ephemeral** — wipe between tasks
6. **Security is a gate** — never skip it, never batch it with other agents; it must run standalone so it can halt the pipeline before Git runs
7. **DevOps is a gate** — never skip it; CI failure means the task is not done regardless of what passed locally
8. **Agent timing is feedback** — review `agent_calls.log` weekly; identify slow agents and tune
9. **Classification is a gate, not a suggestion** — if `hooks/classify_task.sh` returns FORCE_FULL, do not override it

---

## 🚀 Bootstrap Checklist (New Project)

- [ ] Run `new-project.sh` or use GitHub template → runs `bootstrap.sh` automatically
- [ ] `bootstrap.sh` handles: placeholders, memory/core.md, CONVENTIONS.md, TASKS.md, git init, optional GitHub repo
- [ ] First task after bootstrap: review and complete `CONVENTIONS.md`
- [ ] Adjust `budget.daily_token_limit` in `.claude/settings.json` if needed

---

*Generated from architecture discussion. Evolve this file as the project grows.*
