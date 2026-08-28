#!/bin/bash
# Builds SideNotch.app into ./dist. Usage: scripts/make-app.sh
set -euo pipefail
cd "$(dirname "$0")/.."

# Build outside the repo: iCloud-synced folders (Desktop/Documents) add Finder
# metadata that breaks codesigning.
SCRATCH="$(mktemp -d /tmp/sidenotch-build.XXXXXX)"
trap 'rm -rf "$SCRATCH"' EXIT

swift build -c release --scratch-path "$SCRATCH"
BIN="$(swift build -c release --scratch-path "$SCRATCH" --show-bin-path)/SideNotch"

APP="dist/SideNotch.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/SideNotch"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>SideNotch</string>
    <key>CFBundleDisplayName</key><string>AI Side Notch</string>
    <key>CFBundleIdentifier</key><string>com.angelolandiza.SideNotch</string>
    <key>CFBundleExecutable</key><string>SideNotch</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

xattr -rc "$APP" 2>/dev/null || true
codesign --force --sign - "$APP"
echo "Built $APP"
