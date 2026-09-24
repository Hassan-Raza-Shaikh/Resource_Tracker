#!/bin/bash
# Builds a Release copy of Resource Tracker and installs it in /Applications, replacing any
# previous install, then launches it. Run after pulling or changing code:
#
#     ./install.sh
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="Resource Tracker.app"
BUNDLE_ID="com.hassan.ResourceTracker"
DERIVED="build/DerivedData"
BUILT="$DERIVED/Build/Products/Release/$APP_NAME"
DEST="/Applications/$APP_NAME"

echo "Building Release…"
# Ad-hoc signed: runs on this Mac. Distribution builds are signed with your Team in Xcode.
xcodebuild -project ResourceTracker.xcodeproj -scheme ResourceTracker -configuration Release \
    -derivedDataPath "$DERIVED" CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="-" DEVELOPMENT_TEAM="" \
    build 2>&1 | grep -E "\.(swift|plist|xcassets|json)[^ ]*: (error|warning):|\*\* BUILD" || true
[ -d "$BUILT" ] || { echo "Build failed."; exit 1; }

echo "Quitting any running copy…"
osascript -e "tell application id \"$BUNDLE_ID\" to quit" >/dev/null 2>&1 || true
for _ in $(seq 1 20); do pgrep -f "$APP_NAME/Contents/MacOS/" >/dev/null || break; sleep 0.25; done
pkill -f "$APP_NAME/Contents/MacOS/" 2>/dev/null || true

# An older copy in ~/Applications would shadow this one in Spotlight and Launchpad.
# Move it to the Trash rather than deleting it, so it can be recovered.
OLD="$HOME/Applications/$APP_NAME"
if [ -d "$OLD" ]; then
    mv "$OLD" "$HOME/.Trash/Resource Tracker (replaced $(date '+%Y-%m-%d %H.%M.%S')).app"
    echo "Moved the old copy in ~/Applications to the Trash."
fi

echo "Installing to $DEST…"
rm -rf "$DEST"
ditto "$BUILT" "$DEST"
# Register with Launch Services and bump the bundle date so Finder and the Dock pick up a new icon.
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$DEST"
touch "$DEST"

open "$DEST"
echo "Done — Resource Tracker is in /Applications and running."
