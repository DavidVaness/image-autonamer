#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PROJECT_DIR=$(dirname "$SCRIPT_DIR")
VERSION=${1:-0.1.0}
ARCH=$(uname -m)
APP_PATH="$PROJECT_DIR/dist/Image Autonamer.app"
DMG_PATH="$PROJECT_DIR/dist/Image-Autonamer-$VERSION-macOS-$ARCH.dmg"
SUBMISSION_ZIP="$PROJECT_DIR/dist/Image-Autonamer-notarization.zip"

require_value() {
  if [ -z "$2" ]; then
    echo "Missing required environment variable: $1" >&2
    exit 1
  fi
}

require_value CODESIGN_IDENTITY "${CODESIGN_IDENTITY:-}"
require_value APPLE_ID "${APPLE_ID:-}"
require_value APPLE_TEAM_ID "${APPLE_TEAM_ID:-}"
require_value APPLE_APP_PASSWORD "${APPLE_APP_PASSWORD:-}"

"$PROJECT_DIR/scripts/check-version.sh" "$VERSION"

if [ ! -d "$APP_PATH" ]; then
  echo "Build the signed app with scripts/build-macos-app.sh first." >&2
  exit 1
fi

APP_VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
  "$APP_PATH/Contents/Info.plist")
if [ "$VERSION" != "$APP_VERSION" ]; then
  echo "Release version $VERSION does not match built app version $APP_VERSION." >&2
  exit 1
fi

codesign --verify --deep --strict --verbose=2 "$APP_PATH"
if ! codesign -d --verbose=4 "$APP_PATH" 2>&1 | grep -q 'runtime'; then
  echo "The app is not signed with the hardened runtime." >&2
  exit 1
fi

rm -f "$SUBMISSION_ZIP" "$DMG_PATH"
ditto -c -k --keepParent "$APP_PATH" "$SUBMISSION_ZIP"
xcrun notarytool submit "$SUBMISSION_ZIP" \
  --apple-id "$APPLE_ID" \
  --team-id "$APPLE_TEAM_ID" \
  --password "$APPLE_APP_PASSWORD" \
  --wait
xcrun stapler staple "$APP_PATH"
xcrun stapler validate "$APP_PATH"
spctl --assess --type execute --verbose=2 "$APP_PATH"

hdiutil create \
  -volname "Image Autonamer" \
  -srcfolder "$APP_PATH" \
  -ov \
  -format UDZO \
  "$DMG_PATH"
codesign --force --timestamp --sign "$CODESIGN_IDENTITY" "$DMG_PATH"
xcrun notarytool submit "$DMG_PATH" \
  --apple-id "$APPLE_ID" \
  --team-id "$APPLE_TEAM_ID" \
  --password "$APPLE_APP_PASSWORD" \
  --wait
xcrun stapler staple "$DMG_PATH"
xcrun stapler validate "$DMG_PATH"

rm -f "$SUBMISSION_ZIP"
(
  cd "$PROJECT_DIR/dist"
  shasum -a 256 "$(basename "$DMG_PATH")" > checksums.txt
)

echo "Built notarized release: $DMG_PATH"
