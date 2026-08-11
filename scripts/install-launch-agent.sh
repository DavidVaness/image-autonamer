#!/bin/sh
set -eu

LABEL="com.davidvaness.image-autonamer"
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PROJECT_DIR=$(dirname "$SCRIPT_DIR")
DOWNLOADS_DIR=${IMAGE_AUTONAMER_DIRECTORY:-"$HOME/Downloads"}
MODEL=${IMAGE_AUTONAMER_MODEL:-"qwen3-vl:4b"}
AGENTS_DIR="$HOME/Library/LaunchAgents"
LOG_DIR="$HOME/Library/Logs/image-autonamer"
PLIST_PATH="$AGENTS_DIR/$LABEL.plist"

mkdir -p "$AGENTS_DIR" "$LOG_DIR"

"$PROJECT_DIR/bin/image-autonamer" --mark-existing "$DOWNLOADS_DIR"

python3 "$PROJECT_DIR/scripts/render-launch-agent.py" \
  "$PROJECT_DIR/scripts/launch-agent.plist.template" \
  "$PLIST_PATH" \
  "$PROJECT_DIR" \
  "$DOWNLOADS_DIR" \
  "$MODEL" \
  "$HOME"

launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST_PATH"

echo "Installed $LABEL"
echo "Watching: $DOWNLOADS_DIR"
echo "Model: $MODEL"
echo "Logs: $LOG_DIR"
