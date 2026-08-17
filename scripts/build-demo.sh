#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PROJECT_DIR=$(dirname "$SCRIPT_DIR")
ASSET_DIR="$PROJECT_DIR/docs/assets"
SLIDE_DIR="$PROJECT_DIR/docs/demo"
CAPTURE_DIR="$SLIDE_DIR/captures"
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

for number in 01 06; do
  source_svg=$(find "$SLIDE_DIR" -maxdepth 1 -name "${number}-*.svg" -print -quit)
  rsvg-convert --width 1280 --height 720 "$source_svg" > "$DEMO_TMP/$number.png"
done

make_still_clip() {
  number=$1
  duration=$2
  ffmpeg -hide_banner -loglevel error -y \
    -loop 1 -i "$DEMO_TMP/$number.png" \
    -t "$duration" \
    -vf "zoompan=z='min(zoom+0.0001,1.02)':d=$((duration * 30)):s=1280x720:fps=30,fade=t=in:st=0:d=0.35,fade=t=out:st=$(awk "BEGIN { print $duration - 0.35 }"):d=0.35,format=yuv420p" \
    -c:v libx264 -preset medium -crf 20 -movflags +faststart \
    "$DEMO_TMP/$number.mp4"
  printf "file '%s.mp4'\n" "$number" >> "$DEMO_TMP/clips.txt"
}

make_capture_clip() {
  number=$1
  source=$2
  duration=$3
  crop=$4
  ffmpeg -hide_banner -loglevel error -y \
    -i "$CAPTURE_DIR/$source" \
    -t "$duration" \
    -vf "crop=$crop,fps=30,scale=1240:700:force_original_aspect_ratio=decrease,pad=1280:720:(ow-iw)/2:(oh-ih)/2:color=0x0f172a,fade=t=in:st=0:d=0.35,fade=t=out:st=$(awk "BEGIN { print $duration - 0.35 }"):d=0.35,format=yuv420p" \
    -an -c:v libx264 -preset medium -crf 20 -movflags +faststart \
    "$DEMO_TMP/$number.mp4"
  printf "file '%s.mp4'\n" "$number" >> "$DEMO_TMP/clips.txt"
}

make_still_clip 01 6
make_capture_clip 02 real-general.mov 7 1100:1176:68:52
make_capture_clip 03 real-naming.mov 7 1100:1176:68:52
make_capture_clip 04 real-review.mov 11 1640:1256:68:52
make_capture_clip 05 real-history.mov 8 1640:1256:68:52
make_still_clip 06 7

ffmpeg -hide_banner -loglevel error -y \
  -f concat -safe 0 -i "$DEMO_TMP/clips.txt" \
  -c copy -movflags +faststart \
  "$ASSET_DIR/demo.mp4"

ffmpeg -hide_banner -loglevel error -y \
  -ss 6 -t 33 \
  -i "$ASSET_DIR/demo.mp4" \
  -vf "fps=5,scale=640:-1:flags=lanczos,split[s0][s1];[s0]palettegen=max_colors=96[p];[s1][p]paletteuse=dither=bayer:bayer_scale=4" \
  -loop 0 \
  "$ASSET_DIR/demo.gif"

cp "$DEMO_TMP/01.png" "$ASSET_DIR/demo-poster.png"

echo "Built the 46-second MP4 and 33-second real-app GIF preview in docs/assets"
