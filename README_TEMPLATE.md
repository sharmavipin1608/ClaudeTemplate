# {{PROJECT_NAME}}

{{DESCRIPTION}}

**Stack:** {{TECH_STACK}}
**Owner:** {{OWNER_EMAIL}}
**Created:** {{DATE}}

---

## Getting Started

```bash
# Clone the repository
git clone <your-repo-url>
cd {{PROJECT_NAME}}

# TODO: add project-specific setup steps here
# e.g. install dependencies, set environment variables, run migrations
```

---

## Development Workflow

This project uses a multi-agent Claude Code system. To work on a task:

1. Open Claude Code in this directory
2. Describe what you want to build or fix
3. The agent pipeline handles the rest: research → code → review → test → security check → commit

Current tasks are tracked in `TASKS.md`. Add new tasks there before starting work.

---

## Project Structure

```
{{PROJECT_NAME}}/
├── agents/          # Agent definitions
├── memory/          # Project memory (core, facts, scratchpad, episodic)
├── skills/          # Skill reference files loaded by agents
├── hooks/           # Automation hooks (pre/post task, logging, budget)
├── tools/           # Python memory and search utilities
├── logs/            # Tool call and token usage logs
├── TASKS.md         # Task backlog and status
├── AGENTS.md        # Agent registry
├── CONVENTIONS.md   # Team conventions and coding standards
├── CHANGELOG.md     # Project changelog
└── CLAUDE.md        # Orchestrator instructions
```

_Update this tree to reflect your project's actual source directories as you build._

---

## Memory System

Project knowledge is stored in `memory/`:

| File | Contents |
|---|---|
| `memory/core.md` | Permanent project identity, stack, architecture overview |
| `memory/facts.md` | Tagged facts — grep by `[domain]` tag for fast retrieval |
| `memory/scratchpad.md` | Ephemeral working notes for the current task |
| `memory/session_checkpoint.md` | Recovery state for resuming paused sessions |
| `memory/episodic/` | Daily event logs for debugging and retrospectives |

Agents read from and write to these files automatically. You can also query them directly:

```bash
python tools/memory_read.py --tag auth
python tools/search.py "database schema" --fuzzy
```

---

## Contributing

TODO: add contribution guidelines here.

---

## License

TODO: add license information here.
