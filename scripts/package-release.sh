#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PROJECT_DIR=$(dirname "$SCRIPT_DIR")
VERSION=${1:-0.6.1}
ARCH=$(uname -m)
ARCHIVE_NAME="Image-Autonamer-macOS-$ARCH.zip"
DIST_DIR="$PROJECT_DIR/dist"

"$PROJECT_DIR/scripts/check-version.sh" "$VERSION"

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
