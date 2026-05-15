#!/usr/bin/env bash
# Consumes stdin to avoid blocking the hook system
cat > /dev/null

cat >&2 <<'EOF'
╔══════════════════════════════════════════════════════════════════╗
║  PROJECT PIPELINE OVERRIDE — session_override.sh                ║
╠══════════════════════════════════════════════════════════════════╣
║  This project uses a custom orchestrator pipeline (CLAUDE.md).  ║
║  Superpowers skill usage is modified for this project:          ║
║                                                                  ║
║  PHASE 0 (run these explicitly, in order):                      ║
║    1. brainstorming  — clarify requirements, produce spec doc   ║
║    2. writing-plans  — produce implementation plan doc          ║
║    3. Writer agent   — converts plan into TASKS.md entries      ║
║                                                                  ║
║  BLOCKED (do not invoke — orchestrator pipeline replaces them): ║
║    ✗  executing-plans                                           ║
║    ✗  subagent-driven-development                               ║
║                                                                  ║
║  After writing-plans completes:                                  ║
║    → Do NOT offer "subagent-driven or inline execution?"        ║
║    → Hand the plan doc to the Writer agent                      ║
║    → Writer populates TASKS.md                                  ║
║    → Orchestrator picks tasks and runs the full pipeline        ║
║                                                                  ║
║  CLAUDE.md is the only execution authority for this project.    ║
╚══════════════════════════════════════════════════════════════════╝
EOF
