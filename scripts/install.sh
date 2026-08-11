#!/bin/sh
set -eu

REPOSITORY="DavidVaness/image-autonamer"
MODEL="qwen3-vl:4b"
ARCH=$(uname -m)
ARCHIVE_NAME="Image-Autonamer-macOS-$ARCH.zip"
RELEASE_BASE="https://github.com/$REPOSITORY/releases/latest/download"
INSTALL_TMP=$(mktemp -d "${TMPDIR:-/tmp}/image-autonamer-install.XXXXXX")
trap 'rm -rf "$INSTALL_TMP"' EXIT

if [ "$(uname -s)" != "Darwin" ]; then
  echo "The menu-bar app requires macOS." >&2
  exit 1
fi

for tool in curl ditto shasum unzip; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "Missing required macOS tool: $tool" >&2
    exit 1
  fi
done

if [ "$ARCH" != "arm64" ]; then
  echo "The v0.1 binary supports Apple Silicon." >&2
  echo "Intel Macs can build from source with scripts/install-macos-app.sh." >&2
  exit 1
fi

if ! command -v ollama >/dev/null 2>&1; then
  if ! command -v brew >/dev/null 2>&1; then
    echo "Install Ollama from https://ollama.com/download, then rerun this command." >&2
    exit 1
  fi
  echo "Installing Ollama with Homebrew..."
  brew install ollama
fi

echo "Downloading Image Autonamer..."
curl --fail --location --retry 3 --proto '=https' --tlsv1.2 \
  "$RELEASE_BASE/$ARCHIVE_NAME" \
  -o "$INSTALL_TMP/$ARCHIVE_NAME"
curl --fail --location --retry 3 --proto '=https' --tlsv1.2 \
  "$RELEASE_BASE/checksums.txt" \
  -o "$INSTALL_TMP/checksums.txt"

expected_checksum=$(awk -v archive="$ARCHIVE_NAME" '$2 == archive { print $1 }' \
  "$INSTALL_TMP/checksums.txt")
case "$expected_checksum" in
  *[!0-9a-fA-F]* | '')
    echo "The release checksum manifest is invalid." >&2
    exit 1
    ;;
esac
if [ "${#expected_checksum}" -ne 64 ]; then
  echo "The release checksum manifest is invalid." >&2
  exit 1
fi
actual_checksum=$(shasum -a 256 "$INSTALL_TMP/$ARCHIVE_NAME" | awk '{ print $1 }')
if [ "$actual_checksum" != "$expected_checksum" ]; then
  echo "The downloaded archive failed checksum verification." >&2
  exit 1
fi

(
  cd "$INSTALL_TMP"
  unzip -q "$ARCHIVE_NAME"
)

mkdir -p "$HOME/Applications"
ditto "$INSTALL_TMP/Image Autonamer.app" "$HOME/Applications/Image Autonamer.app"

if ! curl -fsS http://127.0.0.1:11434/api/tags >/dev/null 2>&1; then
  echo "Starting Ollama..."
  ollama serve > "$INSTALL_TMP/ollama.log" 2>&1 &
  attempts=0
  while ! curl -fsS http://127.0.0.1:11434/api/tags >/dev/null 2>&1; do
    attempts=$((attempts + 1))
    if [ "$attempts" -ge 30 ]; then
      echo "Ollama did not become ready within 30 seconds." >&2
      cat "$INSTALL_TMP/ollama.log" >&2
      exit 1
    fi
    sleep 1
  done
fi

echo "Pulling the local vision model..."
ollama pull "$MODEL"
open "$HOME/Applications/Image Autonamer.app"

echo "Image Autonamer is installed and running."
echo "Choose Downloads in the folder picker to finish setup."
