#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PROJECT_DIR=$(dirname "$SCRIPT_DIR")
SOURCE_APP="$PROJECT_DIR/dist/Image Autonamer.app"
INSTALL_DIR="$HOME/Applications"
INSTALLED_APP="$INSTALL_DIR/Image Autonamer.app"

"$PROJECT_DIR/scripts/build-macos-app.sh"
mkdir -p "$INSTALL_DIR"
ditto "$SOURCE_APP" "$INSTALLED_APP"
open "$INSTALLED_APP"

echo "Installed and opened $INSTALLED_APP"
