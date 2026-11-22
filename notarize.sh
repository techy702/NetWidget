#!/bin/zsh
# Notarizes and staples build/release/NetWidget.app (run ./build.sh release first).
# Uploads the app to Apple's notary service: this is the one step that uses the network.
#
#   ./notarize.sh <keychain-profile>
#
# The profile is created once with `xcrun notarytool store-credentials` (see README).
# This script never sees your Apple ID password.
set -euo pipefail
cd "$(dirname "$0")"

PROFILE="${1:?usage: ./notarize.sh <keychain-profile>}"
APP=build/release/NetWidget.app
ZIP=build/release/NetWidget-upload.zip
OUT=build/release/NetWidget.zip

[[ -d "$APP" ]] || { echo "No $APP. Run ./build.sh release first." >&2; exit 1; }

ditto -c -k --keepParent "$APP" "$ZIP"
xcrun notarytool submit "$ZIP" --keychain-profile "$PROFILE" --wait
rm -f "$ZIP"
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
spctl --assess --type execute --verbose=4 "$APP"
ditto -c -k --keepParent "$APP" "$OUT"
echo "Notarized and stapled. Copy $OUT to each Mac."
