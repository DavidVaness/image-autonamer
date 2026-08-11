# Image Autonamer

Give downloaded images useful names automatically, without sending them to a cloud service.

Image Autonamer watches a folder, asks a vision-language model running locally in [Ollama](https://ollama.com/) what each new image contains, sanitizes the answer, and safely renames the file.
It is macOS-first, dependency-free, and designed to be understandable enough to trust with your Downloads folder.

```text
IMG_8472.PNG  ->  orange-cat-sleeping-on-sofa.png
download.jpg  ->  mountain-lake-under-storm-clouds.jpg
image.webp    ->  blue-product-dashboard-with-charts.webp
```

## Why this exists

Downloads folders quickly fill up with names such as `image (12).png`, UUIDs, and camera counters.
Cloud vision APIs can fix that, but uploading personal screenshots and photos just to rename them is an uncomfortable trade.
Image Autonamer keeps inference local and makes every filesystem change visible and reversible through normal file history or backups.

## Features

- Runs image understanding locally through Ollama.
- Renames a single file, a directory, or an entire directory tree.
- Automatically reacts to new Downloads on macOS with a launchd agent.
- Supports dry runs before any file changes.
- Never overwrites an existing file and adds `-2`, `-3`, and so on for collisions.
- Remembers processed files in a small local SQLite database.
- Waits for downloads to finish before processing them.
- Uses only the Python standard library at runtime.

## Requirements

- macOS for automatic folder watching.
- Python 3.11 or newer.
- [Ollama](https://ollama.com/download) 0.12.7 or newer.
- About 3.3 GB of disk space for the default `qwen3-vl:4b` model.

The manual command also works on Linux.
The included launchd installer is specific to macOS.

## Quick start

Clone the repository, install Ollama, and pull the default local vision model:

```sh
git clone <your-repository-url>
cd image-autonamer
ollama pull qwen3-vl:4b
```

Preview names for images in Downloads without changing anything:

```sh
./bin/image-autonamer --dry-run ~/Downloads
```

Rename one image:

```sh
./bin/image-autonamer ~/Downloads/IMG_8472.PNG
```

Rename every unprocessed image currently in Downloads:

```sh
./bin/image-autonamer ~/Downloads
```

## Automatic Downloads watching on macOS

Install the launch agent:

```sh
./scripts/install-launch-agent.sh
```

The installer marks images already in Downloads as processed, so enabling automation does not unexpectedly rename your existing library.
After installation, a new image normally gets renamed within one minute.
The agent combines a filesystem trigger with a one-minute interval so partially downloaded files get another chance after the 15-second settling period.

The repository must remain at the same path because the launch agent runs its checked-out script directly.
If you move the repository, run the installer again.

To watch another directory or use another model:

```sh
IMAGE_AUTONAMER_DIRECTORY="$HOME/Desktop/inbox" \
IMAGE_AUTONAMER_MODEL="qwen3-vl:8b" \
./scripts/install-launch-agent.sh
```

To uninstall automation:

```sh
./scripts/uninstall-launch-agent.sh
```

The uninstaller preserves logs and the state database.
They can be removed manually if you no longer need them.

## Command reference

```text
usage: image-autonamer [-h] [--model MODEL] [--endpoint ENDPOINT] [--dry-run]
                       [--force] [--recursive] [--settle-seconds SECONDS]
                       [--max-words 2-12] [paths ...]
```

With no path, the command scans `~/Downloads`.

| Option | Meaning |
| --- | --- |
| `--dry-run` | Ask the model and print proposed changes without renaming files. |
| `--force` | Process an image again even if it is in the state database. |
| `--recursive` | Include subdirectories. |
| `--model MODEL` | Select an installed Ollama vision model. |
| `--endpoint URL` | Use another Ollama-compatible endpoint. |
| `--settle-seconds N` | Skip files modified less than N seconds ago. |
| `--max-words N` | Limit generated filename length to 2 through 12 words. |

You can also set `IMAGE_AUTONAMER_MODEL` and `OLLAMA_HOST` in the environment.

## Safety and privacy

The image bytes are sent only to the configured Ollama endpoint, which defaults to `http://127.0.0.1:11434`.
No telemetry or third-party API is included.

The project avoids destructive behavior:

- It never overwrites a file.
- A dry run performs no rename and does not alter processing state.
- Unsupported files are ignored.
- Existing Downloads are baselined when the watcher is first installed.
- If one image fails, other images continue processing and the command exits nonzero.

The state database lives at `~/.local/state/image-autonamer/state.sqlite3` by default.
Deleting it is safe, but the next scan will treat previously processed files as new.

## Supported files

Image Autonamer recognizes AVIF, BMP, GIF, HEIC, HEIF, JPEG, PNG, TIFF, and WebP by extension.
Actual decoding support depends on the selected Ollama model and Ollama version.
PNG, JPEG, and WebP are the safest choices.

## Troubleshooting

### Cannot reach Ollama

Open the Ollama application or start its service, then verify it responds:

```sh
curl http://127.0.0.1:11434/api/tags
```

### Model not found

Pull the model named in the error:

```sh
ollama pull qwen3-vl:4b
```

### The automatic watcher does not run

Inspect its logs:

```sh
tail -f "$HOME/Library/Logs/image-autonamer/stderr.log"
```

Check its launchd status:

```sh
launchctl print "gui/$(id -u)/com.davidvaness.image-autonamer"
```

macOS may ask for permission to access Downloads.
Grant access to the relevant Python executable or terminal in System Settings if needed, then reinstall the agent.

## Development

Run the test suite without installing dependencies:

```sh
PYTHONPATH=src python3 -m unittest discover -s tests -v
```

The tests cover filename sanitization, collision handling, state tracking, dry runs, file settling, discovery, and the Ollama request/response contract.
A live VLM test is intentionally not part of CI because it requires a multi-gigabyte model.

See [CONTRIBUTING.md](CONTRIBUTING.md) for local development details.

## Design notes

launchd watches directories rather than individual file-create events.
Each invocation therefore performs an idempotent scan, while SQLite remembers the exact path, size, and modification timestamp of processed files.
This keeps the watcher simple, handles missed events after sleep or reboot, and allows changed images to be processed again.

The model is constrained to return a JSON filename field, but its output is still treated as untrusted.
The final name is normalized to lowercase ASCII words, length-limited, and stripped of path characters.
The rename uses a no-clobber hard-link operation, so even two concurrent processes cannot overwrite an existing destination.

## License

[MIT](LICENSE)
