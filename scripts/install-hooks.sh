#!/bin/bash
set -euo pipefail

#######################################
# Install Git Hooks
#######################################
#
# Points git at the checked-in hooks in .githooks/ so every clone runs the
# same ones. Re-run after cloning; the setting is local to your clone and is
# not itself version controlled.
#
# Usage:
#   ./scripts/install-hooks.sh
#   ./scripts/install-hooks.sh --uninstall
#######################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

cd "$REPO_ROOT"

if [[ "${1:-}" == "--uninstall" ]]; then
  git config --unset core.hooksPath || true
  echo -e "${GREEN}✅ Removed core.hooksPath; git will use .git/hooks again${NC}"
  exit 0
fi

git config core.hooksPath .githooks
echo -e "${GREEN}✅ core.hooksPath = $(git config core.hooksPath)${NC}"
echo -e "${BLUE}   Active hooks:${NC}"
for hook in "${REPO_ROOT}"/.githooks/*; do
  [[ -f "$hook" ]] || continue
  if [[ -x "$hook" ]]; then
    echo -e "     $(basename "$hook")"
  else
    echo -e "     ${YELLOW}$(basename "$hook") (not executable -- run: chmod +x $hook)${NC}"
  fi
done

# The common dir gives the default hooks location; --git-path would honour the
# core.hooksPath just set. .sample files are git's own, not hooks.
# --git-path honours core.hooksPath, which we have just set; the git common
# dir gives the default location regardless, and is shared by worktrees.
LEGACY_HOOKS_DIR="$(git rev-parse --git-common-dir)/hooks"
if [[ -d "$LEGACY_HOOKS_DIR" ]] && find "$LEGACY_HOOKS_DIR" -maxdepth 1 -type f \
     ! -name '*.sample' -print -quit 2>/dev/null | read -r _; then
  echo -e "${YELLOW}ℹ️  Hooks remain in ${LEGACY_HOOKS_DIR} and are now ignored.${NC}"
  echo -e "${YELLOW}   Delete them once you are happy with the checked-in ones.${NC}"
fi

if ! command -v gitleaks &>/dev/null; then
  echo -e "${YELLOW}⚠️  gitleaks is not installed; the hooks will skip the secret scan.${NC}"
  echo -e "${YELLOW}   Install with: brew install gitleaks${NC}"
fi
