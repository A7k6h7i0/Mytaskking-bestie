#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

echo "==> Flutter pub get"
flutter pub get

echo "==> CocoaPods (macOS native deps)"
pushd macos >/dev/null
pod install
popd >/dev/null

echo "==> Build macOS release"
flutter build macos --release

APP="$ROOT/build/macos/Build/Products/Release/mytaskking_macos.app"
OUT="$ROOT/dist"
rm -rf "$OUT"
mkdir -p "$OUT"

if [[ -d "$APP" ]]; then
  ditto -c -k --sequesterRsrc --keepParent "$APP" "$OUT/mytaskking-macos.zip"
  echo ""
  echo "Build complete."
  echo "  App bundle: $APP"
  echo "  Zip:        $OUT/mytaskking-macos.zip"
  echo ""
  echo "Run locally:"
  echo "  open \"$APP\""
  echo ""
  echo "For distribution outside your Mac, sign and notarize the .app (Apple Developer account required)."
else
  echo "Expected app bundle not found at $APP" >&2
  exit 1
fi
