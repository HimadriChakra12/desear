#!/usr/bin/env bash
# Restores config/ and data/ from a backup tarball.
#
# Usage:
#   ./backups/restore.sh backups/backup-YYYYMMDD-HHMMSS.tar.gz   # local file
#   ./backups/restore.sh --from-git backup-YYYYMMDD-HHMMSS.tar.gz # pull from 'backups' branch
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BRANCH="backups"

if [ $# -eq 2 ] && [ "$1" == "--from-git" ]; then
  FILENAME="$2"
  cd "$PROJECT_ROOT"
  git fetch origin "$BRANCH" 2>/dev/null || true
  TMP="$(mktemp -d)"
  git worktree add --detach "$TMP" "origin/$BRANCH" >/dev/null 2>&1 \
    || git worktree add --detach "$TMP" "$BRANCH" >/dev/null
  ARCHIVE="$TMP/$FILENAME"
  if [ ! -f "$ARCHIVE" ]; then
    echo "No such backup on '$BRANCH': $FILENAME"
    git worktree remove "$TMP" --force
    exit 1
  fi
elif [ $# -eq 1 ]; then
  ARCHIVE="$1"
else
  echo "Usage: $0 <backup-file.tar.gz>"
  echo "       $0 --from-git <backup-file.tar.gz>   (pulls from '$BRANCH' branch)"
  exit 1
fi

echo "This will overwrite ./config and ./data with the contents of $ARCHIVE"
read -p "Continue? [y/N] " confirm
if [ "$confirm" != "y" ]; then
  echo "Aborted."
  [ -n "${TMP:-}" ] && git worktree remove "$TMP" --force 2>/dev/null || true
  exit 0
fi

# docker compose stop before restoring to avoid file locks / partial writes
(cd "$PROJECT_ROOT" && docker compose down) || true

tar xzf "$ARCHIVE" -C "$PROJECT_ROOT"

[ -n "${TMP:-}" ] && git worktree remove "$TMP" --force 2>/dev/null || true

echo "Restore complete. Start the stack again with: docker compose up -d"
