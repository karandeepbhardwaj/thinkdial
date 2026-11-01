#!/usr/bin/env bash
# Wrap the ThinkDial executable in an ad-hoc signed .app and zip it.
# Usage: Scripts/package-app.sh /path/to/ThinkDial
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BINARY="${1:-}"

if [[ -z "$BINARY" ]]; then
  echo "Pass the ThinkDial executable produced by xcodebuild or swift build." >&2
  exit 1
fi
if [[ ! -f "$BINARY" ]]; then
  echo "Binary not found: $BINARY" >&2
  exit 1
fi
if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "package-app.sh needs macOS (codesign, ditto)." >&2
  exit 1
fi

DIST="$ROOT/dist"
APP="$DIST/ThinkDial.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BINARY" "$APP/Contents/MacOS/ThinkDial"
chmod +x "$APP/Contents/MacOS/ThinkDial"
cp "$ROOT/App/Support/Info.plist" "$APP/Contents/Info.plist"

codesign --force --deep --sign - "$APP"
codesign --verify --verbose=2 "$APP"

ZIP="$DIST/ThinkDial-macos.zip"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
echo "Wrote $ZIP"
