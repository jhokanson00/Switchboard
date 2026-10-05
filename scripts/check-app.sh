#!/usr/bin/env bash
# Checks that a built Switchboard.app is fit to hand to users, and fails loudly if not:
# signed with the developer's Developer ID and the hardened runtime throughout, no
# entitlement but Apple Events (nothing that lets other code into the app), Sparkle
# loaded only from inside the app, built for Apple silicon and Intel on the macOS it
# promises, updates set up so they keep working (the pinned update key, signed feeds),
# and notarized. release.sh runs it on the build, publish.sh on the app in the .dmg.
#
#   scripts/check-app.sh path/to/Switchboard.app [version]
set -euo pipefail

APP="${1:?Usage: scripts/check-app.sh path/to/Switchboard.app [version]}"
VERSION="${2:-}"
BIN="$APP/Contents/MacOS/Switchboard"
PLIST="$APP/Contents/Info.plist"
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"
# The developer's team. Another team's Developer ID would pass Gatekeeper, but macOS
# would forget every permission users gave Switchboard.
TEAM=DHGK36B2V9
fail() { echo "check-app: $*" >&2; exit 1; }

codesign --verify --deep --strict "$APP" 2>/dev/null || fail "the signature doesn't verify"

for code in "$APP" "$SPARKLE/Sparkle" "$SPARKLE/Autoupdate" "$SPARKLE/Updater.app"; do
  info="$(codesign -dvv "$code" 2>&1)"
  grep -q '^Authority=Developer ID Application: ' <<<"$info" || fail "$(basename "$code") isn't signed with a Developer ID"
  grep -q "^TeamIdentifier=$TEAM\$" <<<"$info" || fail "$(basename "$code") isn't signed by team $TEAM"
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

# Updates. Copies of Switchboard trust only the update key they ship with, and from
# 1.0.5 refuse unsigned feeds, so a wrong key or a missing setting would stop every
# future update for everyone with this version (Sparkle won't start at all if
# SURequireSignedFeed is on without SUVerifyUpdateBeforeExtraction).
key() { plutil -extract "$1" raw "$PLIST" 2>/dev/null || echo "(missing)"; }
[ "$(key SUPublicEDKey)" = "$(cat "$(dirname "$0")/sparkle-public-key.txt")" ] \
  || fail "SUPublicEDKey isn't the pinned update key (scripts/sparkle-public-key.txt)"
[ "$(key SUFeedURL)" = "https://github.com/jhokanson00/Switchboard/releases/latest/download/appcast.xml" ] \
  || fail "unexpected SUFeedURL: $(key SUFeedURL)"
[ "$(key SURequireSignedFeed)" = true ] || fail "SURequireSignedFeed isn't on"
[ "$(key SUVerifyUpdateBeforeExtraction)" = true ] || fail "SUVerifyUpdateBeforeExtraction isn't on"

# Apple silicon and Intel, on every macOS the feed offers it to (LSMinimumSystemVersion).
# An update that can't launch could never be fixed by another one.
MIN_OS="$(key LSMinimumSystemVersion)"
for code in "$BIN" "$SPARKLE/Sparkle" "$SPARKLE/Autoupdate"; do
  archs="$(lipo -archs "$code")"
  [ "$archs" = "x86_64 arm64" ] || fail "$(basename "$code") is built for $archs, not Apple silicon and Intel"
  for arch in x86_64 arm64; do
    build="$(vtool -arch "$arch" -show-build "$code")"
    minos="$(awk '$1 == "minos" { print $2 }' <<<"$build" | sed -n 1p)"
    [ -n "$minos" ] && [ "$(printf '%s\n' "$minos" "$MIN_OS" | sort -V | sed -n 1p)" = "$minos" ] \
      || fail "$(basename "$code") ($arch) needs macOS ${minos:-?}, but Switchboard promises $MIN_OS"
  done
done

xcrun stapler validate -q "$APP" || fail "not notarized (no stapled ticket)"
spctl --assess --type execute "$APP" 2>/dev/null || fail "Gatekeeper rejects it"

if [ -n "$VERSION" ]; then
  built="$(key CFBundleShortVersionString)"
  [ "$built" = "$VERSION" ] || fail "it's version $built, not $VERSION"
fi
echo "check-app: $(basename "$APP") passes"
