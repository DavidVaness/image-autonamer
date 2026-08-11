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
cp "$BIN_DIR/ImageAutonamerMac" "$APP_PATH/Contents/MacOS/ImageAutonamer"
cp "$PROJECT_DIR/macos/Info.plist" "$APP_PATH/Contents/Info.plist"

codesign \
  --force \
  --sign - \
  --entitlements "$PROJECT_DIR/macos/ImageAutonamer.entitlements" \
  "$APP_PATH"
codesign --verify --deep --strict "$APP_PATH"

echo "Built $APP_PATH"
