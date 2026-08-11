#!/bin/sh
set -eu

LABEL="com.davidvaness.image-autonamer"
PLIST_PATH="$HOME/Library/LaunchAgents/$LABEL.plist"

launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
if [ -f "$PLIST_PATH" ]; then
  rm "$PLIST_PATH"
fi
echo "Uninstalled $LABEL (the local state database and logs were preserved)."
