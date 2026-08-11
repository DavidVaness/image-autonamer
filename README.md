# Image Autonamer

Give downloaded images useful names automatically without uploading them to a cloud service.

Image Autonamer is a small, sandboxed macOS menu-bar app.
It watches Downloads, asks a vision-language model running locally in [Ollama](https://ollama.com/) what each new image contains, sanitizes the answer, and safely renames the file.

```text
IMG_8472.PNG  ->  orange-cat-sleeping-on-sofa.png
download.jpg  ->  mountain-lake-under-storm-clouds.jpg
image.webp    ->  blue-product-dashboard-with-charts.webp
```

## Why this exists

Downloads folders quickly fill up with UUIDs, camera counters, and names such as `image (12).png`.
Cloud vision APIs can fix that, but uploading personal screenshots and photos just to rename them is an uncomfortable trade.
Image Autonamer keeps inference local and limits its filesystem access to the Downloads folder you explicitly select.

## Features

- Runs image understanding locally through Ollama.
- Watches for new top-level images in Downloads every 15 seconds.
- Starts automatically at login through the native macOS login-item API.
- Sandboxes the app with only user-selected file access and outbound network access.
- Stores a security-scoped bookmark after a one-time Downloads folder selection.
- Protects every image already in Downloads during first-time setup.
- Waits for files to settle before processing them.
- Never overwrites an existing file and adds `-2`, `-3`, and so on for collisions.
- Includes a standalone Python CLI for manual and recursive batch jobs.

## Requirements

- macOS 13 or newer for the menu-bar app.
- [Ollama](https://ollama.com/download) with the `qwen3-vl:4b` model.
- Swift 6 and the Xcode Command Line Tools to build from source.
- About 3.3 GB of disk space for the default model.

## Quick start

Install Ollama, pull the local model, clone the repository, and run the installer:

```sh
ollama pull qwen3-vl:4b
git clone git@github.com:DavidVaness/image-autonamer.git
cd image-autonamer
./scripts/install-macos-app.sh
```

On first launch, macOS opens a folder picker with Downloads selected.
Click **Allow Downloads** once.
The app stores that choice as a security-scoped bookmark inside its sandbox and does not require Full Disk Access.

The installer puts `Image Autonamer.app` in `~/Applications` and opens it.
Use the photo/checkmark icon in the menu bar to scan manually, open Downloads, reauthorize the folder, inspect recent activity, or disable Launch at Login.

Existing images are protected during the first scan.
Only images added afterward are renamed automatically unless you explicitly choose **Process Existing Images…** from the menu.

## Security model

The local build is ad-hoc signed with these sandbox entitlements:

- App Sandbox.
- User-selected files with read/write access.
- Outbound network client access.

The app accepts only the actual Downloads folder in its picker.
macOS supplies a security-scoped capability for that selected folder, and the app persists the capability as a bookmark in its private container.
It has no Full Disk Access, no automation entitlement, and no permission to inspect unrelated folders.

Image bytes are sent to the configured Ollama endpoint, which defaults to `http://127.0.0.1:11434`.
The sandbox network entitlement technically permits outbound client connections, but the shipped code uses only that local endpoint.
The project includes no telemetry or third-party API.

The rename path is also defensive:

- Unsupported files and symbolic links are ignored.
- Model output is treated as untrusted and reduced to a lowercase ASCII slug.
- A hard-link-first rename prevents accidental overwrites even when operations race.
- If a generated name already exists, the app chooses the next numbered suffix.
- The state file is kept inside the app's sandbox container.

## Supported images

The native app recognizes AVIF, BMP, GIF, HEIC, HEIF, JPEG, PNG, TIFF, and WebP by extension.
AppKit converts the image to PNG before sending it to Ollama, which also makes HEIC and other macOS-readable formats reliable.

Only files directly inside Downloads are watched.
Subfolders are intentionally excluded to keep the automatic scope predictable.

## Manual CLI

The Python CLI remains useful for dry runs, one-off images, recursive folders, or Linux.
It requires Python 3.11 or newer.

Preview names without changing files:

```sh
./bin/image-autonamer --dry-run ~/Downloads
```

Rename one image:

```sh
./bin/image-autonamer ~/Downloads/IMG_8472.PNG
```

Process a directory tree:

```sh
./bin/image-autonamer --recursive /path/to/images
```

Run `./bin/image-autonamer --help` for the complete command reference.
The CLI is not sandboxed, so macOS may apply the permissions of the terminal or Python process that launches it.
Use the native app for automatic Downloads watching.

## Troubleshooting

### Ollama is unavailable

Open Ollama and verify the local endpoint:

```sh
curl http://127.0.0.1:11434/api/tags
```

Pull the default model if it is missing:

```sh
ollama pull qwen3-vl:4b
```

### Folder access was cancelled

Open the menu-bar icon and choose **Choose Downloads…** or **Reauthorize Downloads…**.
Select Downloads and click **Allow Downloads**.

There is no `+` button to find in System Settings and Full Disk Access is not needed.

### The menu-bar icon is hidden

macOS may place extra status items behind Control Center when menu-bar space is limited.
Open Control Center or quit another menu-bar utility temporarily.

### Build uses the wrong Swift toolchain

Point the installer at a specific Swift binary:

```sh
SWIFT_BIN=/path/to/swift ./scripts/install-macos-app.sh
```

## Development

Run the native tests:

```sh
swift test
```

Build and verify the signed app bundle:

```sh
./scripts/build-macos-app.sh
codesign --verify --deep --strict "dist/Image Autonamer.app"
```

Run the Python tests:

```sh
PYTHONPATH=src python3 -m unittest discover -s tests -v
```

The native tests cover filename sanitization, first-run protection, safe renaming, and collision handling.
The Python suite additionally covers the CLI, state database, file settling, discovery, and Ollama request/response contract.
A live VLM test is intentionally excluded from CI because it requires a multi-gigabyte model.

See [CONTRIBUTING.md](CONTRIBUTING.md) for contribution details.

## Uninstall

Open the menu-bar icon, turn off **Launch at Login**, and quit the app.
Then move `~/Applications/Image Autonamer.app` to Trash.

The sandbox container remains at `~/Library/Containers/com.davidvaness.image-autonamer` so reinstalling preserves folder authorization and processing state.
You can remove that container manually if you also want to erase the saved state and bookmark.

## License

[MIT](LICENSE)
