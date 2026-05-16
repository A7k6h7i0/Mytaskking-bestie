#!/usr/bin/env bash
#
# Bestie — daily database backup
#
# Dumps Postgres to a timestamped file, gzips it, optionally uploads to R2,
# then prunes anything older than RETENTION_DAYS in the local backup dir.
#
# Run from cron, e.g.:
#   30 3 * * *   /opt/bestie/deploy/backup.sh >>/var/log/bestie/backup.log 2>&1
#
# Restore:
#   gunzip -c bestie-2026-05-14.sql.gz | psql "$DATABASE_URL"

set -euo pipefail

: "${DATABASE_URL:?DATABASE_URL must be set}"
BACKUP_DIR="${BACKUP_DIR:-/var/backups/bestie}"
RETENTION_DAYS="${RETENTION_DAYS:-14}"
TS=$(date -u +%Y-%m-%dT%H%M%SZ)
OUT="$BACKUP_DIR/bestie-$TS.sql.gz"

mkdir -p "$BACKUP_DIR"

echo "[$(date -u +%FT%TZ)] backup.start → $OUT"
pg_dump --no-owner --no-privileges --format=plain "$DATABASE_URL" | gzip -9 > "$OUT"

SIZE=$(du -h "$OUT" | cut -f1)
echo "[$(date -u +%FT%TZ)] backup.local_done size=$SIZE"

# Optional: ship to Cloudflare R2 (requires `aws` cli configured with R2 endpoint)
if [[ -n "${R2_BACKUP_BUCKET:-}" && -n "${R2_ENDPOINT:-}" ]]; then
  aws --endpoint-url "$R2_ENDPOINT" s3 cp "$OUT" "s3://$R2_BACKUP_BUCKET/db/$(basename "$OUT")"
  echo "[$(date -u +%FT%TZ)] backup.uploaded → s3://$R2_BACKUP_BUCKET/db/"
fi

# Prune old local backups
find "$BACKUP_DIR" -name 'bestie-*.sql.gz' -type f -mtime "+$RETENTION_DAYS" -delete
echo "[$(date -u +%FT%TZ)] backup.pruned older_than=${RETENTION_DAYS}d"
