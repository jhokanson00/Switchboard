#!/usr/bin/env bash
# Checks that a built Switchboard.app is fit to hand to users, and fails loudly if not:
# Developer ID signed with the hardened runtime throughout, no entitlement but Apple
# Events (nothing that lets other code into the app), Sparkle loaded only from inside
# the app, and notarized. release.sh runs it on the build, publish.sh on the app in the
# .dmg.
#
#   scripts/check-app.sh path/to/Switchboard.app [version]
set -euo pipefail

APP="${1:?Usage: scripts/check-app.sh path/to/Switchboard.app [version]}"
VERSION="${2:-}"
BIN="$APP/Contents/MacOS/Switchboard"
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"
fail() { echo "check-app: $*" >&2; exit 1; }

codesign --verify --deep --strict "$APP" 2>/dev/null || fail "the signature doesn't verify"

for code in "$APP" "$SPARKLE/Sparkle" "$SPARKLE/Autoupdate" "$SPARKLE/Updater.app"; do
  info="$(codesign -dvv "$code" 2>&1)"
  grep -q '^Authority=Developer ID Application: ' <<<"$info" || fail "$(basename "$code") isn't signed with a Developer ID"
  grep -q '^CodeDirectory .*flags=.*runtime' <<<"$info" || fail "$(basename "$code") doesn't use the hardened runtime"
done

# Entitlements: Apple Events only. Anything else (library validation off, DYLD
# variables, get-task-allow, JIT) would let other code run inside Switchboard and use
# its permissions.
entitlements() {
  local xml
  xml="$(codesign -d --entitlements - --xml "$1" 2>/dev/null)"
  if [ -z "$xml" ]; then echo "{}"; else plutil -convert json -o - - <<<"$xml"; fi
}
[ "$(entitlements "$APP")" = '{"com.apple.security.automation.apple-events":true}' ] \
  || fail "unexpected entitlements: $(entitlements "$APP")"
for helper in "$SPARKLE/Autoupdate" "$SPARKLE/Updater.app"; do
  [ "$(entitlements "$helper")" = "{}" ] || fail "$(basename "$helper") has entitlements: $(entitlements "$helper")"
done

# Libraries found through @rpath (Sparkle) come only from inside the app.
rpaths="$(otool -l "$BIN" | awk '/cmd LC_RPATH/ { getline; getline; sub(/^ *path /, ""); sub(/ \(offset [0-9]+\)$/, ""); print }' | sort -u)"
while IFS= read -r rpath; do
  case "$rpath" in
    "@executable_path/../Frameworks" | /usr/lib/swift | "") ;;
    *) fail "unexpected library search path: $rpath" ;;
  esac
done <<<"$rpaths"

xcrun stapler validate -q "$APP" || fail "not notarized (no stapled ticket)"
spctl --assess --type execute "$APP" 2>/dev/null || fail "Gatekeeper rejects it"

if [ -n "$VERSION" ]; then
  built="$(plutil -extract CFBundleShortVersionString raw "$APP/Contents/Info.plist")"
  [ "$built" = "$VERSION" ] || fail "it's version $built, not $VERSION"
fi
echo "check-app: $(basename "$APP") passes"
