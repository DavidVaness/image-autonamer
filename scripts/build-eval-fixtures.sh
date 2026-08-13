#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PROJECT_DIR=$(dirname "$SCRIPT_DIR")
FIXTURE_DIR="$PROJECT_DIR/eval/fixtures"

if ! command -v rsvg-convert >/dev/null 2>&1; then
  echo "Missing required fixture tool: rsvg-convert" >&2
  exit 1
fi

for source in "$FIXTURE_DIR"/*.svg; do
  destination="${source%.svg}.png"
  rsvg-convert --width 800 --height 600 "$source" > "$destination"
done

echo "Built evaluation PNGs in $FIXTURE_DIR"
