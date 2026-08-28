#!/bin/bash
# One-line installer:
#   curl -fsSL https://raw.githubusercontent.com/AngeloLandiza/MacOS-AI-Usage-Side-Notch-Tracker/main/scripts/install.sh | bash
# Downloads the latest release DMG and installs SideNotch into /Applications.
# Terminal downloads carry no quarantine flag, so Gatekeeper never blocks this.
set -euo pipefail

REPO="AngeloLandiza/MacOS-AI-Usage-Side-Notch-Tracker"
DMG_URL="$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" \
    | grep -o '"browser_download_url": *"[^"]*\.dmg"' | head -1 | cut -d'"' -f4)"
if [ -z "$DMG_URL" ]; then
    echo "Could not find a DMG in the latest release of $REPO." >&2
    exit 1
fi

TMP="$(mktemp -d /tmp/sidenotch-install.XXXXXX)"
MOUNT="$TMP/mnt"
cleanup() {
    hdiutil detach "$MOUNT" -quiet 2>/dev/null || true
    rm -rf "$TMP"
}
trap cleanup EXIT

echo "Downloading $DMG_URL"
curl -fL --progress-bar -o "$TMP/SideNotch.dmg" "$DMG_URL"
mkdir "$MOUNT"
hdiutil attach "$TMP/SideNotch.dmg" -mountpoint "$MOUNT" -nobrowse -quiet

# Stop any running copy (plain signal: no automation prompts, never launches the app).
killall SideNotch 2>/dev/null || true
for _ in $(seq 1 25); do pgrep -xq SideNotch || break; sleep 0.2; done
rm -rf /Applications/SideNotch.app
cp -R "$MOUNT/SideNotch.app" /Applications/
xattr -dr com.apple.quarantine /Applications/SideNotch.app 2>/dev/null || true

echo "Installed /Applications/SideNotch.app"
open /Applications/SideNotch.app
