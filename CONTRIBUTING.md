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
python -m pip install -e .
```

## Pull requests

Keep changes focused and add or update tests for behavior changes.
Do not include personal images, generated app bundles, state files, security-scoped bookmarks, or model files.
Run both test suites and verify the signed app bundle before opening a pull request.
