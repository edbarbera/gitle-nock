#!/bin/bash
# Builds, signs with a Developer ID certificate, notarizes, staples, and
# packages GitleNock as a DMG that anyone can double-click and open without
# a Gatekeeper warning. bundle.sh's ad-hoc signature is fine for running the
# app on this Mac; it is not enough for handing it to someone else's Mac.
#
# One-time setup, before this script will work:
#
#   1. Enroll in the Apple Developer Program: developer.apple.com/programs ($99/yr).
#
#   2. Get a "Developer ID Application" certificate (needs Xcode installed,
#      even though the project itself doesn't use it):
#        Xcode > Settings > Accounts > select your Apple ID team >
#        Manage Certificates > + > Developer ID Application.
#
#   3. Generate an app-specific password at appleid.apple.com
#      (Sign-In and Security > App-Specific Passwords), then store
#      notarization credentials once so this script can log in silently:
#        xcrun notarytool store-credentials "gitlenock-notary" \
#          --apple-id you@example.com \
#          --team-id YOUR_TEAM_ID \
#          --password the-app-specific-password
#      Your team ID is on developer.apple.com/account under Membership.
#
# After that, just run: ./scripts/release.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/build/GitleNock.app"
DMG="$ROOT/build/GitleNock.dmg"
NOTARY_PROFILE="${NOTARY_PROFILE:-gitlenock-notary}"

SIGN_ID="$(security find-identity -v -p codesigning 2>/dev/null | grep 'Developer ID Application' | head -1 | sed -E 's/.*"(.*)"/\1/' || true)"
if [ -z "$SIGN_ID" ]; then
    echo "No 'Developer ID Application' certificate found in the keychain." >&2
    echo "See the setup steps at the top of this script." >&2
    exit 1
fi

"$ROOT/scripts/bundle.sh" release

echo "Signing with: $SIGN_ID"
# --options runtime turns on the hardened runtime; notarization requires it.
# This replaces bundle.sh's ad-hoc signature outright.
codesign --force --deep --options runtime --timestamp --sign "$SIGN_ID" "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"

echo "Submitting for notarization (usually a few minutes)…"
ZIP="$ROOT/build/GitleNock-notarize.zip"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
rm -f "$ZIP"

echo "Stapling the notarization ticket to the app…"
xcrun stapler staple "$APP"

echo "Building the DMG…"
rm -f "$DMG"
hdiutil create -volname "gitle nock" -srcfolder "$APP" -ov -format UDZO "$DMG"
xcrun stapler staple "$DMG"

echo
echo "Done: $DMG"
echo "Sanity check before sending it anywhere:"
echo "  spctl -a -vvv --type install \"$DMG\""
echo "Should print: accepted, source=Notarized Developer ID"
