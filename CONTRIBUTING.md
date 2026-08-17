# Contributing

Thanks for helping improve Image Autonamer.

## Local setup

The native app requires macOS 13 or newer, Swift 6, and the Xcode Command Line Tools.
Run its tests and build the signed app bundle:

```sh
swift test
./scripts/build-macos-app.sh
codesign --verify --deep --strict "dist/Image Autonamer.app"
```

The manual CLI has no runtime dependencies beyond Python 3.11 or newer.
Run its tests directly:

```sh
PYTHONPATH=src python3 -m unittest discover -s tests -v
```

For an editable command-line installation:

```sh
python3 -m venv .venv
. .venv/bin/activate
python -m pip install -e '.[dev]'
```

## Pull requests

Keep changes focused and add or update tests for behavior changes.
Do not include personal images, generated app bundles, state files, security-scoped bookmarks, or model files.
Run both test suites and verify the signed app bundle before opening a pull request.

## Product scope

Image Autonamer intentionally does one thing: it gives newly downloaded images and PDFs useful filenames using local inference.
Improvements to naming quality, reliability, privacy, installation, accessibility, and failure recovery are welcome.
General file organization, photo management, cloud inference, and image editing are deliberately outside the project scope.

Read [ROADMAP.md](ROADMAP.md) before proposing a substantial feature.

## Evaluation corpus

Every fixture under `eval/fixtures` must be original work or have an unambiguous license that permits redistribution under this repository's MIT license.
Do not contribute personal screenshots, receipts, photos, names, addresses, or account information.

Rebuild fixture PNGs and run the local quality evaluation with:

```sh
./scripts/build-eval-fixtures.sh
./eval/run.py --model qwen3-vl:4b --output eval/results/qwen3-vl-4b.json
```

Evaluation thresholds should not be weakened to make a model pass.
Update expected concepts only when a reasonable human description of the image supports the change.

## Security

Do not report vulnerabilities through a public issue.
Follow [SECURITY.md](SECURITY.md) and use GitHub private vulnerability reporting.
