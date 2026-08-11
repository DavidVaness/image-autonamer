#!/usr/bin/env python3
"""Render the launchd plist without unsafe text substitution."""

from __future__ import annotations

import argparse
import plistlib
from pathlib import Path
from typing import Any


def replace_placeholders(value: Any, replacements: dict[str, str]) -> Any:
    if isinstance(value, str):
        for placeholder, replacement in replacements.items():
            value = value.replace(placeholder, replacement)
        return value
    if isinstance(value, list):
        return [replace_placeholders(item, replacements) for item in value]
    if isinstance(value, dict):
        return {
            key: replace_placeholders(item, replacements) for key, item in value.items()
        }
    return value


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("template", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("project_dir")
    parser.add_argument("downloads_dir")
    parser.add_argument("model")
    parser.add_argument("home")
    args = parser.parse_args()

    with args.template.open("rb") as template_file:
        document = plistlib.load(template_file)
    rendered = replace_placeholders(
        document,
        {
            "__PROJECT_DIR__": args.project_dir,
            "__DOWNLOADS_DIR__": args.downloads_dir,
            "__MODEL__": args.model,
            "__HOME__": args.home,
        },
    )
    with args.output.open("wb") as output_file:
        plistlib.dump(rendered, output_file, sort_keys=False)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
