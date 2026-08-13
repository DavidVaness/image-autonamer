#!/usr/bin/env python3
"""Build deterministic macOS and GitHub brand assets from checked-in SVG sources."""

from __future__ import annotations

import shutil
import struct
import subprocess
import tempfile
from pathlib import Path


PROJECT_DIR = Path(__file__).resolve().parent.parent
LOGO_SOURCE = PROJECT_DIR / "docs" / "assets" / "logo.svg"
SOCIAL_SOURCE = PROJECT_DIR / "docs" / "assets" / "social-preview.svg"
ICON_OUTPUT = PROJECT_DIR / "macos" / "AppIcon.icns"
SOCIAL_OUTPUT = PROJECT_DIR / "docs" / "assets" / "social-preview.png"

ICON_REPRESENTATIONS = (
    (b"icp4", 16),
    (b"icp5", 32),
    (b"icp6", 64),
    (b"ic07", 128),
    (b"ic08", 256),
    (b"ic09", 512),
    (b"ic10", 1024),
)


def render(source: Path, destination: Path, width: int, height: int) -> None:
    with destination.open("wb") as output:
        subprocess.run(
            [
                "rsvg-convert",
                "--width",
                str(width),
                "--height",
                str(height),
                str(source),
            ],
            check=True,
            stdout=output,
        )


def build_icon() -> None:
    chunks = bytearray()
    with tempfile.TemporaryDirectory(prefix="image-autonamer-icon-") as directory:
        temporary_directory = Path(directory)
        for chunk_type, size in ICON_REPRESENTATIONS:
            png_path = temporary_directory / f"icon-{size}.png"
            render(LOGO_SOURCE, png_path, size, size)
            payload = png_path.read_bytes()
            chunks.extend(chunk_type)
            chunks.extend(struct.pack(">I", len(payload) + 8))
            chunks.extend(payload)

    ICON_OUTPUT.write_bytes(b"icns" + struct.pack(">I", len(chunks) + 8) + chunks)


def main() -> int:
    if shutil.which("rsvg-convert") is None:
        raise SystemExit("Missing required brand asset tool: rsvg-convert")
    build_icon()
    render(SOCIAL_SOURCE, SOCIAL_OUTPUT, 1280, 640)
    print(f"Built {ICON_OUTPUT.relative_to(PROJECT_DIR)}")
    print(f"Built {SOCIAL_OUTPUT.relative_to(PROJECT_DIR)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
