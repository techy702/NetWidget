#!/bin/zsh
# NetWidget build script. Uses only Xcode and XcodeGen; downloads nothing, never launches
# the app, never installs the helper.
#
#   ./build.sh test      generate the project and run the unit tests (unsigned)
#   ./build.sh dev       Release build, ad-hoc signed, into build/dev/ (layout check only:
#                        the helper refuses to run without a Developer ID signature)
#   ./build.sh release   Developer ID signed archive -> build/release/NetWidget.app
#                        (needs Config/Signing.local.xcconfig; see the .example file)
set -euo pipefail
cd "$(dirname "$0")"

MODE="${1:-test}"
xcodegen generate --quiet

case "$MODE" in
  test)
    xcodebuild test -project NetWidget.xcodeproj -scheme NetWidgetTests \
      -destination 'platform=macOS' -derivedDataPath build/DerivedData \
      CODE_SIGNING_ALLOWED=NO -quiet
    echo "Tests passed."
    ;;
  dev)
    xcodebuild build -project NetWidget.xcodeproj -scheme NetWidget -configuration Release \
      -derivedDataPath build/DerivedData -quiet
    rm -rf build/dev && mkdir -p build/dev
    ditto build/DerivedData/Build/Products/Release/NetWidget.app build/dev/NetWidget.app
    echo "Built build/dev/NetWidget.app (ad-hoc signed)."
    ;;
  release)
    [[ -f Config/Signing.local.xcconfig ]] || {
      echo "Missing Config/Signing.local.xcconfig. Copy Config/Signing.local.xcconfig.example and add your Team ID." >&2
      exit 1
    }
    rm -rf build/NetWidget.xcarchive build/release
    xcodebuild archive -project NetWidget.xcodeproj -scheme NetWidget -configuration Release \
      -archivePath build/NetWidget.xcarchive -derivedDataPath build/DerivedData -quiet
    mkdir -p build/release
    ditto build/NetWidget.xcarchive/Products/Applications/NetWidget.app build/release/NetWidget.app
    codesign --verify --deep --strict --verbose=2 build/release/NetWidget.app
    echo "Signed: build/release/NetWidget.app. Next: ./notarize.sh <keychain-profile>"
    ;;
  *)
    echo "usage: ./build.sh [test|dev|release]" >&2
    exit 2
    ;;
esac
