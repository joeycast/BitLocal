#!/bin/zsh
set -euo pipefail

REPO_DIR="${1:-REPO_ROOT_PLACEHOLDER}"
KEEPALIVE_FILE=".github/keepalive.md"
DEFAULT_BRANCH="${DEFAULT_BRANCH:-main}"
REMOTE_NAME="${REMOTE_NAME:-origin}"
STAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

cd "$REPO_DIR"

git rev-parse --is-inside-work-tree >/dev/null

git fetch "$REMOTE_NAME" "$DEFAULT_BRANCH"
git checkout "$DEFAULT_BRANCH"
git pull --ff-only "$REMOTE_NAME" "$DEFAULT_BRANCH"

mkdir -p .github
printf "Last keepalive: %s\n" "$STAMP" > "$KEEPALIVE_FILE"

git add "$KEEPALIVE_FILE"

if git diff --cached --quiet; then
  exit 0
fi

git commit --only "$KEEPALIVE_FILE" -m "chore(repo): refresh keepalive timestamp"
git push "$REMOTE_NAME" "$DEFAULT_BRANCH"
