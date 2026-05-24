#!/usr/bin/env bash
#
# MyTaskKing — database restore helper. ALWAYS practice on staging first.
#
# Usage:
#   ./restore.sh /var/backups/mytaskking/mytaskking-2026-05-14T030000Z.sql.gz
#
# This script:
#   1. confirms the operator wants to overwrite the target DB
#   2. drops + recreates the schema in a single transaction
#   3. streams the gzipped dump into psql
#
# It does NOT delete files in storage (Cloudinary / R2) — those are
# eventually-consistent with the DB; a restore that points at the same
# storage buckets will recover. If you need to roll those back too, restore
# from the dated R2 snapshot for the same day.

set -euo pipefail

: "${DATABASE_URL:?DATABASE_URL must be set}"

BACKUP_FILE="${1:-}"
if [[ -z "$BACKUP_FILE" || ! -f "$BACKUP_FILE" ]]; then
  echo "usage: $0 <path/to/mytaskking-*.sql.gz>" >&2
  exit 1
fi

echo "About to restore:"
echo "  file:        $BACKUP_FILE"
echo "  database:    ${DATABASE_URL%%\?*}"
read -rp "Type 'restore' to continue: " ans
[[ "$ans" == "restore" ]] || { echo "aborted"; exit 1; }

echo "[$(date -u +%FT%TZ)] restore.start"
gunzip -c "$BACKUP_FILE" | psql --set ON_ERROR_STOP=1 "$DATABASE_URL"
echo "[$(date -u +%FT%TZ)] restore.done"
