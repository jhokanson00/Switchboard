#!/usr/bin/env bash
# Publishes a release that scripts/release.sh built, after checking it once more: the
# GitHub release v<version>, tagged on the pushed commit that sets that version, with
# the .dmg and the signed appcast.xml that every copy of Switchboard reads for updates.
# Published releases can't be changed (immutable releases), so it goes up as a draft
# first, and is published only once GitHub holds exactly these files.
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
SOURCE="$OUT/source-commit"
KEY="$(cat scripts/sparkle-public-key.txt)"
fail() { echo "Not published: $*" >&2; exit 1; }
verify() { swift scripts/verify-signature.swift "$KEY" "$@" >/dev/null; }

[ -f "$DMG" ] && [ -f "$FEED" ] && [ -f "$NOTES" ] && [ -f "$SOURCE" ] \
  || fail "build it first with scripts/release.sh $VERSION"

# The source: main, clean, pushed, and setting this version.
[ "$(git rev-parse --abbrev-ref HEAD)" = main ] || fail "check out main"
[ -z "$(git status --porcelain)" ] || fail "commit the version change (and anything else) first"
git fetch -q origin main
[ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ] || fail "push main first"
COMMIT="$(git rev-parse HEAD)"
plist() { git show "$COMMIT:Resources/Info.plist" | plutil -extract "$1" raw -; }
[ "$(plist CFBundleShortVersionString)" = "$VERSION" ] || fail "the pushed Info.plist isn't version $VERSION"
BUILD="$(plist CFBundleVersion)"
# The source release.sh built, with only the version change on top: the tag must point
# at what's in the .dmg.
git diff --quiet "$(cat "$SOURCE")" "$COMMIT" -- . ':(exclude)Resources/Info.plist' \
  || fail "main has changed since release.sh built $VERSION; build it again"

# The feed: well-formed, signed for the update key every copy of Switchboard holds, and
# for this version and build.
xmllint --noout "$FEED" || fail "appcast.xml isn't valid XML"
verify "$FEED" || fail "appcast.xml isn't signed with the pinned update key"
grep -q "<sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>" "$FEED" \
  && grep -q "<sparkle:version>$BUILD</sparkle:version>" "$FEED" \
  || fail "appcast.xml is for a different version or build"

# The disk image: notarized, matching the feed's update signature, and holding an app
# that passes every check.
xcrun stapler validate -q "$DMG" || fail "the .dmg isn't notarized"
spctl --assess --type open --context context:primary-signature "$DMG" 2>/dev/null || fail "Gatekeeper rejects the .dmg"
SIGNATURE="$(sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p' "$FEED")"
verify "$DMG" "$SIGNATURE" || fail "the .dmg doesn't match the update signature in appcast.xml"
MOUNT="$(mktemp -d)"
hdiutil attach -quiet -nobrowse -readonly -mountpoint "$MOUNT" "$DMG"
trap 'hdiutil detach -quiet "$MOUNT" || true' EXIT
scripts/check-app.sh "$MOUNT/Switchboard.app" "$VERSION"
git show "$COMMIT:Resources/Info.plist" | cmp -s - "$MOUNT/Switchboard.app/Contents/Info.plist" \
  || fail "the app in the .dmg doesn't have the pushed Info.plist"

echo "==> Uploading Switchboard $VERSION (build $BUILD) from $COMMIT as a draft"
gh release create "v$VERSION" "$DMG" "$FEED" --repo "$REPO" --target "$COMMIT" \
  --title "Switchboard $VERSION" --notes-file "$NOTES" --draft
CHECK="$(mktemp -d)"
gh release download "v$VERSION" --repo "$REPO" --dir "$CHECK" \
  || fail "couldn't download the draft to check it; delete it (gh release delete v$VERSION --repo $REPO) and run this again"
cmp -s "$DMG" "$CHECK/$(basename "$DMG")" && cmp -s "$FEED" "$CHECK/appcast.xml" \
  || fail "the draft on GitHub doesn't hold these files; delete it (gh release delete v$VERSION --repo $REPO) and run this again"

echo "==> Publishing"
gh release edit "v$VERSION" --repo "$REPO" --draft=false --latest

# What GitHub now serves to every copy of Switchboard: this version, validly signed.
# Give GitHub a minute to start serving it.
LIVE="$(mktemp)"
for attempt in 1 2 3 4 5 6; do
  if curl -fsSL "https://github.com/$REPO/releases/latest/download/appcast.xml" -o "$LIVE" \
    && verify "$LIVE" \
    && grep -q "<sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>" "$LIVE"; then
    echo "Live: every copy of Switchboard will be offered $VERSION."
    exit 0
  fi
  [ "$attempt" = 6 ] || sleep 10
done
echo "!! Published, but after a minute the live appcast still isn't this version, validly" >&2
echo "!! signed. Check https://github.com/$REPO/releases/latest/download/appcast.xml by hand." >&2
echo "!! If it's really wrong, copies of Switchboard from 1.0.5 on may not be getting updates;" >&2
echo "!! releases can't be changed once published, so publish the next patch version with" >&2
echo "!! release.sh and this script." >&2
exit 1
