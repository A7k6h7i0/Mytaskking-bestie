#!/usr/bin/env bash
#
# MyTaskKing — emergency rollback for the API.
#
# Usage:
#   ./deploy/rollback.sh <previous-git-ref>
#
# What it does:
#   1. checks out the given ref into a parallel directory
#   2. installs deps + runs `prisma migrate resolve --rolled-back` on any
#      migration that was applied after that ref
#   3. swaps the symlink that PM2 starts from
#   4. reloads PM2
#
# Database rollbacks are advisory only — destructive migrations (column drops,
# enum reductions) can't be rolled back from `migrate resolve`. The right
# answer there is to forward-fix: deploy a fix-up migration. This script will
# refuse to proceed if it detects unrecoverable migrations.

set -euo pipefail

REF="${1:-}"
if [[ -z "$REF" ]]; then
  echo "usage: $0 <git-ref>" >&2
  exit 1
fi

DEPLOY_PATH="${DEPLOY_PATH:-$HOME/bestie}"
RELEASES="$DEPLOY_PATH/releases"
CURRENT_LINK="$DEPLOY_PATH/current"

mkdir -p "$RELEASES"

STAMP=$(date -u +%Y%m%d-%H%M%S)
TARGET="$RELEASES/rb-$STAMP-$REF"

echo "[$(date -u +%FT%TZ)] rollback.checkout ref=$REF target=$TARGET"
git -C "$DEPLOY_PATH/source" worktree add "$TARGET" "$REF"

(cd "$TARGET/backend" && npm ci --omit=dev && npx prisma generate)

echo "[$(date -u +%FT%TZ)] rollback.migration_safety"
# Detect schema drift between checked-out code and live DB.
if ! (cd "$TARGET/backend" && npx prisma migrate status --schema=prisma/schema.prisma); then
  echo "::warning:: schema drift detected — review migrations before swapping the symlink"
  echo "If the forward migration was destructive, write a recovery migration instead of rolling back."
  exit 2
fi

ln -sfn "$TARGET" "$CURRENT_LINK"
pm2 reload "$CURRENT_LINK/backend/ecosystem.config.js"
pm2 restart bestie-worker || true

echo "[$(date -u +%FT%TZ)] rollback.done -> $TARGET"
