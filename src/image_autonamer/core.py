"""Core image naming and filesystem operations."""

from __future__ import annotations

import base64
import json
import os
import re
import sqlite3
import time
import unicodedata
from collections.abc import Iterable
from dataclasses import dataclass
from pathlib import Path
from typing import Self
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

SUPPORTED_EXTENSIONS = frozenset(
    {
        ".avif",
        ".bmp",
        ".gif",
        ".heic",
        ".heif",
        ".jpeg",
        ".jpg",
        ".png",
        ".tif",
        ".tiff",
        ".webp",
    }
)
DEFAULT_PROMPT = """Create a concise, descriptive filename for this image.
Describe only what is visibly important and avoid guessing names, locations, or sensitive traits.
Return JSON with exactly one field named \"filename\".
The filename must contain 3 to 8 lowercase words separated by hyphens, with no extension.
Prefer concrete subjects, actions, setting, and distinctive visible text when useful.
Do not include filler words, punctuation, a path, or commentary."""


class AutoNamerError(RuntimeError):
    """A user-facing image auto-naming error."""


@dataclass(frozen=True)
class RenameResult:
    source: Path
    destination: Path | None
    status: str
    detail: str = ""


class StateStore:
    """Track processed files so directory scans are idempotent."""

    def __init__(self, path: Path) -> None:
        self.path = path.expanduser()
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self.connection = sqlite3.connect(self.path, timeout=10)
        self.connection.execute(
            """
            CREATE TABLE IF NOT EXISTS processed_files (
                path TEXT PRIMARY KEY,
                size INTEGER NOT NULL,
                mtime_ns INTEGER NOT NULL,
                processed_at INTEGER NOT NULL
            )
            """
        )
        self.connection.commit()

    def close(self) -> None:
        self.connection.close()

    def __enter__(self) -> Self:
        return self

    def __exit__(self, *_: object) -> None:
        self.close()

    def contains(self, path: Path) -> bool:
        try:
            stat = path.stat()
        except FileNotFoundError:
            return False
        row = self.connection.execute(
            "SELECT size, mtime_ns FROM processed_files WHERE path = ?",
            (str(path.resolve()),),
        ).fetchone()
        return row == (stat.st_size, stat.st_mtime_ns)

    def mark(self, path: Path) -> None:
        stat = path.stat()
        self.connection.execute(
            """
            INSERT INTO processed_files(path, size, mtime_ns, processed_at)
            VALUES (?, ?, ?, ?)
            ON CONFLICT(path) DO UPDATE SET
                size = excluded.size,
                mtime_ns = excluded.mtime_ns,
                processed_at = excluded.processed_at
            """,
            (str(path.resolve()), stat.st_size, stat.st_mtime_ns, int(time.time())),
        )
        self.connection.commit()


class OllamaNamer:
    """Generate image names with Ollama's local HTTP API."""

    def __init__(
        self,
        model: str = "qwen3-vl:4b",
        endpoint: str = "http://127.0.0.1:11434",
        timeout: float = 120.0,
        prompt: str = DEFAULT_PROMPT,
    ) -> None:
        self.model = model
        self.endpoint = endpoint.rstrip("/")
        if "://" not in self.endpoint:
            self.endpoint = f"http://{self.endpoint}"
        self.timeout = timeout
        self.prompt = prompt

    def suggest(self, image_path: Path) -> str:
        payload = {
            "model": self.model,
            "prompt": self.prompt,
            "images": [base64.b64encode(image_path.read_bytes()).decode("ascii")],
            "stream": False,
            "think": False,
            "format": {
                "type": "object",
                "properties": {"filename": {"type": "string"}},
                "required": ["filename"],
                "additionalProperties": False,
            },
            "options": {"temperature": 0.2},
        }
        request = Request(
            f"{self.endpoint}/api/generate",
            data=json.dumps(payload).encode("utf-8"),
            headers={"Content-Type": "application/json"},
            method="POST",
        )
        try:
            with urlopen(request, timeout=self.timeout) as response:
                body = json.load(response)
        except HTTPError as error:
            detail = error.read().decode("utf-8", errors="replace")
            if error.code == 404:
                raise AutoNamerError(
                    f"Ollama could not find model '{self.model}'. Run: ollama pull {self.model}"
                ) from error
            raise AutoNamerError(
                f"Ollama returned HTTP {error.code}: {detail}"
            ) from error
        except URLError as error:
            raise AutoNamerError(
                f"Cannot reach Ollama at {self.endpoint}. Install/start Ollama, then pull {self.model}."
            ) from error
        except TimeoutError as error:
            raise AutoNamerError(
                f"Ollama did not respond within {self.timeout:g} seconds."
            ) from error

        if not isinstance(body, dict):
            raise AutoNamerError("Ollama returned an unexpected response.")

        raw_name = None
        for field in ("response", "thinking"):
            candidate = body.get(field)
            if not isinstance(candidate, str) or not candidate:
                continue
            try:
                generated = json.loads(candidate)
            except (TypeError, json.JSONDecodeError):
                continue
            if isinstance(generated, dict) and isinstance(
                generated.get("filename"), str
            ):
                raw_name = generated["filename"]
                break
        if not isinstance(raw_name, str):
            raise AutoNamerError("Ollama returned an unexpected response.")
        return raw_name


