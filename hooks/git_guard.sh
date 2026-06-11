#!/bin/bash
# Blocks git commit and git push when the active pipeline step is not "git".
# Registered on PreToolUse (Bash only).
#
# The Git agent is the only entity permitted to commit or push. If the
# orchestrator runs git commit/push directly it bypasses envelope validation,
# the push confirmation gate, and the audit trail in pipeline.jsonl.
#
# Exit 2 blocks the tool call (Claude Code only blocks on exit 2).
# Exit 0 allows it.

source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

INPUT=$(cat)

# Only inspect Bash tool calls
TOOL=$(printf '%s' "$INPUT" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('tool_name',''))" 2>/dev/null || echo "")
[ "$TOOL" != "Bash" ] && exit 0

# Extract the bash command
CMD=$(printf '%s' "$INPUT" | python3 -c "import json,sys; d=json.load(sys.stdin); inp=d.get('tool_input',{}); print(inp.get('command',''))" 2>/dev/null || echo "")

# Check if the command contains git commit or git push
if ! echo "$CMD" | grep -qE "git (commit|push)"; then
    exit 0
fi

# Allow if no pipeline is running (outside of any pipeline context)
STATUS=$(state_field status)
[ "$STATUS" != "running" ] && exit 0

# Allow if the current pipeline step IS the git agent
STEP=$(state_field current_step)
if [ "$STEP" = "git" ]; then
    exit 0
fi

# Block: orchestrator is attempting to commit/push directly
echo "[GIT GUARD] Blocked: git commit/push is only permitted inside the Git agent subagent." >&2
echo "[GIT GUARD] Current pipeline step: '${STEP}'. Dispatch the Git agent instead." >&2
echo "[GIT GUARD] See .claude/agents/git.md and the routing table in orchestrator.md." >&2
exit 2
