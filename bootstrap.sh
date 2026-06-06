#!/bin/bash
# bootstrap.sh — Interactive project setup wizard for ClaudeTemplate
# Usage: ./bootstrap.sh [--doc /path/to/idea.md]
# Turns a freshly cloned copy of ClaudeTemplate into a new project.

set -euo pipefail

# ---------------------------------------------------------------------------
# ANSI color helpers
# ---------------------------------------------------------------------------
GREEN='\033[1;32m'
CYAN='\033[0;36m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
RESET='\033[0m'

header()  { printf "\n${GREEN}%s${RESET}\n" "$*"; }
prompt()  { printf "${CYAN}%s${RESET}" "$*"; }
success() { printf "${GREEN}%s${RESET}\n" "$*"; }
error()   { printf "${RED}ERROR: %s${RESET}\n" "$*" >&2; }
warn()    { printf "${YELLOW}WARN: %s${RESET}\n" "$*"; }

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
IDEA_DOC=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --doc)
      IDEA_DOC="$2"
      shift 2
      ;;
    *)
      error "Unknown argument: $1"
      printf "Usage: ./bootstrap.sh [--doc /path/to/idea.md]\n"
      exit 1
      ;;
  esac
done

if [[ -n "$IDEA_DOC" && ! -f "$IDEA_DOC" ]]; then
  error "Idea doc not found: $IDEA_DOC"
  exit 1
fi

# ---------------------------------------------------------------------------
# Parse idea doc for hints (best-effort grep extraction)
# ---------------------------------------------------------------------------
DOC_NAME=""
DOC_STACK=""
DOC_DESC=""

if [[ -n "$IDEA_DOC" ]]; then
  # Project name: first # heading
  DOC_NAME=$(grep -m1 "^# " "$IDEA_DOC" 2>/dev/null | sed 's/^# //' | tr -d '\r' || true)

  # Stack: line containing Stack:, Tech:, Technology: (bold markdown or plain)
  DOC_STACK=$(grep -iEm1 "^\*{0,2}(stack|tech(nology)?)\*{0,2}\s*:?\s*" "$IDEA_DOC" 2>/dev/null \
    | sed -E 's/^\*{0,2}(Stack|Tech(nology)?)\*{0,2}\s*:?\s*\*{0,2}//i' \
    | tr -d '\r*' || true)

  # Description: explicit **Description:** line first, then first non-heading paragraph
  DOC_DESC=$(grep -iEm1 "^\*{0,2}description\*{0,2}\s*:" "$IDEA_DOC" 2>/dev/null \
    | sed -E 's/^\*{0,2}[Dd]escription\*{0,2}\s*:\s*\*{0,2}//' \
    | tr -d '\r*' || true)
  if [[ -z "$DOC_DESC" ]]; then
    DOC_DESC=$(grep -v "^#" "$IDEA_DOC" | grep -v "^[[:space:]]*$" | grep -v "^\*\*" | head -1 | tr -d '\r' || true)
  fi
fi

# ---------------------------------------------------------------------------
# Banner
# ---------------------------------------------------------------------------
header "=================================================="
header "  ClaudeTemplate Bootstrap Wizard"
header "=================================================="
printf "This script will configure your new project.\n"
printf "Press Enter to accept defaults shown in [brackets].\n"
if [[ -n "$IDEA_DOC" ]]; then
  printf "\n${YELLOW}Idea doc loaded: %s${RESET}\n" "$IDEA_DOC"
  [[ -n "$DOC_NAME"  ]] && printf "  Detected name  : %s\n" "$DOC_NAME"
  [[ -n "$DOC_STACK" ]] && printf "  Detected stack : %s\n" "$DOC_STACK"
  [[ -n "$DOC_DESC"  ]] && printf "  Detected desc  : %s\n" "$DOC_DESC"
fi
printf "\n"

# ---------------------------------------------------------------------------
# Gather project information
# ---------------------------------------------------------------------------
DEFAULT_NAME="${DOC_NAME:-$(basename "$PWD")}"

prompt "Project name [${DEFAULT_NAME}]: "
read -r INPUT_NAME
PROJECT_NAME="${INPUT_NAME:-$DEFAULT_NAME}"

