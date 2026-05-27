#!/usr/bin/env python3
"""
PreToolUse hook: intercepts Bash tool calls and routes them to Telegram for remote approval.

Activation:
  Run `telegram` in any terminal to toggle routing on/off (no Claude Code restart needed).
  Flag file: ~/.claude/telegram_active

Credential lookup order:
  1. <project_root>/.env.telegram   (per-project)
  2. ~/.claude/telegram.env          (global fallback)

If the flag file is absent, or credentials are missing, the hook exits silently
and Claude Code shows its native dialog.
"""

import json
import os
import subprocess
import sys
import urllib.error
import urllib.request
from pathlib import Path


# ── Credentials ───────────────────────────────────────────────────────────────

def load_credentials():
    try:
        project_root = subprocess.check_output(
            ["git", "rev-parse", "--show-toplevel"], stderr=subprocess.DEVNULL
        ).decode().strip()
    except Exception:
        project_root = os.getcwd()

    candidates = [
        Path(project_root) / ".env.telegram",
        Path.home() / ".claude" / "telegram.env",
    ]

    for path in candidates:
        if path.exists():
            config = {}
            with open(path) as f:
                for line in f:
                    line = line.strip()
                    if line and not line.startswith("#") and "=" in line:
                        key, _, value = line.partition("=")
                        config[key.strip()] = value.strip().strip('"').strip("'")
            token = config.get("TELEGRAM_BOT_TOKEN")
            chat_id = config.get("TELEGRAM_CHAT_ID")
            if token and chat_id:
                return token, chat_id, project_root

    return None, None, project_root


# ── Telegram API ──────────────────────────────────────────────────────────────

def _api(bot_token, method, payload):
    url = f"https://api.telegram.org/bot{bot_token}/{method}"
    data = json.dumps(payload).encode()
    req = urllib.request.Request(url, data=data, headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=35) as resp:
        return json.loads(resp.read())


def send_message(token, chat_id, text, keyboard=None):
    payload = {"chat_id": chat_id, "text": text, "parse_mode": "Markdown"}
    if keyboard:
        payload["reply_markup"] = keyboard
    return _api(token, "sendMessage", payload)


def edit_message(token, chat_id, message_id, text):
    _api(token, "editMessageText", {
        "chat_id": chat_id, "message_id": message_id,
        "text": text, "parse_mode": "Markdown",
    })


def answer_callback(token, callback_id):
    _api(token, "answerCallbackQuery", {"callback_query_id": callback_id})


def get_updates(token, offset=None):
    payload = {"timeout": 30}  # long-poll: Telegram holds connection up to 30s
    if offset is not None:
        payload["offset"] = offset
    return _api(token, "getUpdates", payload)


# ── Core logic ────────────────────────────────────────────────────────────────

def poll_for_decision(token, chat_id, message_id):
    """Block indefinitely until the user taps Allow or Deny on the message."""
    offset = None
    while True:
        try:
            updates = get_updates(token, offset)
        except Exception:
            continue  # network hiccup — keep polling

        for update in updates.get("result", []):
            offset = update["update_id"] + 1
            cb = update.get("callback_query")
            if not cb:
                continue
            if cb["message"]["message_id"] != message_id:
                continue
            if str(cb["message"]["chat"]["id"]) != str(chat_id):
                continue
            return cb["data"], cb["id"]  # "allow" | "deny", callback_id


def build_message(project_name, tool_name, command, description):
    cmd_display = command if len(command) <= 500 else command[:497] + "..."
    parts = [
        f"🔔 *Permission Request — {project_name}*",
        "",
        f"🔧 *{tool_name}*",
        "",
        f"```\n{cmd_display}\n```",
    ]
    if description:
        parts.append(f"\n📝 {description}")
    return "\n".join(parts)


def main():
    try:
        input_data = json.load(sys.stdin)
    except Exception:
        sys.exit(0)

    # Check flag file — toggled by running `telegram` in any terminal
    if not Path.home().joinpath(".claude/telegram_active").exists():
        sys.exit(0)

    tool_name = input_data.get("tool_name", "")
    tool_input = input_data.get("tool_input", {})

    # Only intercept tools listed in TELEGRAM_INTERCEPT_TOOLS (default: Bash)
    intercept = [t.strip() for t in os.getenv("TELEGRAM_INTERCEPT_TOOLS", "Bash").split(",")]
    if tool_name not in intercept:
        sys.exit(0)

    token, chat_id, project_root = load_credentials()
    if not token or not chat_id:
        sys.exit(0)  # no credentials — fall through to native Claude Code dialog

    project_name = os.path.basename(project_root)
    command = tool_input.get("command", "")
    description = tool_input.get("description", "")

    message_text = build_message(project_name, tool_name, command, description)
    keyboard = {
        "inline_keyboard": [[
            {"text": "✅ Allow", "callback_data": "allow"},
            {"text": "❌ Deny",  "callback_data": "deny"},
        ]]
    }

    try:
        result = send_message(token, chat_id, message_text, keyboard)
        message_id = result["result"]["message_id"]
    except Exception:
        sys.exit(0)  # Telegram unreachable — fall through to native dialog

    decision, callback_id = poll_for_decision(token, chat_id, message_id)

    # Edit the original message in place to confirm the decision
    emoji = "✅" if decision == "allow" else "❌"
    action = "Approved" if decision == "allow" else "Denied"
    summary = description or command[:80]
    try:
        edit_message(token, chat_id, message_id,
                     f"{emoji} *{action} — {project_name}*\n🔧 {tool_name} · {summary}")
        answer_callback(token, callback_id)
    except Exception:
        pass

    if decision == "allow":
        print(json.dumps({"decision": "allow"}))
    else:
        print(json.dumps({"decision": "block", "reason": "Denied via Telegram"}))


if __name__ == "__main__":
    main()
