#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PROJECT_DIR=$(dirname "$SCRIPT_DIR")
APP_PATH="$PROJECT_DIR/dist/Image Autonamer.app"
SWIFT_COMMAND=${SWIFT_BIN:-swift}

cd "$PROJECT_DIR"
"$SWIFT_COMMAND" build -c release --product ImageAutonamerMac
BIN_DIR=$("$SWIFT_COMMAND" build -c release --show-bin-path)

rm -rf "$APP_PATH"
mkdir -p "$APP_PATH/Contents/MacOS"
mkdir -p "$APP_PATH/Contents/Resources"
cp "$BIN_DIR/ImageAutonamerMac" "$APP_PATH/Contents/MacOS/ImageAutonamer"
cp "$PROJECT_DIR/macos/Info.plist" "$APP_PATH/Contents/Info.plist"
cp "$PROJECT_DIR/macos/AppIcon.icns" "$APP_PATH/Contents/Resources/AppIcon.icns"

SIGNING_IDENTITY=${CODESIGN_IDENTITY:--}
if [ "$SIGNING_IDENTITY" = "-" ]; then
  codesign \
    --force \
    --sign - \
    --entitlements "$PROJECT_DIR/macos/ImageAutonamer.entitlements" \
    "$APP_PATH"
else
  codesign \
    --force \
    --options runtime \
    --timestamp \
    --sign "$SIGNING_IDENTITY" \
    --entitlements "$PROJECT_DIR/macos/ImageAutonamer.entitlements" \
    "$APP_PATH"
fi
codesign --verify --deep --strict "$APP_PATH"

echo "Built $APP_PATH"
