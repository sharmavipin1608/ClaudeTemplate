#!/bin/bash
# Toggles Telegram approval routing for Claude Code Bash permission prompts.
# Run as: telegram
# The flag file is checked fresh on every hook call — no Claude Code restart needed.

FLAG="$HOME/.claude/telegram_active"

if [ -f "$FLAG" ]; then
    rm "$FLAG"
    echo "Telegram approval: OFF — using native Claude Code dialogs"
else
    touch "$FLAG"
    echo "Telegram approval: ON  — Bash approvals will route to Telegram"
fi
