# Demo capture

The repository's primary GIF and MP4 use recordings of the real macOS app.
The recordings contain only synthetic PDFs from `eval/fixtures` and a temporary demo folder.
Each app window is captured independently, so the desktop and personal files never appear in published media.

The capture harness is compiled only in debug builds and activates only when `--capture-demo` is passed explicitly.
It never changes the normal release app.

Build the debug app:

```sh
swift build
```

Open General or Naming Settings against an isolated folder:

```sh
.build/debug/ImageAutonamerMac --capture-demo
.build/debug/ImageAutonamerMac --capture-demo --capture-naming
```

Populate Review Inbox and History with real local Ollama inference:

```sh
IMAGE_AUTONAMER_DEMO_FIXTURE="$PWD/eval/fixtures/north-star-invoice.pdf" \
  .build/debug/ImageAutonamerMac --capture-demo --capture-review

IMAGE_AUTONAMER_DEMO_FIXTURE="$PWD/eval/fixtures/north-star-invoice.pdf" \
  .build/debug/ImageAutonamerMac --capture-demo --capture-review --capture-history
```

The committed raw recordings live in `docs/demo/captures`.
`scripts/build-demo.sh` crops only the app windows and generates the final 46-second MP4 with original title cards.
It also creates a compact 33-second app-only GIF preview for the README.
