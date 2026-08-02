#!/usr/bin/env bash
# Backs up config/ and data/ into a single timestamped tarball, then
# commits that tarball onto a dedicated `backups` branch (kept separate
# from `master` so binary blobs don't bloat your source history) and
# pushes it if a remote is configured.
#
# Usage: ./backups/backup.sh [--no-push]
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STAMP="$(date +%Y%m%d-%H%M%S)"
FILENAME="backup-$STAMP.tar.gz"
OUT="$PROJECT_ROOT/backups/$FILENAME"
BRANCH="backups"
NO_PUSH="${1:-}"

cd "$PROJECT_ROOT"

tar czf "$OUT" \
  --exclude='backups' \
  config \
  data

echo "Backup written to $OUT"

# Keep only the last 14 backups on disk
ls -1t "$PROJECT_ROOT"/backups/backup-*.tar.gz 2>/dev/null | tail -n +15 | xargs -r rm --

# --- git side: commit this backup onto its own orphan branch ---
if ! command -v git >/dev/null 2>&1; then
  echo "git not found - skipping git backup step."
  exit 0
fi
if [ ! -d .git ]; then
  echo "Not a git repo - skipping git backup step."
  exit 0
fi

CURRENT_BRANCH="$(git rev-parse --abbrev-ref HEAD)"

# Create the orphan backups branch the first time it's needed.
# Done via plumbing (no `git checkout --orphan`) so the main working
# directory/checkout is never touched or switched.
if ! git show-ref --verify --quiet "refs/heads/$BRANCH"; then
  EMPTY_TREE="$(git hash-object -t tree /dev/null)"
  INIT_COMMIT="$(git commit-tree "$EMPTY_TREE" -m "init backups branch")"
  git branch "$BRANCH" "$INIT_COMMIT"
fi

# Use a worktree so we don't disturb your actual working directory / master checkout.
WORKTREE_DIR="$PROJECT_ROOT/.backup-worktree"
if [ ! -d "$WORKTREE_DIR" ]; then
  git worktree add -B "$BRANCH" "$WORKTREE_DIR" "$BRANCH" >/dev/null
fi

cp "$OUT" "$WORKTREE_DIR/$FILENAME"
git -C "$WORKTREE_DIR" add "$FILENAME"
git -C "$WORKTREE_DIR" commit -m "backup: $STAMP" >/dev/null

echo "Committed $FILENAME to '$BRANCH' branch."

if [ "$NO_PUSH" != "--no-push" ] && git remote get-url origin >/dev/null 2>&1; then
  git -C "$WORKTREE_DIR" push origin "$BRANCH"
  echo "Pushed '$BRANCH' to origin."
else
  echo "Skipping push (no remote configured, or --no-push passed)."
fi
