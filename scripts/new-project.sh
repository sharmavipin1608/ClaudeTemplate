#!/bin/bash
# =============================================================================
# new-project.sh — Local machine convenience script for creating new projects
#                  from ClaudeTemplate.
#
# Install:
#   1. Copy this file to ~/Projects/new-project.sh
#   2. chmod +x ~/Projects/new-project.sh
#   3. Set TEMPLATE_REPO_URL below (or export it as an env var) to the GitHub
#      URL of your ClaudeTemplate fork/copy, e.g.:
#        TEMPLATE_REPO_URL="https://github.com/yourname/ClaudeTemplate.git"
#
# Usage:
#   ~/Projects/new-project.sh
#   PROJECTS_DIR=/path/to/workspace ~/Projects/new-project.sh
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration — edit this after copying the script to ~/Projects/
# ---------------------------------------------------------------------------
TEMPLATE_REPO_URL="${TEMPLATE_REPO_URL:-https://github.com/sharmavipin1608/ClaudeTemplate.git}"
PROJECTS_DIR="${PROJECTS_DIR:-${HOME}/Projects}"

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

# Check git is installed
if ! command -v git &>/dev/null; then
  error "git is not installed."
  printf "  Install git before running this script:\n"
  printf "    macOS  : brew install git\n"
  printf "    Ubuntu : sudo apt-get install git\n"
  printf "    Fedora : sudo dnf install git\n"
  exit 1
fi

# Check the template repo URL has been set
if [[ "$TEMPLATE_REPO_URL" == "{{TEMPLATE_REPO_URL}}" || -z "$TEMPLATE_REPO_URL" ]]; then
  error "TEMPLATE_REPO_URL has not been set."
  printf "\n"
  printf "  Open this script and replace the placeholder:\n"
  printf "    TEMPLATE_REPO_URL=\"{{TEMPLATE_REPO_URL}}\"\n"
  printf "  with your actual ClaudeTemplate GitHub URL, e.g.:\n"
  printf "    TEMPLATE_REPO_URL=\"https://github.com/yourname/ClaudeTemplate.git\"\n"
  printf "\n"
  printf "  Alternatively, export the variable before running:\n"
  printf "    export TEMPLATE_REPO_URL=\"https://github.com/yourname/ClaudeTemplate.git\"\n"
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

# ---------------------------------------------------------------------------
# Check target directory doesn't already exist
# ---------------------------------------------------------------------------
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
  error "git clone failed. Check the TEMPLATE_REPO_URL and your network connection."
  exit 1
fi

success "  Clone complete."

# ---------------------------------------------------------------------------
# Run bootstrap.sh
# ---------------------------------------------------------------------------
header "=================================================="
printf "  Next step: run bootstrap.sh to set up your project.\n"
printf "\n"
printf "    cd %s\n" "$TARGET_DIR"
printf "    ./bootstrap.sh\n"
header "=================================================="

printf "\n"
prompt "Run ./bootstrap.sh now? [Y/n]: "
read -r RUN_BOOTSTRAP
RUN_BOOTSTRAP="${RUN_BOOTSTRAP:-Y}"

if [[ "$RUN_BOOTSTRAP" =~ ^[Yy]$ ]]; then
  header "Running bootstrap.sh..."
  cd "$TARGET_DIR"
  bash ./bootstrap.sh
else
  printf "\n"
  printf "  Skipped. When you're ready, run:\n"
  printf "    cd %s\n" "$TARGET_DIR"
  printf "    ./bootstrap.sh\n"
  printf "\n"
fi
