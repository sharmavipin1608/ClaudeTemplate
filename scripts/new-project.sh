#!/bin/bash
# =============================================================================
# new-project.sh — Local machine convenience script for creating new projects
#                  from ClaudeTemplate.
#
# Install:
#   1. Copy this file to ~/Projects/new-project.sh
#   2. chmod +x ~/Projects/new-project.sh
#
# Usage:
#   ~/Projects/new-project.sh
#   ~/Projects/new-project.sh --doc ~/path/to/idea.md
#   PROJECTS_DIR=/path/to/workspace ~/Projects/new-project.sh
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration — edit this after copying the script to ~/Projects/
# ---------------------------------------------------------------------------
TEMPLATE_REPO_URL="${TEMPLATE_REPO_URL:-https://github.com/sharmavipin1608/ClaudeTemplate.git}"
PROJECTS_DIR="${PROJECTS_DIR:-${HOME}/Projects}"

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
      printf "Unknown argument: %s\n" "$1" >&2
      printf "Usage: new-project.sh [--doc /path/to/idea.md]\n" >&2
      exit 1
      ;;
  esac
done

if [[ -n "$IDEA_DOC" && ! -f "$IDEA_DOC" ]]; then
  printf "ERROR: Idea doc not found: %s\n" "$IDEA_DOC" >&2
  exit 1
fi

# Resolve to absolute path so it's still valid after cd
if [[ -n "$IDEA_DOC" ]]; then
  IDEA_DOC=$(cd "$(dirname "$IDEA_DOC")" && pwd)/$(basename "$IDEA_DOC")
fi

# ---------------------------------------------------------------------------
# ANSI color helpers
# ---------------------------------------------------------------------------
GREEN='\033[1;32m'
CYAN='\033[0;36m'
RED='\033[0;31m'
RESET='\033[0m'

header()  { printf "\n${GREEN}%s${RESET}\n" "$*"; }
prompt()  { printf "${CYAN}%s${RESET}" "$*"; }
success() { printf "${GREEN}%s${RESET}\n" "$*"; }
error()   { printf "${RED}ERROR: %s${RESET}\n" "$*" >&2; }

# ---------------------------------------------------------------------------
# Pre-flight checks
# ---------------------------------------------------------------------------
if ! command -v git &>/dev/null; then
  error "git is not installed."
  printf "  macOS  : brew install git\n"
  printf "  Ubuntu : sudo apt-get install git\n"
  exit 1
fi

if [[ "$TEMPLATE_REPO_URL" == "{{TEMPLATE_REPO_URL}}" || -z "$TEMPLATE_REPO_URL" ]]; then
  error "TEMPLATE_REPO_URL has not been set."
  printf "  Open this script and set TEMPLATE_REPO_URL to your ClaudeTemplate GitHub URL.\n"
  exit 1
fi

# ---------------------------------------------------------------------------
# Banner
# ---------------------------------------------------------------------------
header "=================================================="
header "  ClaudeTemplate — New Project Setup"
header "=================================================="
printf "  Projects directory : %s\n" "$PROJECTS_DIR"
printf "  Template repo      : %s\n" "$TEMPLATE_REPO_URL"
[[ -n "$IDEA_DOC" ]] && printf "  Idea doc           : %s\n" "$IDEA_DOC"
printf "\n"

# ---------------------------------------------------------------------------
# Ask for project name
# ---------------------------------------------------------------------------
prompt "Project name: "
read -r PROJECT_NAME

if [[ -z "$PROJECT_NAME" ]]; then
  error "Project name cannot be empty."
  exit 1
fi

TARGET_DIR="${PROJECTS_DIR}/${PROJECT_NAME}"

if [[ -e "$TARGET_DIR" ]]; then
  error "Directory already exists: ${TARGET_DIR}"
  printf "  Choose a different project name or remove the existing directory.\n"
  exit 1
fi

# ---------------------------------------------------------------------------
# Clone the template
# ---------------------------------------------------------------------------
header "Cloning ClaudeTemplate into ${TARGET_DIR}..."

if ! git clone "$TEMPLATE_REPO_URL" "$TARGET_DIR"; then
  error "git clone failed. Check TEMPLATE_REPO_URL and your network connection."
  exit 1
fi

success "  Clone complete."

# ---------------------------------------------------------------------------
# Run bootstrap.sh
# ---------------------------------------------------------------------------
BOOTSTRAP_ARGS=""
[[ -n "$IDEA_DOC" ]] && BOOTSTRAP_ARGS="--doc \"${IDEA_DOC}\""

header "=================================================="
printf "  Next step: run bootstrap.sh to set up your project.\n"
printf "\n"
printf "    cd %s\n" "$TARGET_DIR"
printf "    ./bootstrap.sh %s\n" "$BOOTSTRAP_ARGS"
header "=================================================="

printf "\n"
prompt "Run ./bootstrap.sh now? [Y/n]: "
read -r RUN_BOOTSTRAP
RUN_BOOTSTRAP="${RUN_BOOTSTRAP:-Y}"

if [[ "$RUN_BOOTSTRAP" =~ ^[Yy]$ ]]; then
  header "Running bootstrap.sh..."
  cd "$TARGET_DIR"
  if [[ -n "$IDEA_DOC" ]]; then
    bash ./bootstrap.sh --doc "$IDEA_DOC"
  else
    bash ./bootstrap.sh
  fi
else
  printf "\n  Skipped. When ready:\n"
  printf "    cd %s\n" "$TARGET_DIR"
  printf "    ./bootstrap.sh %s\n" "$BOOTSTRAP_ARGS"
  printf "\n"
fi
