#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PROJECT_DIR=$(dirname "$SCRIPT_DIR")
VERSION=${1:-0.1.0}
ARCH=$(uname -m)
ARCHIVE_NAME="Image-Autonamer-macOS-$ARCH.zip"
DIST_DIR="$PROJECT_DIR/dist"
PLIST_VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
  "$PROJECT_DIR/macos/Info.plist")

if [ "$VERSION" != "$PLIST_VERSION" ]; then
  echo "Release version $VERSION does not match Info.plist version $PLIST_VERSION." >&2
  exit 1
fi

"$PROJECT_DIR/scripts/build-macos-app.sh"

rm -f "$DIST_DIR/$ARCHIVE_NAME" "$DIST_DIR/checksums.txt"
ditto -c -k --sequesterRsrc --keepParent \
  "$DIST_DIR/Image Autonamer.app" \
  "$DIST_DIR/$ARCHIVE_NAME"

(
  cd "$DIST_DIR"
  shasum -a 256 "$ARCHIVE_NAME" > checksums.txt
)

echo "Packaged Image Autonamer v$VERSION"
echo "$DIST_DIR/$ARCHIVE_NAME"
echo "$DIST_DIR/checksums.txt"
