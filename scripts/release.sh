#!/usr/bin/env bash
# Builds a release of Switchboard from the committed source on main: a universal app in
# a .dmg, notarized, plus the signed appcast.xml that Sparkle reads for updates. It
# publishes nothing; scripts/publish.sh does that once the version change is pushed.
#
#   scripts/release.sh 1.0.0   # build into build/release/
#
# Without a Developer ID certificate it makes a test build only: not notarized, not
# signed for updates, and refused by publish.sh.
#
# Release notes come from docs/release-notes/<version>.md: they're shown in the app's
# update window and on the GitHub release. Write and commit them first.
# Sets the version in Resources/Info.plist (and bumps the build number); commit that.
# Notarizing needs a stored notarytool profile, made once with:
#   xcrun notarytool store-credentials pane-notary --apple-id <id> --team-id <team>
# SWITCHBOARD_NOTARY_PROFILE picks a different profile name.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-}"
if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]] || [ $# -ne 1 ]; then
  echo "Usage: scripts/release.sh <version, e.g. 1.0.0>   (then scripts/publish.sh <version>)" >&2
  exit 1
fi

# Only committed source on main goes out, never a local experiment.
if [ "$(git rev-parse --abbrev-ref HEAD)" != main ]; then
  echo "Check out main first: releases are built from main." >&2
  exit 1
fi
if [ -n "$(git status --porcelain)" ]; then
  echo "Commit or stash your changes first: a release is built from the committed source." >&2
  git status --short >&2
  exit 1
fi

NOTES="docs/release-notes/$VERSION.md"
if [ ! -f "$NOTES" ]; then
  echo "Write the release notes in $NOTES first." >&2
  exit 1
fi

REPO="jhokanson00/Switchboard"
PROFILE="${SWITCHBOARD_NOTARY_PROFILE:-pane-notary}"
PLIST=Resources/Info.plist
OUT=build/release
DMG="$OUT/Switchboard-$VERSION.dmg"
SPARKLE_BIN=.build/artifacts/sparkle/Sparkle/bin

# Version: the build number goes up by one each release.
BUILD=$(( $(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$PLIST") + 1 ))
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD" "$PLIST"
echo "==> Switchboard $VERSION (build $BUILD)"

SWITCHBOARD_UNIVERSAL=1 ./scripts/build-app.sh release
APP=build/Switchboard.app

# Read the signature once: grep -q or awk's exit would cut codesign off mid-output,
# which pipefail counts as a failure.
SIGNED_BY="$(codesign -dv --verbose=2 "$APP" 2>&1 | sed -n 's/^Authority=\(Developer ID Application.*\)/\1/p')"
NOTARIZE=0
if [ -n "$SIGNED_BY" ]; then
  NOTARIZE=1
else
  echo
  echo "!! No Developer ID certificate: making a TEST build (not notarized, not signed for updates)."
  echo
fi

notarize() {
  echo "==> Notarizing $(basename "$1") (usually a few minutes)"
  xcrun notarytool submit "$1" --keychain-profile "$PROFILE" --wait
}

rm -rf "$OUT"
mkdir -p "$OUT"

if [ "$NOTARIZE" = 1 ]; then
  ditto -c -k --keepParent "$APP" "$OUT/Switchboard.zip"
  notarize "$OUT/Switchboard.zip"
  xcrun stapler staple "$APP"
  rm "$OUT/Switchboard.zip"
  scripts/check-app.sh "$APP" "$VERSION"
fi

echo "==> Making $DMG"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
cp -R "$APP" "$STAGE/Switchboard.app"
ln -s /Applications "$STAGE/Applications"
hdiutil create -quiet -volname "Switchboard $VERSION" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DMG"

if [ "$NOTARIZE" = 1 ]; then
  codesign --force --timestamp --sign "$SIGNED_BY" "$DMG"
  notarize "$DMG"
  xcrun stapler staple "$DMG"
  spctl --assess --type open --context context:primary-signature -v "$DMG"
else
  echo
  echo "Test build: $DMG"
  echo "Not notarized and not signed for Sparkle, so it can't be published or offered as an update."
  exit 0
fi

# Sparkle: the update is the .dmg itself, signed with the EdDSA key in the keychain
# (made by generate_keys --account Switchboard; its public half is SUPublicEDKey in
# Info.plist).
echo "==> Writing appcast.xml"
SIGNATURE="$("$SPARKLE_BIN/sign_update" --account Switchboard "$DMG")"
# The notes are embedded as HTML, so Sparkle's window shows them on a plain background
# instead of loading the GitHub page.
NOTES_HTML="$(swift scripts/notes-html.swift "$NOTES")"
if [[ "$NOTES_HTML" == *"]]>"* ]]; then
  echo "$NOTES can't contain ']]>'." >&2
  exit 1
fi
MIN_OS="$(/usr/libexec/PlistBuddy -c "Print :LSMinimumSystemVersion" "$PLIST")"
cat > "$OUT/appcast.xml" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Switchboard</title>
    <item>
      <title>Switchboard $VERSION</title>
      <pubDate>$(LC_ALL=C date -u "+%a, %d %b %Y %H:%M:%S +0000")</pubDate>
      <sparkle:version>$BUILD</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>$MIN_OS</sparkle:minimumSystemVersion>
      <description><![CDATA[$NOTES_HTML]]></description>
      <enclosure url="https://github.com/$REPO/releases/download/v$VERSION/Switchboard-$VERSION.dmg"
                 type="application/octet-stream" $SIGNATURE />
    </item>
  </channel>
</rss>
EOF
# Sign the feed itself, so a changed appcast (other notes, links, versions) is refused
# by Switchboard (SURequireSignedFeed). Nothing may edit it after this. sign_update signs
# even XML it can't parse, so check it parses, and check the signature against the
# public key users have, not the keychain's.
xmllint --noout "$OUT/appcast.xml"
"$SPARKLE_BIN/sign_update" --account Switchboard "$OUT/appcast.xml"
xmllint --noout "$OUT/appcast.xml"
swift scripts/verify-signature.swift "$(cat scripts/sparkle-public-key.txt)" "$OUT/appcast.xml"
swift scripts/verify-signature.swift "$(cat scripts/sparkle-public-key.txt)" "$DMG" \
  "$(sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p' <<<"$SIGNATURE")"

# The GitHub release: the same notes, plus how to install.
{
  cat "$NOTES"
  echo
  echo "Download **Switchboard-$VERSION.dmg** below, open it, and drag Switchboard to Applications."
  echo "It lives in the menu bar as a light switch. Already have it? Choose **Check for Updates…** at the bottom of the panel."
  echo
  echo "Requires macOS $MIN_OS or later. Runs on Apple silicon and Intel."
} > "$OUT/notes.md"

echo
echo "Built:"
ls -lh "$OUT"
echo
echo "Next: commit Resources/Info.plist (\"Version $VERSION (build $BUILD)\"), push main, then"
echo "  scripts/publish.sh $VERSION"
