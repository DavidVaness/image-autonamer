# Release process

This document separates reproducible local packaging from trusted public distribution.

## Version preparation

Update the version in `macos/Info.plist`, `pyproject.toml`, and `src/image_autonamer/__init__.py` together.
Run the complete validation gate before creating a tag.

```sh
PYTHONPATH=src python3 -m unittest discover -s tests -v
swift test
./scripts/package-release.sh 0.1.0
```

The packager refuses to continue when its requested version differs from the app bundle version.

## Ad-hoc development artifact

`scripts/package-release.sh` creates an ad-hoc signed ZIP and checksum manifest.
This is suitable for local validation and source-based development releases.
It is not a substitute for Apple notarization.

## Notarized public artifact

Trusted distribution requires an Apple Developer Program membership and a Developer ID Application certificate.
Import the certificate into the active keychain, then provide these environment variables:

```sh
export CODESIGN_IDENTITY="Developer ID Application: Example Name (TEAMID)"
export APPLE_ID="developer@example.com"
export APPLE_TEAM_ID="TEAMID"
export APPLE_APP_PASSWORD="app-specific-password"
```

Build, sign, notarize, staple, and package the DMG:

```sh
./scripts/build-macos-app.sh
./scripts/notarize-release.sh 0.1.0
```

The notarization script verifies the bundle identifier, hardened runtime signature, notarization result, stapled ticket, DMG, and checksum manifest.

## GitHub release automation

The `notarized-release.yml` workflow is credential-gated and runs only when manually dispatched.
Configure its listed GitHub Actions secrets before using it.
The workflow intentionally fails instead of publishing an ad-hoc artifact when signing credentials are absent.

## Homebrew

Create a personal Homebrew tap only after the notarized DMG can be downloaded from a stable release URL.
Submit to the official Homebrew Cask repository only after the app has public adoption and works on the latest macOS without bypassing Gatekeeper.
