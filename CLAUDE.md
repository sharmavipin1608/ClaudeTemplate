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

For every task:
1. Read `TASKS.md` to understand what's next
2. Read `memory/core.md` for project identity
3. Read `memory/facts.md` (or grep relevant tags) for known decisions
4. Read `memory/session_checkpoint.md` for session recovery context
5. Load `memory/scratchpad.md` for current working context
6. Delegate to the right sub-agent with a **surgical context** — only what they need
7. After task completes, update `TASKS.md` and `memory/scratchpad.md`

---

## 🤖 Agent Pipeline

```
Researcher → Coder → Reviewer → Tester → Security → Git → Memory → Changelog
```

- Each agent runs in **isolation** — do not pass full conversation history
- Pass only: task description + relevant memory chunks + relevant skill file
- Security agent is a **gate** — pipeline stops if it returns blockers

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
| `coder` | Implementation task | task + scratchpad + java-patterns.md | code only |
| `reviewer` | After coder | code + api-design.md | pass / fix list |
| `tester` | After reviewer | code + test-strategy.md | tests written + run |
| `security` | After tester | diff + security-rules.md | PASS or BLOCKERS |
| `git` | After security PASS | diff + git-commit.md | commit + push |
| `memory` | After git + ad-hoc on significant decisions | task output + scratchpad + facts | updated memory files + checkpoint |
| `changelog` | End of day | git log | CHANGELOG.md updated |
| `writer` | Docs needed | task + core.md | markdown docs |

---

## 🔧 Skills (Lazy Load — Never Dump All)

| Skill file | Load when |
|---|---|
| `skills/java-patterns.md` | Coder agent runs |
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
      { "command": "bash hooks/pre_task.sh" },
      { "command": "bash hooks/log_tool.sh $TOOL_NAME $AGENT_NAME" },
      { "command": "bash hooks/budget_guard.sh" }
    ],
    "PostToolUse": [
      { "command": "bash hooks/post_task.sh" }
    ]
  }
}
```

| Hook | Purpose |
|---|---|
| `pre_task.sh` | Load core.md, grep relevant facts, load scratchpad |
| `post_task.sh` | Append to episodic log, update facts.md if new decision made, clear scratchpad |
| `log_tool.sh` | Append every tool call to `logs/tool_calls.log` |
| `budget_guard.sh` | Check daily token spend — halt if over limit |
| `on_error.sh` | Log failure, requeue task in TASKS.md, alert |

---

## 📊 Logging

- **Tool calls:** `logs/tool_calls.log` — format: `timestamp | AGENT | TOOL`
- **Token usage:** `logs/token_usage.log` — format: `timestamp | AGENT | TASK | IN | OUT`
- **Traces:** `logs/traces/` — only when debug mode is ON in `settings.json`

Use token logs to identify which agent is consuming the most budget and tune accordingly.

---

## 📁 Project Structure

```
my-project/
├── .claude/
│   ├── CLAUDE.md              ← you are here
│   └── settings.json
├── agents/
│   ├── AGENTS.md
│   ├── orchestrator.md
│   ├── researcher.md
│   ├── coder.md
│   ├── reviewer.md
│   ├── tester.md
│   ├── security.md
│   ├── git.md
│   ├── changelog.md
│   └── writer.md
├── skills/
│   ├── java-patterns.md
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
6. **Security is a gate** — never skip it
7. **Token logs are feedback** — review weekly and tune

---

## 🚀 Bootstrap Checklist (New Project)

- [ ] Run `new-project.sh` or use GitHub template → runs `bootstrap.sh` automatically
- [ ] `bootstrap.sh` handles: placeholders, memory/core.md, CONVENTIONS.md, TASKS.md, git init, optional GitHub repo
- [ ] First task after bootstrap: review and complete `CONVENTIONS.md`
- [ ] Adjust `budget.daily_token_limit` in `.claude/settings.json` if needed

---

*Generated from architecture discussion. Evolve this file as the project grows.*
