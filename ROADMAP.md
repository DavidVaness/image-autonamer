# Roadmap

Image Autonamer intentionally remains a focused utility.
Its product promise is simple: a new image or PDF arrives in Downloads and receives a useful filename without leaving the Mac.

## Recently shipped

- Dynamic document-type detection and type-specific filename recipes in v0.4.0.
- Visible correspondent, date, period, and safe reference extraction for documents in v0.4.0.
- Opt-in Review Inbox with editable suggestions, visible evidence, bulk approval, and keep-original handling in v0.5.0.
- Bounded rename history and collision-safe undo for both automatic and approved renames in v0.5.0.
- Local PDF page rendering, document naming, previews, and extension preservation in v0.6.0.
- Embedded-text extraction, local OCR fallback, and conservative filename-quality decisions in v0.6.0.
- An authentic Settings capture and evidence-backed PDF walkthrough in v0.6.0.

## Now

- Improve naming quality through a reproducible, redistributable evaluation corpus.
- Make installation trustworthy with Developer ID signing and Apple notarization.
- Provide clear recovery actions for Ollama, model, and folder-access failures.
- Validate the complete workflow on supported macOS versions.

## Next

- Publish a Homebrew tap after a notarized build is available.
- Evaluate a smaller default model against the same quality corpus.
- Add signed automatic updates after the release cadence is established.
- Add Intel or universal packaging when it can be tested on real hardware.

## Deliberately out of scope

- General file organization or folder routing.
- Duplicate detection and photo-library management.
- Semantic search, OCR storage, or automatic tagging databases.
- Cloud inference and team synchronization.
- Image editing or conversion workflows.

Feature requests should strengthen the core private-renaming journey rather than broaden the product category.
