#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

echo "==> Flutter pub get"
flutter pub get

echo "==> Build Linux release bundle"
flutter build linux --release

BUNDLE="$ROOT/build/linux/x64/release/bundle"
OUT="$ROOT/dist"
rm -rf "$OUT"
mkdir -p "$OUT"

ARCHIVE="mytaskking-linux-x64.tar.gz"
tar -czf "$OUT/$ARCHIVE" -C "$BUNDLE" .

cat <<EOF

Build complete.

Run locally:
  cd "$BUNDLE" && ./mytaskking_linux

Share with users:
  $OUT/$ARCHIVE

Extract on target machine:
  tar -xzf $ARCHIVE
  ./mytaskking_linux

Optional .desktop file is not bundled here — add one if you ship to many users.
EOF
