#!/bin/bash
# bootstrap.sh — Interactive project setup wizard for ClaudeTemplate
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
# Banner
# ---------------------------------------------------------------------------
header "=================================================="
header "  ClaudeTemplate Bootstrap Wizard"
header "=================================================="
printf "This script will configure your new project.\n"
printf "Press Enter to accept defaults shown in [brackets].\n\n"

# ---------------------------------------------------------------------------
# Gather project information
# ---------------------------------------------------------------------------
DEFAULT_NAME=$(basename "$PWD")

prompt "Project name [${DEFAULT_NAME}]: "
read -r INPUT_NAME
PROJECT_NAME="${INPUT_NAME:-$DEFAULT_NAME}"

prompt "Tech stack (e.g. 'Node.js + PostgreSQL'): "
read -r TECH_STACK
if [[ -z "$TECH_STACK" ]]; then
  TECH_STACK="(unspecified)"
fi

prompt "One-line description: "
read -r DESCRIPTION
if [[ -z "$DESCRIPTION" ]]; then
  DESCRIPTION="A project bootstrapped from ClaudeTemplate."
fi

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
  # Escape forward slashes in replacement for use inside sed s///
  local escaped
  escaped=$(printf '%s\n' "$replacement" | sed 's/[\/&]/\\&/g')
  sed -i.bak "s/${pattern}/${escaped}/g" "$file" && rm -f "${file}.bak"
}

# ---------------------------------------------------------------------------
# Collect files to process
# ---------------------------------------------------------------------------
header "Step 1/7 — Replacing placeholders in project files..."

mapfile -t FILES < <(find . -type f \( \
  -name "*.md" \
  -o -name "*.sh" \
  -o -name "*.py" \
  -o -name "*.json" \
\) -not -path './.git/*' 2>/dev/null)

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
# Populate memory/core.md
# ---------------------------------------------------------------------------
header "Step 2/7 — Writing memory/core.md..."

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
# Write CONVENTIONS.md last-reviewed date
# ---------------------------------------------------------------------------
header "Step 3/7 — Stamping CONVENTIONS.md..."

if [[ -f "CONVENTIONS.md" ]]; then
  replace_in_file "{{DATE}}" "$TODAY" "CONVENTIONS.md"
  # Also stamp a "Last reviewed" line if not already present
  if ! grep -q "Last reviewed:" CONVENTIONS.md 2>/dev/null; then
    printf "\n---\n_Last reviewed: %s_\n" "$TODAY" >> CONVENTIONS.md
  fi
  success "  CONVENTIONS.md stamped."
else
  warn "  CONVENTIONS.md not found — skipping."
fi

# ---------------------------------------------------------------------------
# Generate README.md from README_TEMPLATE.md (if template exists)
# ---------------------------------------------------------------------------
header "Step 4/7 — Generating README.md..."

if [[ -f "README_TEMPLATE.md" ]]; then
  cp README_TEMPLATE.md README.md
  replace_in_file "{{PROJECT_NAME}}" "$PROJECT_NAME" "README.md"
  replace_in_file "{{TECH_STACK}}"   "$TECH_STACK"   "README.md"
  replace_in_file "{{DESCRIPTION}}"  "$DESCRIPTION"  "README.md"
  replace_in_file "{{DATE}}"         "$TODAY"         "README.md"
  replace_in_file "{{OWNER_EMAIL}}"  "$OWNER_EMAIL"  "README.md"
  success "  README.md generated from README_TEMPLATE.md."
else
  # Create a minimal README if no template exists
  cat > README.md <<EOF
# ${PROJECT_NAME}

${DESCRIPTION}

**Stack:** ${TECH_STACK}
**Owner:** ${OWNER_EMAIL}
**Created:** ${TODAY}
EOF
  success "  README.md created (no template found, minimal version written)."
fi

# ---------------------------------------------------------------------------
# Remove bootstrap artifacts
# ---------------------------------------------------------------------------
header "Step 5/7 — Removing bootstrap artifacts..."

[[ -f "README_TEMPLATE.md" ]] && rm -f README_TEMPLATE.md && success "  Removed README_TEMPLATE.md."
[[ -d "docs/superpowers"   ]] && rm -rf docs/superpowers   && success "  Removed docs/superpowers/."
[[ -d "scripts"            ]] && rm -rf scripts            && success "  Removed scripts/."

# ---------------------------------------------------------------------------
# Fresh git history
# ---------------------------------------------------------------------------
header "Step 6/7 — Initialising fresh git repository..."

if [[ -d ".git" ]]; then
  rm -rf .git
  success "  Removed existing .git directory."
fi

git init -q
git add .
git commit -q -m "chore: init project from ClaudeTemplate"
success "  Initial commit created."

# ---------------------------------------------------------------------------
# Optional GitHub repo creation
# ---------------------------------------------------------------------------
header "Step 7/7 — GitHub repository (optional)"
prompt "Create GitHub repo? [y/N]: "
read -r CREATE_GH
CREATE_GH="${CREATE_GH:-N}"

if [[ "$CREATE_GH" =~ ^[Yy]$ ]]; then
  if ! command -v gh &>/dev/null; then
    warn "  'gh' CLI not found. Install it from https://cli.github.com/ and then run:"
    warn "    gh repo create \"${PROJECT_NAME}\" --${VISIBILITY} --source=. --remote=origin --push"
  else
    printf "  Creating %s GitHub repo '%s'...\n" "$VISIBILITY" "$PROJECT_NAME"
    REPO_URL=$(gh repo create "$PROJECT_NAME" --"$VISIBILITY" --source=. --remote=origin --push 2>&1 | grep "https://github.com" | head -1 || true)
    if [[ -n "$REPO_URL" ]]; then
      success "  Repository created: ${REPO_URL}"
    else
      warn "  Repository may have been created but URL could not be captured."
      warn "  Check 'gh repo list' or your GitHub dashboard."
    fi
  fi
else
  printf "  Skipped. You can push manually later:\n"
  printf "    gh repo create \"%s\" --%s --source=. --remote=origin --push\n" \
    "$PROJECT_NAME" "$VISIBILITY"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
header "=================================================="
success "  Project ready!"
header "=================================================="
printf "\n"
printf "  Project : %s\n" "$PROJECT_NAME"
printf "  Stack   : %s\n" "$TECH_STACK"
printf "  Owner   : %s\n" "$OWNER_EMAIL"
printf "\n"
printf "  Next steps:\n"
printf "    1. Open Claude Code in this directory\n"
printf "    2. Run /tasks to see your first tasks (TASK-001 and TASK-002)\n"
printf "    3. Complete CONVENTIONS.md to capture your project conventions\n"
printf "    4. Start building!\n"
printf "\n"
