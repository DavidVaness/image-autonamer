"""Command-line interface for image-autonamer."""

from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path

from . import __version__
from .core import (
    AutoNamerError,
    OllamaNamer,
    StateStore,
    discover_images,
    process_image,
)


def default_state_path() -> Path:
    state_home = os.environ.get("XDG_STATE_HOME")
    root = Path(state_home) if state_home else Path.home() / ".local" / "state"
    return root / "image-autonamer" / "state.sqlite3"


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="image-autonamer",
        description="Rename images using a private vision model running in Ollama.",
    )
    parser.add_argument(
        "paths",
        nargs="*",
        type=Path,
        help="Image files or directories (default: ~/Downloads)",
    )
    parser.add_argument(
        "--model", default=os.environ.get("IMAGE_AUTONAMER_MODEL", "qwen3-vl:4b")
    )
    parser.add_argument(
        "--endpoint",
        default=os.environ.get("OLLAMA_HOST", "http://127.0.0.1:11434"),
        help="Ollama base URL",
    )
    parser.add_argument(
        "--state-file", type=Path, default=default_state_path(), help=argparse.SUPPRESS
    )
    parser.add_argument(
        "--dry-run", action="store_true", help="Show proposed names without renaming"
    )
    parser.add_argument(
        "--force",
        action="store_true",
        help="Reprocess files already in the state database",
    )
    parser.add_argument("--recursive", action="store_true", help="Scan subdirectories")
    parser.add_argument(
        "--settle-seconds", type=float, default=0, help="Skip files newer than this age"
    )
    parser.add_argument(
        "--max-words", type=int, default=8, choices=range(2, 13), metavar="2-12"
    )
    parser.add_argument(
        "--mark-existing",
        action="store_true",
        help="Record matching files without renaming them (used during watcher installation)",
    )
    parser.add_argument(
        "--version", action="version", version=f"%(prog)s {__version__}"
    )
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    paths = args.paths or [Path.home() / "Downloads"]
    try:
        images = discover_images(paths, recursive=args.recursive)
    except OSError as error:
        print(f"error: cannot scan input paths: {error}", file=sys.stderr)
        return 1
    if not images:
        print("No supported images found.")
        return 0

    failures = 0
    with StateStore(args.state_file) as state:
        if args.mark_existing:
            for image in images:
                state.mark(image)
            print(f"Marked {len(images)} existing image(s) as already processed.")
            return 0

        namer = OllamaNamer(model=args.model, endpoint=args.endpoint)
        for image in images:
            try:
                result = process_image(
                    image,
                    namer,
                    state,
                    dry_run=args.dry_run,
                    force=args.force,
                    settle_seconds=args.settle_seconds,
                    max_words=args.max_words,
                )
            except (AutoNamerError, OSError) as error:
                print(f"error: {image}: {error}", file=sys.stderr)
                failures += 1
                continue

            if result.destination is not None and result.destination != result.source:
                arrow = "would rename" if result.status == "dry-run" else "renamed"
                print(f"{arrow}: {result.source.name} -> {result.destination.name}")
            elif result.status != "skipped" or result.detail != "already processed":
                detail = f": {result.detail}" if result.detail else ""
                print(f"{result.status}: {result.source.name}{detail}")
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