DEFAULT_STACK="${DOC_STACK:-}"
if [[ -n "$DEFAULT_STACK" ]]; then
  prompt "Tech stack [${DEFAULT_STACK}]: "
else
  prompt "Tech stack (e.g. 'Node.js + PostgreSQL'): "
fi
read -r INPUT_STACK
TECH_STACK="${INPUT_STACK:-${DEFAULT_STACK:-"(unspecified)"}}"

DEFAULT_DESC="${DOC_DESC:-}"
if [[ -n "$DEFAULT_DESC" ]]; then
  prompt "One-line description [${DEFAULT_DESC}]: "
else
  prompt "One-line description: "
fi
read -r INPUT_DESC
DESCRIPTION="${INPUT_DESC:-${DEFAULT_DESC:-"A project bootstrapped from ClaudeTemplate."}}"

prompt "Owner email: "
read -r OWNER_EMAIL
if [[ -z "$OWNER_EMAIL" ]]; then
  OWNER_EMAIL="owner@example.com"
fi

prompt "GitHub visibility — public or private [private]: "
read -r INPUT_VIS
VISIBILITY="${INPUT_VIS:-private}"
if [[ "$VISIBILITY" != "public" && "$VISIBILITY" != "private" ]]; then
  warn "Unrecognised value '$VISIBILITY'; defaulting to 'private'."
  VISIBILITY="private"
fi

TODAY=$(date +%Y-%m-%d)

# ---------------------------------------------------------------------------
# Confirm before proceeding
# ---------------------------------------------------------------------------
header "--------------------------------------------------"
printf "  Project name : %s\n" "$PROJECT_NAME"
printf "  Tech stack   : %s\n" "$TECH_STACK"
printf "  Description  : %s\n" "$DESCRIPTION"
printf "  Owner email  : %s\n" "$OWNER_EMAIL"
printf "  Visibility   : %s\n" "$VISIBILITY"
printf "  Date         : %s\n" "$TODAY"
[[ -n "$IDEA_DOC" ]] && printf "  Idea doc     : %s (will be copied to docs/)\n" "$(basename "$IDEA_DOC")"
header "--------------------------------------------------"
prompt "Proceed? [Y/n]: "
read -r CONFIRM
CONFIRM="${CONFIRM:-Y}"
if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
  error "Aborted by user."
  exit 1
fi

# ---------------------------------------------------------------------------
# Helper: safe sed that works on both macOS (BSD sed) and Linux (GNU sed)
# ---------------------------------------------------------------------------
replace_in_file() {
  local pattern="$1"
  local replacement="$2"
  local file="$3"
  local escaped
  escaped=$(printf '%s\n' "$replacement" | sed 's/[\/&]/\\&/g')
  sed -i.bak "s/${pattern}/${escaped}/g" "$file" && rm -f "${file}.bak"
}

# ---------------------------------------------------------------------------
# Step 1/9 — Replace placeholders
# ---------------------------------------------------------------------------
header "Step 1/9 — Replacing placeholders in project files..."

FILES=()
while IFS= read -r -d '' f; do
  FILES+=("$f")
done < <(find . -type f \( \
  -name "*.md" \
  -o -name "*.sh" \
  -o -name "*.py" \
  -o -name "*.json" \
\) -not -path './.git/*' -print0 2>/dev/null)

REPLACED=0
for f in "${FILES[@]}"; do
  replace_in_file "{{PROJECT_NAME}}" "$PROJECT_NAME" "$f"
  replace_in_file "{{TECH_STACK}}"   "$TECH_STACK"   "$f"
  replace_in_file "{{DESCRIPTION}}"  "$DESCRIPTION"  "$f"
  replace_in_file "{{DATE}}"         "$TODAY"         "$f"
  replace_in_file "{{OWNER_EMAIL}}"  "$OWNER_EMAIL"  "$f"
  (( REPLACED++ ))
done

success "  Replaced placeholders in ${REPLACED} files."

# ---------------------------------------------------------------------------
# Step 2/9 — Write memory/core.md
# ---------------------------------------------------------------------------
header "Step 2/9 — Writing memory/core.md..."

