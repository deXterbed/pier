#!/usr/bin/env bash
# Builds Pier.app. Needs Xcode or the Command Line Tools — nothing else.
set -euo pipefail

cd "$(dirname "$0")"

APP="Pier.app"
CONFIG="${PIER_CONFIG:-release}"

echo "→ compiling ($CONFIG)"
swift build -c "$CONFIG" --product Pier
swift build -c "$CONFIG" --product PierIcon

BIN=".build/$CONFIG"

echo "→ assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/Pier" "$APP/Contents/MacOS/Pier"
cp Info.plist "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

echo "→ drawing the icon"
ICONSET="$(mktemp -d)/Pier.iconset"
mkdir -p "$ICONSET"
"$BIN/PierIcon" "$ICONSET" > /dev/null
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/Pier.icns"
rm -rf "$(dirname "$ICONSET")"

# Ad-hoc signature: enough for macOS to give the app a stable identity on this machine.
# There's no paid certificate here and no notarization, which is why you build it
# yourself instead of downloading a dmg from a stranger.
echo "→ signing (ad-hoc)"
codesign --force --sign - "$APP" 2>/dev/null || echo "  (codesign unavailable — the app still runs)"

echo
echo "Built $(pwd)/$APP"
echo "Run it:  open $APP"
