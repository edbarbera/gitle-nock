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

# The DMG is a styled drag-to-install window, not a bare file listing: custom
# background art, the app on the left, an /Applications symlink on the right.
# hdiutil can't set any of that, so the image is first created read-write,
# mounted, laid out through Finder scripting (which writes the .DS_Store),
# then converted to the compressed read-only UDZO that actually ships.
#
# The osascript block needs Automation permission for Finder the first time
# it runs from a terminal — approve the one-time prompt or the layout step
# fails with "not authorized".
STAGE="$ROOT/build/dmg-stage"
DMG_RW="$ROOT/build/GitleNock-rw.dmg"
VOLNAME="gitle nock"

rm -rf "$STAGE" "$DMG_RW"
mkdir -p "$STAGE/.background"
cp -R "$APP" "$STAGE/GitleNock.app"
ln -s /Applications "$STAGE/Applications"
cp "$ROOT/assets/dmg-background.tiff" "$STAGE/.background/background.tiff"

# The volume itself gets the app icon, so the mounted disk on the desktop
# matches what's being installed.
if [ -f "$ROOT/assets/AppIcon.icns" ]; then
    cp "$ROOT/assets/AppIcon.icns" "$STAGE/.VolumeIcon.icns"
fi

hdiutil create -volname "$VOLNAME" -srcfolder "$STAGE" -ov -format UDRW "$DMG_RW"

MOUNT_DIR="/Volumes/$VOLNAME"
hdiutil attach "$DMG_RW" -noautoopen
# SetFile ships with the Xcode CLT; without the custom-icon bit the
# .VolumeIcon.icns file is ignored, but that's cosmetic — don't fail over it.
if [ -f "$MOUNT_DIR/.VolumeIcon.icns" ]; then
    SetFile -a C "$MOUNT_DIR" 2>/dev/null || true
fi

osascript <<OSA
tell application "Finder"
    tell disk "$VOLNAME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        -- 660x420 content, matching assets/dmg-background.svg's canvas
        set the bounds of container window to {200, 120, 860, 568}
        set viewOptions to the icon view options of container window
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 128
        set text size of viewOptions to 12
        set background picture of viewOptions to file ".background:background.tiff"
        -- Centers of the two glass rings drawn in the background art
        set position of item "GitleNock.app" of container window to {165, 240}
        set position of item "Applications" of container window to {495, 240}
        close
        open
        update without registering applications
        delay 1
        close
    end tell
end tell
OSA

sync
hdiutil detach "$MOUNT_DIR"
hdiutil convert "$DMG_RW" -format UDZO -o "$DMG"
rm -f "$DMG_RW"
rm -rf "$STAGE"

# hdiutil never signs the disk image itself, and notarization/stapling a
# ticket onto it doesn't produce one either — spctl's "install" check on a
# DMG looks for its own signature, so an unsigned DMG reads as "no usable
# signature" even with a valid stapled ticket. Sign it directly.
echo "Signing the DMG…"
codesign --force --sign "$SIGN_ID" "$DMG"

# The app's notarization ticket only covers the app's own hash — the DMG is a
# separate artifact and needs its own notarization submission before it can
# be stapled. Skipping this step is what causes stapler's "CloudKit query
# ... Record not found" on the DMG: there's no ticket for it to find yet.
echo "Submitting the DMG for notarization…"
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait

echo "Stapling the notarization ticket to the DMG…"
xcrun stapler staple "$DMG"

echo
echo "Done: $DMG"
echo "Sanity check before sending it anywhere:"
echo "  spctl -a -vvv --type install \"$DMG\""
echo "Should print: accepted, source=Notarized Developer ID"
