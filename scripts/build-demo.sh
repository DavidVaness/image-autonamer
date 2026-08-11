#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PROJECT_DIR=$(dirname "$SCRIPT_DIR")
ASSET_DIR="$PROJECT_DIR/docs/assets"
SLIDE_DIR="$PROJECT_DIR/docs/demo"
DEMO_TMP=$(mktemp -d "${TMPDIR:-/tmp}/image-autonamer-demo.XXXXXX")
trap 'rm -rf "$DEMO_TMP"' EXIT

for tool in rsvg-convert ffmpeg; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "Missing required demo tool: $tool" >&2
    exit 1
  fi
done

rsvg-convert --width 1200 --height 800 \
  "$ASSET_DIR/sample-landscape.svg" \
  > "$ASSET_DIR/sample-landscape.png"

for number in 01 02 03 04 05 06; do
  source_svg=$(find "$SLIDE_DIR" -maxdepth 1 -name "${number}-*.svg" -print -quit)
  rsvg-convert --width 1280 --height 720 "$source_svg" > "$DEMO_TMP/$number.png"
  ffmpeg -hide_banner -loglevel error -y \
    -loop 1 -i "$DEMO_TMP/$number.png" \
    -t 10 \
    -vf "zoompan=z='min(zoom+0.0001,1.03)':d=300:s=1280x720:fps=30,fade=t=in:st=0:d=0.45,fade=t=out:st=9.55:d=0.45,format=yuv420p" \
    -c:v libx264 -preset medium -crf 20 -movflags +faststart \
    "$DEMO_TMP/$number.mp4"
  printf "file '%s.mp4'\n" "$number" >> "$DEMO_TMP/clips.txt"
done

ffmpeg -hide_banner -loglevel error -y \
  -f concat -safe 0 -i "$DEMO_TMP/clips.txt" \
  -c copy -movflags +faststart \
  "$ASSET_DIR/demo.mp4"

ffmpeg -hide_banner -loglevel error -y \
  -i "$ASSET_DIR/demo.mp4" \
  -vf "fps=8,scale=800:-1:flags=lanczos,split[s0][s1];[s0]palettegen=max_colors=128[p];[s1][p]paletteuse=dither=bayer:bayer_scale=4" \
  -loop 0 \
  "$ASSET_DIR/demo.gif"

cp "$DEMO_TMP/01.png" "$ASSET_DIR/demo-poster.png"

echo "Built docs/assets/demo.mp4 and docs/assets/demo.gif"
