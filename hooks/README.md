# hooks/

Shell scripts wired into Claude Code's hook system via `.claude/settings.json`. They run automatically on tool lifecycle events — no orchestrator action required.

## Execution Model

Claude Code invokes hooks as subprocesses and passes a JSON payload on stdin. Hooks must consume stdin (even if unused) to avoid blocking. Output to stderr is surfaced in the Claude Code UI; stdout is discarded.

Hook events and when each script fires:

| Event | Scripts |
|---|---|
| `SessionStart` | `session_override.sh` |
| `PreToolUse` (Bash only) | `telegram_approval.py` |
| `PreToolUse` (all tools) | `pre_task.sh`, `classify_task.sh`, `budget_guard.sh`, `log_tool.sh` |
| `PostToolUse` | `post_task.sh`, `log_tool.sh` |
| `Stop` | `on_error.sh` |

---

## Scripts

### `telegram_approval.py`
**Event:** PreToolUse (Bash only)

Intercepts Bash tool calls and routes them to Telegram for remote approval instead of requiring you to be at the keyboard. Sends a message with the command and description, with inline ✅ Allow / ❌ Deny buttons. Polls indefinitely — no timeout — matching Claude Code's native behavior. The original message edits in place once you tap.

**Credential lookup order (first match wins):**
1. `<project_root>/.env.telegram` — per-project credentials
2. `~/.claude/telegram.env` — global fallback for all projects

If neither file exists the hook exits silently and Claude Code shows its native permission dialog.

**Setup:**
1. Message `@BotFather` on Telegram → `/newbot` → copy the token
2. Message `@userinfobot` on Telegram → copy your numeric chat ID
3. Copy `.env.telegram.example` to `.env.telegram` (or `~/.claude/telegram.env` for global) and fill in both values
4. Send your bot any message to open a conversation so it can reach you

**Toggling on/off:**

Run `telegram` in any terminal to flip the state — no Claude Code restart needed:
```
$ telegram
Telegram approval: ON  — Bash approvals will route to Telegram

$ telegram
Telegram approval: OFF — using native Claude Code dialogs
```

The `telegram` command is a symlink to `hooks/telegram_toggle.sh`. Install it once:
```bash
ln -sf "$(pwd)/hooks/telegram_toggle.sh" ~/.local/bin/telegram
```

**Configuration:**

| Env var | Default | Effect |
|---|---|---|
| `TELEGRAM_INTERCEPT_TOOLS` | `Bash` | Comma-separated tool names to route through Telegram |

---

### `session_override.sh`
**Event:** SessionStart

Fires once at the start of every session. Prints a structured override notice to stderr that tells Claude which superpowers skills are permitted in Phase 0 (`brainstorming`, `writing-plans`) and which are blocked (`executing-plans`, `subagent-driven-development`). Also instructs Claude to hand off to the Writer agent after `writing-plans` completes rather than offering the standard "subagent-driven or inline execution?" choice.

This hook exists because superpowers is installed globally and its `SessionStart` injection uses aggressive language that can override CLAUDE.md without an explicit counter-signal at session start. This script provides that counter-signal at the same event, before CLAUDE.md is read.

### `pre_task.sh`
**Event:** PreToolUse

Injects memory context into the conversation once per session. Reads `session_id` from stdin, compares it to `.claude/last_session_id`, and skips if already run this session. On a new session, prints `memory/core.md`, `memory/session_checkpoint.md` (if > 50 bytes), and `memory/scratchpad.md` (if > 100 bytes) to stderr so Claude sees them in context.

### `classify_task.sh`
**Event:** PreToolUse

Classifies the current in-progress task as `FORCE_FULL` or `AMBIGUOUS` and writes the verdict to `/tmp/task_mode`. The orchestrator reads this file to decide between the full pipeline and the fast-track pipeline.

Hard rules that always produce `FORCE_FULL`:
- Auth/security/token file paths touched
- Payment/billing file paths touched
- Database migration or schema files changed
- Dockerfile, docker-compose, or CI workflow files changed
- Any file under `hooks/` changed
- `CLAUDE.md` or `AGENTS.md` changed
- Any file deleted
- Any new file created
- More than `FAST_TRACK_FILE_LIMIT` (default 5) files modified
- Dependency manifests changed (`package.json`, `requirements.txt`, etc.)
- Sensitive keywords in the task description (PII, GDPR, privacy, etc.)

If no hard rule fires, writes `AMBIGUOUS` — the orchestrator then reasons about whether to use the full pipeline.

Results are cached per task (via a hash of the in-progress task content) so the script only re-runs when the task changes.

### `budget_guard.sh`
**Event:** PreToolUse

Counts today's tool calls in `logs/tool_calls.log` and compares against `CLAUDE_DAILY_CALL_LIMIT` (default: 500). If the limit is reached:
- `CLAUDE_BUDGET_MODE=warn` (default): logs a warning and continues
- `CLAUDE_BUDGET_MODE=halt`: exits with code 1, which stops Claude Code from proceeding

Token counts are not available in Claude Code hooks, so tool call volume is used as a cost proxy.

### `log_tool.sh`
**Event:** PreToolUse and PostToolUse

Parses `tool_name` from the stdin JSON and appends a line to `logs/tool_calls.log`:
```
2026-05-15T10:00:00Z | Bash
```
Runs on both PreToolUse and PostToolUse, providing a full call record used by `budget_guard.sh` and available for cost analysis.

### `post_task.sh`
**Event:** PostToolUse

Appends a `POST_TOOL | done` marker to `logs/tool_calls.log` after each tool call completes. Provides a paired end-marker for the pre-tool entry written by `log_tool.sh`.

### `log_agent.sh`
**Event:** Called directly by the orchestrator

Not a lifecycle hook — called explicitly by the orchestrator via `bash hooks/log_agent.sh <agent_name> <START|END>`. Writes timing entries to `logs/agent_calls.log`:
```
2026-05-15T10:00:00Z | researcher | START
2026-05-15T10:02:30Z | researcher | END
```
Review this log weekly to identify which agents run longest and where to tune.

### `on_error.sh`
**Event:** Stop

Fires when Claude Code stops for any reason. Reads `stop_reason` from stdin (defaults to `end_turn` if unparseable). Ignores normal `end_turn` exits. For unexpected stops (`max_tokens`, errors, etc.), logs the reason to `logs/tool_calls.log` and appends a recovery note to `memory/scratchpad.md` so the next session knows to resume interrupted work.

---

## Configuration

| Env var | Default | Effect |
|---|---|---|
| `CLAUDE_DAILY_CALL_LIMIT` | `500` | Max tool calls per day before budget action |
| `CLAUDE_BUDGET_MODE` | `warn` | `warn` logs and continues; `halt` stops Claude Code |
| `FAST_TRACK_FILE_LIMIT` | `5` | Modified file count above which `classify_task.sh` forces full pipeline |

---

## Logs

| File | Written by | Content |
|---|---|---|
| `logs/tool_calls.log` | `log_tool.sh`, `post_task.sh`, `budget_guard.sh`, `on_error.sh` | Every tool call with timestamp |
| `logs/agent_calls.log` | `log_agent.sh` | Agent START/END timing |
