#!/usr/bin/env bash
# Builds Switchboard.app into ./build. Usage: scripts/build-app.sh [release|debug]
# SWITCHBOARD_UNIVERSAL=1 builds for Apple silicon and Intel; SWITCHBOARD_SIGN_IDENTITY
# picks the signing identity.
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-release}"
if [ "${SWITCHBOARD_UNIVERSAL:-0}" = 1 ]; then
  ARCH_FLAGS=(--arch arm64 --arch x86_64)
else
  ARCH_FLAGS=()
fi
swift build -c "$CONFIG" ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"}
BIN_DIR="$(swift build -c "$CONFIG" ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"} --show-bin-path)"

APP="build/Switchboard.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$BIN_DIR/Switchboard" "$APP/Contents/MacOS/Switchboard"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# Sparkle (updates). Switchboard isn't sandboxed, so Sparkle's XPC services aren't needed.
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework"
cp -R "$BIN_DIR/Sparkle.framework" "$SPARKLE"
rm -rf "$SPARKLE/Versions/B/XPCServices" "$SPARKLE/XPCServices"

# Signing identity: SWITCHBOARD_SIGN_IDENTITY if set, else a Developer ID, else a local
# identity so macOS remembers the Bluetooth and Automation permissions across rebuilds,
# else ad-hoc.
IDENTITY="${SWITCHBOARD_SIGN_IDENTITY:-}"
if [ -z "$IDENTITY" ]; then
  IDENTITY="$(security find-identity -p codesigning 2>/dev/null \
    | awk -F'"' '/Developer ID Application/ { print $2; exit }')"
fi
if [ -z "$IDENTITY" ]; then
  IDENTITY="$(security find-identity -p codesigning 2>/dev/null \
    | awk -F'"' '/Pane Local Signing|Veil Local Signing|Apple Development/ { print $2; exit }')"
fi

# Hardened runtime always, so local builds behave like the notarized release. A secure
# timestamp is required for notarization and only works with Apple-issued identities.
SIGN=(codesign --force --options runtime --sign "${IDENTITY:--}")
ENTITLEMENTS=Resources/Switchboard.entitlements
case "$IDENTITY" in
  "Developer ID Application"*) SIGN+=(--timestamp) ;;
  *)
    # Without an Apple Team ID the runtime refuses to load Sparkle.framework, so local
    # and ad-hoc builds allow libraries signed by anyone.
    ENTITLEMENTS="build/Switchboard-local.entitlements"
    cp Resources/Switchboard.entitlements "$ENTITLEMENTS"
    /usr/libexec/PlistBuddy -c "Add :com.apple.security.cs.disable-library-validation bool true" "$ENTITLEMENTS"
    ;;
esac

# Inside out: Sparkle's helpers, the framework, then the app.
"${SIGN[@]}" "$SPARKLE/Versions/B/Autoupdate"
"${SIGN[@]}" "$SPARKLE/Versions/B/Updater.app"
"${SIGN[@]}" "$SPARKLE"
"${SIGN[@]}" --entitlements "$ENTITLEMENTS" "$APP"

if [ -n "$IDENTITY" ]; then
  echo "Signed with: $IDENTITY"
else
  echo "Signed ad-hoc. Permissions may be asked for again after each rebuild."
fi
echo "Built $APP"
