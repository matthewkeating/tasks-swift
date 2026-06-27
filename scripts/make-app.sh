#!/bin/bash
#
# Assembles a macOS .app bundle around the SwiftPM executable.
#
# SwiftPM only produces a bare Mach-O binary in .build/<config>/Tasks. macOS
# frameworks (and the GoogleSignIn SDK in particular) expect a real .app bundle:
# Bundle.main reads Contents/Info.plist for things like GIDClientID, and
# LaunchServices registers the CFBundleURLTypes there so the OAuth redirect
# (com.googleusercontent.apps.…://) can route back to the app. This script
# builds that bundle so debug runs and shipped releases share the same layout.
#
# Usage: scripts/make-app.sh [debug|release]   (defaults to debug)

set -euo pipefail

CONFIG="${1:-debug}"

# Resolve paths relative to the repo root (this script lives in scripts/).
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

APP_NAME="Tasks"
# Ask SwiftPM where it put the binary rather than hard-coding the arch triple.
BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"
BINARY="$BIN_DIR/$APP_NAME"

if [[ ! -x "$BINARY" ]]; then
    echo "error: $BINARY not found — run 'swift build -c $CONFIG' first." >&2
    exit 1
fi

APP="$BIN_DIR/$APP_NAME.app"
CONTENTS="$APP/Contents"

# Rebuild from scratch so a removed/renamed resource never lingers in the bundle.
rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"

cp "$BINARY" "$CONTENTS/MacOS/$APP_NAME"
cp "Sources/Tasks/Info.plist" "$CONTENTS/Info.plist"
cp "Sources/Tasks/AppIcon.icns" "$CONTENTS/Resources/AppIcon.icns"

# Ad-hoc sign the finished bundle. Apple Silicon refuses to launch unsigned
# code, and copying a fresh binary in invalidates any signature SwiftPM applied,
# so re-sign the whole .app. "-" is the ad-hoc identity: no certificate, valid
# only on this machine — enough for local use, not for distribution to others.
codesign --force --sign - "$APP"

echo "Built $APP"