def slugify(value: str, max_words: int = 8, max_length: int = 96) -> str:
    """Convert model output into a safe, portable filename stem."""
    normalized = (
        unicodedata.normalize("NFKD", value).encode("ascii", "ignore").decode("ascii")
    )
    words = re.findall(r"[a-z0-9]+", normalized.lower())[:max_words]
    extension_words = {extension.lstrip(".") for extension in SUPPORTED_EXTENSIONS}
    if words and words[-1] in extension_words:
        words.pop()
    slug = "-".join(words).strip("-.")[:max_length].rstrip("-.")
    if slug in {"", ".", ".."}:
        raise AutoNamerError("The model did not return a usable filename.")
    return slug


def unique_destination(source: Path, stem: str) -> Path:
    """Return a non-existing sibling path without overwriting anything."""
    candidate = source.with_name(f"{stem}{source.suffix.lower()}")
    counter = 2
    while candidate.exists() and candidate != source:
        candidate = source.with_name(f"{stem}-{counter}{source.suffix.lower()}")
        counter += 1
    return candidate


def discover_images(paths: Iterable[Path], recursive: bool = False) -> list[Path]:
    """Expand files and directories into a stable, unique list of images."""
    discovered: dict[str, Path] = {}
    for raw_path in paths:
        path = raw_path.expanduser()
        if path.is_file():
            candidates = [path]
        elif path.is_dir():
            candidates = path.rglob("*") if recursive else path.iterdir()
        else:
            continue
        for candidate in candidates:
            if (
                candidate.is_file()
                and not candidate.is_symlink()
                and candidate.suffix.lower() in SUPPORTED_EXTENSIONS
            ):
                discovered[str(candidate.resolve())] = candidate
    return sorted(discovered.values(), key=lambda item: str(item).lower())


def process_image(
    source: Path,
    namer: OllamaNamer,
    state: StateStore,
    *,
    dry_run: bool = False,
    force: bool = False,
    settle_seconds: float = 0,
    max_words: int = 8,
) -> RenameResult:
    """Name and rename one image while preserving data and prior work."""
    if not source.is_file() or source.suffix.lower() not in SUPPORTED_EXTENSIONS:
        return RenameResult(source, None, "skipped", "not a supported image")
    if not force and state.contains(source):
        return RenameResult(source, None, "skipped", "already processed")
    original_stat = source.stat()
    age = max(0.0, time.time() - original_stat.st_mtime)
    if age < settle_seconds:
        return RenameResult(
            source, None, "skipped", f"waiting for file to settle ({age:.0f}s old)"
        )

    stem = slugify(namer.suggest(source), max_words=max_words)
    destination = unique_destination(source, stem)
    if destination == source:
        if not dry_run:
            state.mark(source)
        return RenameResult(
            source, source, "unchanged", "already has the suggested name"
        )
    if dry_run:
        return RenameResult(source, destination, "dry-run")

    current_stat = source.stat()
    if (current_stat.st_size, current_stat.st_mtime_ns) != (
        original_stat.st_size,
        original_stat.st_mtime_ns,
    ):
        return RenameResult(
            source, None, "skipped", "file changed while it was being analyzed"
        )

    while True:
        try:
            os.link(source, destination, follow_symlinks=False)
            break
        except FileExistsError:
            destination = unique_destination(source, stem)
    source.unlink()
    state.mark(destination)
    return RenameResult(source, destination, "renamed")
