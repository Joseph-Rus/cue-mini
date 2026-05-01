#!/bin/bash
# End-to-end release: build → sign → notarize → staple → DMG.
#
# Prerequisites (one-time):
#   1. DEVELOPER_ID env var, e.g.:
#        export DEVELOPER_ID="Developer ID Application: Your Name (TEAMID)"
#   2. Notary credentials stored under the keychain profile "cuemini-notary":
#        xcrun notarytool store-credentials cuemini-notary \
#          --apple-id your-apple-id@example.com \
#          --team-id TEAMID \
#          --password APP-SPECIFIC-PASSWORD
#
# Usage:
#   ./scripts/release.sh
#
# Output: build/Cue-Mini.dmg — share this file with anyone.

set -euo pipefail

if [[ -z "${DEVELOPER_ID:-}" ]]; then
    echo "ERROR: DEVELOPER_ID is not set."
    echo "  export DEVELOPER_ID=\"Developer ID Application: Your Name (TEAMID)\""
    exit 1
fi

NOTARY_PROFILE="cuemini-notary"
APP_PATH="$(pwd)/build/Cue Mini.app"
DMG_PATH="$(pwd)/build/Cue-Mini.dmg"
ZIP_PATH="$(pwd)/build/Cue-Mini.zip"

echo "==> [1/5] Building signed release"
./scripts/build-app.sh --release

echo
echo "==> [2/5] Zipping for notarization upload"
rm -f "$ZIP_PATH"
ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"

echo
echo "==> [3/5] Submitting to Apple Notary Service (this takes a few minutes)"
xcrun notarytool submit "$ZIP_PATH" \
    --keychain-profile "$NOTARY_PROFILE" \
    --wait

echo
echo "==> [4/5] Stapling notarization ticket to the .app"
xcrun stapler staple "$APP_PATH"
xcrun stapler validate "$APP_PATH"

echo
echo "==> [5/5] Building DMG"
rm -f "$DMG_PATH"
hdiutil create \
    -volname "Cue Mini" \
    -srcfolder "$APP_PATH" \
    -ov \
    -format UDZO \
    "$DMG_PATH"

# Sign the DMG itself so users don't get an "unidentified developer" warning
# on the DMG before they even open it.
codesign --force --sign "$DEVELOPER_ID" --timestamp "$DMG_PATH"

# Notarize the DMG too (this prevents the "downloaded from internet" warning).
echo
echo "==> Notarizing DMG"
xcrun notarytool submit "$DMG_PATH" \
    --keychain-profile "$NOTARY_PROFILE" \
    --wait
xcrun stapler staple "$DMG_PATH"

# Cleanup
rm -f "$ZIP_PATH"

echo
echo "Done."
echo "  DMG: $DMG_PATH"
echo "  Send this file to friends — they double-click it, drag Cue Mini to Applications, done."