mkdir -p memory
cat > memory/core.md <<EOF
# Project Core Memory

**Project:** ${PROJECT_NAME}
**Stack:** ${TECH_STACK}
**Description:** ${DESCRIPTION}
**Owner:** ${OWNER_EMAIL}
**Created:** ${TODAY}

## Architecture Overview
_Fill this in as the architecture becomes clear._

## Key External Dependencies
_List major external services, APIs, or databases here._
EOF

success "  memory/core.md written."

# ---------------------------------------------------------------------------
# Step 3/9 — Stamp CONVENTIONS.md
# ---------------------------------------------------------------------------
header "Step 3/9 — Stamping CONVENTIONS.md..."

if [[ -f "CONVENTIONS.md" ]]; then
  replace_in_file "{{DATE}}" "$TODAY" "CONVENTIONS.md"
  if ! grep -q "Last reviewed:" CONVENTIONS.md 2>/dev/null; then
    printf "\n---\n_Last reviewed: %s_\n" "$TODAY" >> CONVENTIONS.md
  fi
  success "  CONVENTIONS.md stamped."
else
  warn "  CONVENTIONS.md not found — skipping."
fi

# ---------------------------------------------------------------------------
# Step 4/9 — Generate README.md
# ---------------------------------------------------------------------------
header "Step 4/9 — Generating README.md..."

if [[ -f "README_TEMPLATE.md" ]]; then
  cp README_TEMPLATE.md README.md
  replace_in_file "{{PROJECT_NAME}}" "$PROJECT_NAME" "README.md"
  replace_in_file "{{TECH_STACK}}"   "$TECH_STACK"   "README.md"
  replace_in_file "{{DESCRIPTION}}"  "$DESCRIPTION"  "README.md"
  replace_in_file "{{DATE}}"         "$TODAY"         "README.md"
  replace_in_file "{{OWNER_EMAIL}}"  "$OWNER_EMAIL"  "README.md"
  success "  README.md generated from README_TEMPLATE.md."
else
  cat > README.md <<EOF
# ${PROJECT_NAME}

${DESCRIPTION}

**Stack:** ${TECH_STACK}
**Owner:** ${OWNER_EMAIL}
**Created:** ${TODAY}
EOF
  success "  README.md created (minimal version)."
fi

