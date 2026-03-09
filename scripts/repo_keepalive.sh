#!/bin/zsh
set -euo pipefail

REPO_DIR="${1:-REPO_ROOT_PLACEHOLDER}"
KEEPALIVE_FILE=".github/keepalive.md"
DEFAULT_BRANCH="${DEFAULT_BRANCH:-main}"
STAMP="$(date -u +%Y-%m-%d)"

cd "$REPO_DIR"

mkdir -p .github
printf "Last keepalive: %s\n" "$STAMP" > "$KEEPALIVE_FILE"

git add "$KEEPALIVE_FILE"

if git diff --cached --quiet; then
  exit 0
fi

git commit -m "chore(repo): refresh keepalive timestamp"
git push origin "$DEFAULT_BRANCH"
