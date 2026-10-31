#!/usr/bin/env bash
# Builds Pier.app, reinstalls it into /Applications, and clears its stale Accessibility entry
# on the way.
#
# Ad-hoc signing gives every build a new cdhash, so the Accessibility grant macOS is holding no
# longer matches the binary: the app stays listed, stops being trusted, and notification badges
# go blank with no visible reason. Resetting the entry before the copy means the freshly
# launched build asks again instead of sitting there as a grant that no longer applies.
#
# This does not make the grant survive rebuilds. Only a stable signing identity would.
set -euo pipefail
cd "$(dirname "$0")"

./build.sh

echo "→ quitting Pier"
osascript -e 'tell application "Pier" to quit' 2>/dev/null || true
sleep 1
pkill -f '/Applications/Pier.app/Contents/MacOS/Pier' 2>/dev/null || true
sleep 1

echo "→ clearing the Accessibility entry for app.openware.pier"
tccutil reset Accessibility app.openware.pier || true

echo "→ installing to /Applications"
rm -rf /Applications/Pier.app
cp -R Pier.app /Applications/
xattr -cr /Applications/Pier.app

echo "→ launching"
open /Applications/Pier.app
