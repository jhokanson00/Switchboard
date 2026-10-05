#!/usr/bin/env bash
# Publishes a release that scripts/release.sh built, after checking it once more: the
# GitHub release v<version>, tagged on the pushed commit that sets that version, with
# the .dmg and the signed appcast.xml that every copy of Switchboard reads for updates.
#
#   scripts/publish.sh 1.0.0
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-}"
if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]]; then
  echo "Usage: scripts/publish.sh <version, e.g. 1.0.0>" >&2
  exit 1
fi

REPO="jhokanson00/Switchboard"
OUT=build/release
DMG="$OUT/Switchboard-$VERSION.dmg"
FEED="$OUT/appcast.xml"
NOTES="$OUT/notes.md"
SPARKLE_BIN=.build/artifacts/sparkle/Sparkle/bin
fail() { echo "Not published: $*" >&2; exit 1; }

[ -f "$DMG" ] && [ -f "$FEED" ] && [ -f "$NOTES" ] || fail "build it first with scripts/release.sh $VERSION"

# The source: main, clean, pushed, and setting this version.
[ "$(git rev-parse --abbrev-ref HEAD)" = main ] || fail "check out main"
[ -z "$(git status --porcelain)" ] || fail "commit the version change (and anything else) first"
git fetch -q origin main
[ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ] || fail "push main first"
COMMIT="$(git rev-parse HEAD)"
plist() { git show "$COMMIT:Resources/Info.plist" | plutil -extract "$1" raw -; }
[ "$(plist CFBundleShortVersionString)" = "$VERSION" ] || fail "the pushed Info.plist isn't version $VERSION"
BUILD="$(plist CFBundleVersion)"

# The feed: signed with the update key, and for this version and build.
"$SPARKLE_BIN/sign_update" --account Switchboard --verify "$FEED" >/dev/null || fail "appcast.xml isn't validly signed"
grep -q "<sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>" "$FEED" \
  && grep -q "<sparkle:version>$BUILD</sparkle:version>" "$FEED" \
  || fail "appcast.xml is for a different version or build"

# The disk image: notarized, matching the feed's update signature, and holding an app
# that passes every check.
xcrun stapler validate -q "$DMG" || fail "the .dmg isn't notarized"
spctl --assess --type open --context context:primary-signature "$DMG" 2>/dev/null || fail "Gatekeeper rejects the .dmg"
SIGNATURE="$(sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p' "$FEED")"
"$SPARKLE_BIN/sign_update" --account Switchboard --verify "$DMG" "$SIGNATURE" >/dev/null \
  || fail "the .dmg doesn't match the update signature in appcast.xml"
MOUNT="$(mktemp -d)"
hdiutil attach -quiet -nobrowse -readonly -mountpoint "$MOUNT" "$DMG"
trap 'hdiutil detach -quiet "$MOUNT" || true' EXIT
scripts/check-app.sh "$MOUNT/Switchboard.app" "$VERSION"
[ "$(plutil -extract CFBundleVersion raw "$MOUNT/Switchboard.app/Contents/Info.plist")" = "$BUILD" ] \
  || fail "the app in the .dmg isn't build $BUILD"

echo "==> Publishing Switchboard $VERSION (build $BUILD) from $COMMIT"
gh release create "v$VERSION" "$DMG" "$FEED" --repo "$REPO" --target "$COMMIT" \
  --title "Switchboard $VERSION" --notes-file "$NOTES"

if curl -fsSL "https://github.com/$REPO/releases/latest/download/appcast.xml" \
  | grep -q "<sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>"; then
  echo "Live: every copy of Switchboard will be offered $VERSION."
else
  echo "Published, but the latest appcast doesn't show $VERSION yet. Check the release page." >&2
fi
