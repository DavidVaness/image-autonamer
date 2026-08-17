#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PROJECT_DIR=$(dirname "$SCRIPT_DIR")
FIXTURE_DIR="$PROJECT_DIR/eval/fixtures"
PYTHON_COMMAND=${PYTHON_BIN:-python3}

if ! command -v rsvg-convert >/dev/null 2>&1; then
  echo "Missing required fixture tool: rsvg-convert" >&2
  exit 1
fi

for source in "$FIXTURE_DIR"/*.svg; do
  destination="${source%.svg}.png"
  rsvg-convert --width 800 --height 600 "$source" > "$destination"
done

if ! "$PYTHON_COMMAND" -c "import reportlab" >/dev/null 2>&1; then
  echo "Missing required fixture dependency: reportlab" >&2
  exit 1
fi

"$PYTHON_COMMAND" "$SCRIPT_DIR/build-pdf-fixture.py"

echo "Built evaluation images and PDF in $FIXTURE_DIR"
