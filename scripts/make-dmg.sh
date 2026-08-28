#!/bin/bash
# Builds a drag-to-install disk image: dist/SideNotch-<version>.dmg
set -euo pipefail
cd "$(dirname "$0")/.."

scripts/make-app.sh
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' dist/SideNotch.app/Contents/Info.plist)"

STAGE="$(mktemp -d /tmp/sidenotch-dmg.XXXXXX)"
trap 'rm -rf "$STAGE"' EXIT
cp -R dist/SideNotch.app "$STAGE/"
xattr -rc "$STAGE/SideNotch.app" 2>/dev/null || true
ln -s /Applications "$STAGE/Applications"
cat > "$STAGE/READ ME FIRST.txt" <<'NOTE'
AI Side Notch — first launch

Drag SideNotch into Applications. Because the app isn't notarized by Apple,
macOS blocks the very first launch ("Apple could not verify...").

Two ways to unblock it — pick one:

1. Open the app once and click Done (NOT Move to Trash), then go to
   System Settings > Privacy & Security, scroll down, and click "Open Anyway".

2. Or run this in Terminal:
   xattr -dr com.apple.quarantine /Applications/SideNotch.app

Tip: installing from Terminal skips the block entirely:
   curl -fsSL https://raw.githubusercontent.com/AngeloLandiza/MacOS-AI-Usage-Side-Notch-Tracker/main/scripts/install.sh | bash
NOTE

DMG="dist/SideNotch-$VERSION.dmg"
rm -f "$DMG"
hdiutil create -volname "AI Side Notch" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
echo "Built $DMG"
