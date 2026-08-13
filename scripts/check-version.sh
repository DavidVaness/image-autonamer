#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PROJECT_DIR=$(dirname "$SCRIPT_DIR")
EXPECTED_VERSION=${1:?usage: scripts/check-version.sh VERSION}

PLIST_VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
  "$PROJECT_DIR/macos/Info.plist")
PYPROJECT_VERSION=$(sed -n 's/^version = "\([^"]*\)"$/\1/p' \
  "$PROJECT_DIR/pyproject.toml")
PACKAGE_VERSION=$(sed -n 's/^__version__ = "\([^"]*\)"$/\1/p' \
  "$PROJECT_DIR/src/image_autonamer/__init__.py")

for entry in \
  "macos/Info.plist:$PLIST_VERSION" \
  "pyproject.toml:$PYPROJECT_VERSION" \
  "src/image_autonamer/__init__.py:$PACKAGE_VERSION"
do
  file=${entry%%:*}
  version=${entry#*:}
  if [ "$version" != "$EXPECTED_VERSION" ]; then
    echo "$file version $version does not match release version $EXPECTED_VERSION." >&2
    exit 1
  fi
done

echo "Version $EXPECTED_VERSION is consistent across release metadata."