# ---------------------------------------------------------------------------
# Step 5/9 — Copy idea doc and prepend TASK-000 (if --doc provided)
# ---------------------------------------------------------------------------
if [[ -n "$IDEA_DOC" ]]; then
  header "Step 5/9 — Importing idea doc..."

  mkdir -p docs
  DOC_FILENAME=$(basename "$IDEA_DOC")
  cp "$IDEA_DOC" "docs/${DOC_FILENAME}"
  success "  Copied to docs/${DOC_FILENAME}."

  # Prepend TASK-000 to TASKS.md before the existing tasks
  if [[ -f "TASKS.md" ]]; then
    TASK_BLOCK=$(cat <<EOF

### [TASK-000] Brainstorm and design the project
**Status:** pending
**Priority:** high
**Agent:** orchestrator
**Tags:** [core]

Idea doc: \`docs/${DOC_FILENAME}\`

This is a rough idea — not a spec. Do NOT jump to implementation.

Use the brainstorming skill to hash it out with the user into a proper design:
1. Read \`docs/${DOC_FILENAME}\` for context before asking any questions
2. Invoke the brainstorming skill — it guides the full design conversation
3. Output: design spec → \`docs/superpowers/specs/YYYY-MM-DD-<name>-design.md\`
4. Output: implementation plan → \`docs/superpowers/plans/YYYY-MM-DD-<name>-implementation.md\`

Only start TASK-001 after the implementation plan exists.

EOF
)
    # Insert after the "## Tasks" heading.
    # Write block to a temp file so markdown special chars (backticks, **, <>) never
    # land inside a regex replacement string.
    _TASK_TMP=$(mktemp)
    printf '%s' "$TASK_BLOCK" > "$_TASK_TMP"
    python3 -c "
import sys
block = open(sys.argv[1]).read()
content = open('TASKS.md').read()
content = content.replace('## Tasks\n', '## Tasks\n' + block, 1)
open('TASKS.md', 'w').write(content)
" "$_TASK_TMP"
    rm -f "$_TASK_TMP"
    success "  Prepended TASK-000 to TASKS.md."
  fi
else
  header "Step 5/9 — No idea doc provided (skipping)."
fi

# ---------------------------------------------------------------------------
# Step 6/9 — Remove bootstrap artifacts
# ---------------------------------------------------------------------------
header "Step 6/9 — Removing bootstrap artifacts..."

[[ -f "README_TEMPLATE.md" ]] && rm -f README_TEMPLATE.md && success "  Removed README_TEMPLATE.md."
[[ -d "scripts"            ]] && rm -rf scripts            && success "  Removed scripts/."

# Remove only the template's own design/plan docs — keep the directory structure
# so brainstorming can save new specs and plans here
if [[ -d "docs/superpowers" ]]; then
  rm -f docs/superpowers/specs/*.md docs/superpowers/plans/*.md 2>/dev/null || true
  # Keep empty dirs so brainstorming outputs have a home
  mkdir -p docs/superpowers/specs docs/superpowers/plans
  touch docs/superpowers/specs/.gitkeep docs/superpowers/plans/.gitkeep
  success "  Cleared template docs from docs/superpowers/ (kept directory for new specs/plans)."
fi

# Remove ClaudeTemplate-specific HTML docs (architecture diagram + GitHub Pages index)
[[ -f "docs/ARCHITECTURE.html" ]] && rm -f docs/ARCHITECTURE.html && success "  Removed docs/ARCHITECTURE.html."
[[ -f "docs/index.html"        ]] && rm -f docs/index.html        && success "  Removed docs/index.html."

# Clear operational logs — new project starts with empty logs
[[ -f "logs/tool_calls.log"  ]] && : > logs/tool_calls.log  && success "  Cleared logs/tool_calls.log."
[[ -f "logs/agent_calls.log" ]] && : > logs/agent_calls.log && success "  Cleared logs/agent_calls.log."

# Remove session state that has no meaning outside the template repo
[[ -f ".claude/last_session_id" ]] && rm -f .claude/last_session_id && success "  Removed .claude/last_session_id."
[[ -d ".claude/worktrees"       ]] && rm -rf .claude/worktrees       && success "  Removed .claude/worktrees/."

# Remove hook test that targets ClaudeTemplate's own classify_task implementation
[[ -f "hooks/tests/test_classify_task.sh" ]] && rm -f hooks/tests/test_classify_task.sh && success "  Removed hooks/tests/test_classify_task.sh."
# Remove hooks/tests dir only if now empty
[[ -d "hooks/tests" ]] && rmdir hooks/tests 2>/dev/null && success "  Removed empty hooks/tests/." || true

# Clear CHANGELOG to a blank template (keep header, remove any history entries)
if [[ -f "CHANGELOG.md" ]]; then
  cat > CHANGELOG.md <<'EOF'
# Changelog

All notable changes to this project will be documented here.

Format: grouped by feature, written for a human reading months later — not a git log dump.

---

## [Unreleased]
EOF
  success "  Reset CHANGELOG.md to blank template."
fi

# Remove Python bytecode caches left from running ClaudeTemplate's own tests
find . -type d -name "__pycache__" -not -path './.git/*' -exec rm -rf {} + 2>/dev/null || true
find . -name "*.pyc" -o -name "*.pyo" -not -path './.git/*' | xargs rm -f 2>/dev/null || true
success "  Removed __pycache__ and bytecode files."

# ---------------------------------------------------------------------------
# Step 7/9 — Move Claude infrastructure into .claude/
# ---------------------------------------------------------------------------
header "Step 7/9 — Moving Claude infrastructure into .claude/..."

for dir in agents hooks skills tools; do
  if [[ -d "$dir" ]]; then
    mv "$dir" ".claude/$dir"
    success "  Moved $dir/ → .claude/$dir/."
  fi
done

# Update hook command paths in settings.json: hooks/ → .claude/hooks/
sed -i.bak \
  -e 's|"bash hooks/|"bash .claude/hooks/|g' \
  -e 's|"python3 hooks/|"python3 .claude/hooks/|g' \
  .claude/settings.json
rm -f .claude/settings.json.bak
success "  Updated hook paths in .claude/settings.json."

# classify_task.sh has a hardcoded file-path pattern for the hooks dir;
# patch it to match the new location so FORCE_FULL still fires on hook edits.
sed -i.bak 's|\^hooks/|^\.claude/hooks/|g' .claude/hooks/classify_task.sh
rm -f .claude/hooks/classify_task.sh.bak
success "  Patched classify_task.sh path pattern (^hooks/ → ^.claude/hooks/)."

# Write slim CLAUDE.md: project identity + import of orchestrator machinery
cat > CLAUDE.md <<EOF
# CLAUDE.md — Project Instructions

You are an orchestrator in a multi-agent system. Read this file fully before taking any action.

## 🏗️ Project Identity

- **Project:** ${PROJECT_NAME}
- **Stack:** ${TECH_STACK}
- **Owner conventions:** See \`CONVENTIONS.md\`
- **All agents registry:** See \`AGENTS.md\`
- **Current tasks:** See \`TASKS.md\`

@.claude/orchestrator.md
EOF
success "  Written slim CLAUDE.md ($(wc -l < CLAUDE.md) lines) with @.claude/orchestrator.md import."

# ---------------------------------------------------------------------------
# Step 8/9 — Fresh git history
# ---------------------------------------------------------------------------
header "Step 8/9 — Initialising fresh git repository..."

if [[ -d ".git" ]]; then
  rm -rf .git
  success "  Removed existing .git directory."
fi

git init -q
git add .
git commit -q -m "chore: init project from ClaudeTemplate"
success "  Initial commit created."

# ---------------------------------------------------------------------------
# Step 9/9 — Optional GitHub repo creation
# ---------------------------------------------------------------------------
header "Step 9/9 — GitHub repository (optional)"
prompt "Create GitHub repo? [y/N]: "
read -r CREATE_GH
CREATE_GH="${CREATE_GH:-N}"

if [[ "$CREATE_GH" =~ ^[Yy]$ ]]; then
  if ! command -v gh &>/dev/null; then
    warn "  'gh' CLI not found. Install from https://cli.github.com/ then run:"
    warn "    gh repo create \"${PROJECT_NAME}\" --${VISIBILITY} --source=. --remote=origin --push"
  else
    printf "  Creating %s GitHub repo '%s'...\n" "$VISIBILITY" "$PROJECT_NAME"
    REPO_URL=$(gh repo create "$PROJECT_NAME" --"$VISIBILITY" --source=. --remote=origin --push 2>&1 | grep "https://github.com" | head -1 || true)
    if [[ -n "$REPO_URL" ]]; then
      success "  Repository created: ${REPO_URL}"
    else
      warn "  Repository may have been created — check 'gh repo list' to confirm."
    fi
  fi
else
  printf "  Skipped. Push manually later:\n"
  printf "    gh repo create \"%s\" --%s --source=. --remote=origin --push\n" \
    "$PROJECT_NAME" "$VISIBILITY"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
header "=================================================="
success "  Project ready: ${PROJECT_NAME}"
header "=================================================="
printf "\n"
printf "  Project : %s\n" "$PROJECT_NAME"
printf "  Stack   : %s\n" "$TECH_STACK"
printf "  Owner   : %s\n" "$OWNER_EMAIL"
if [[ -n "$IDEA_DOC" ]]; then
  printf "  Idea doc: docs/%s\n" "$(basename "$IDEA_DOC")"
fi
printf "\n"
printf "  Next steps:\n"
printf "    1. Open Claude Code in this directory\n"
if [[ -n "$IDEA_DOC" ]]; then
  printf "    2. TASK-000 is queued: orchestrator will read docs/%s first\n" "$(basename "$IDEA_DOC")"
  printf "    3. Review CONVENTIONS.md (TASK-001) once TASK-000 is done\n"
else
  printf "    2. Run /tasks to see your first tasks\n"
  printf "    3. Complete CONVENTIONS.md (TASK-001)\n"
fi
printf "\n"
