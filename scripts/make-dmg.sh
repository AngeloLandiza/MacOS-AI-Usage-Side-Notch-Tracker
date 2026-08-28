#!/bin/bash
# Builds a drag-to-install disk image: dist/SideNotch-<version>.dmg
set -euo pipefail
cd "$(dirname "$0")/.."

scripts/make-app.sh
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' dist/SideNotch.app/Contents/Info.plist)"

STAGE="$(mktemp -d /tmp/sidenotch-dmg.XXXXXX)"
trap 'rm -rf "$STAGE"' EXIT
cp -R dist/SideNotch.app "$STAGE/"
ln -s /Applications "$STAGE/Applications"

DMG="dist/SideNotch-$VERSION.dmg"
rm -f "$DMG"
hdiutil create -volname "AI Side Notch" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
echo "Built $DMG"
