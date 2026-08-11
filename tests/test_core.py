from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path
from typing import Self
from unittest.mock import patch

from image_autonamer.core import (
    AutoNamerError,
    OllamaNamer,
    StateStore,
    discover_images,
    process_image,
    slugify,
    unique_destination,
)


class FakeNamer:
    def __init__(self, suggestion: str = "Red Fox in Snow") -> None:
        self.suggestion = suggestion
        self.calls: list[Path] = []

    def suggest(self, image_path: Path) -> str:
        self.calls.append(image_path)
        return self.suggestion


class FakeResponse:
    def __init__(self, body: dict[str, object]) -> None:
        self.body = body

    def __enter__(self) -> Self:
        return self

    def __exit__(self, *_: object) -> None:
        return None

    def read(self) -> bytes:
        return json.dumps(self.body).encode()


class SlugifyTests(unittest.TestCase):
    def test_normalizes_punctuation_case_and_accents(self) -> None:
        self.assertEqual(slugify('  "Café: Cat & Croissant!"  '), "cafe-cat-croissant")

    def test_limits_word_count(self) -> None:
        self.assertEqual(
            slugify("one two three four five", max_words=3), "one-two-three"
        )

    def test_removes_an_extension_returned_by_the_model(self) -> None:
        self.assertEqual(slugify("red fox in snow.PNG"), "red-fox-in-snow")

    def test_rejects_empty_output(self) -> None:
        with self.assertRaises(AutoNamerError):
            slugify("💥")


class DiscoveryTests(unittest.TestCase):
    def test_discovers_supported_images_only(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "photo.JPG").write_bytes(b"image")
            (root / "notes.txt").write_text("text")
            nested = root / "nested"
            nested.mkdir()
            (nested / "other.png").write_bytes(b"image")

            self.assertEqual(discover_images([root]), [root / "photo.JPG"])
            self.assertEqual(len(discover_images([root], recursive=True)), 2)

    def test_ignores_image_symlinks(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            target = root / "target.png"
            target.write_bytes(b"image")
            symlink = root / "alias.png"
            symlink.symlink_to(target)
            self.assertEqual(discover_images([symlink]), [])


class DestinationTests(unittest.TestCase):
    def test_adds_counter_instead_of_overwriting(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "download.JPG"
            source.write_bytes(b"source")
            (root / "red-fox-in-snow.jpg").write_bytes(b"existing")
            self.assertEqual(
                unique_destination(source, "red-fox-in-snow").name,
                "red-fox-in-snow-2.jpg",
            )


class ProcessingTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary_directory.name)
        self.state = StateStore(self.root / "state.sqlite3")

    def tearDown(self) -> None:
        self.state.close()
        self.temporary_directory.cleanup()

    def test_renames_and_records_image(self) -> None:
        source = self.root / "IMG_1234.PNG"
        source.write_bytes(b"not-a-real-image")
        result = process_image(source, FakeNamer(), self.state)
        self.assertEqual(result.status, "renamed")
        self.assertEqual(result.destination.name, "red-fox-in-snow.png")
        self.assertFalse(source.exists())
        self.assertTrue(result.destination.exists())
        self.assertTrue(self.state.contains(result.destination))

    def test_dry_run_does_not_change_or_record_image(self) -> None:
        source = self.root / "IMG_1234.png"
        source.write_bytes(b"image")
        result = process_image(source, FakeNamer(), self.state, dry_run=True)
        self.assertEqual(result.status, "dry-run")
        self.assertTrue(source.exists())
        self.assertFalse(self.state.contains(source))

    def test_processed_file_is_skipped_without_model_call(self) -> None:
        source = self.root / "already.png"
        source.write_bytes(b"image")
        self.state.mark(source)
        namer = FakeNamer()
        result = process_image(source, namer, self.state)
        self.assertEqual(result.status, "skipped")
        self.assertEqual(namer.calls, [])

    def test_changed_file_is_processed_again(self) -> None:
        source = self.root / "changed.png"
        source.write_bytes(b"first")
        self.state.mark(source)
        source.write_bytes(b"second-longer")
        result = process_image(source, FakeNamer(), self.state)
        self.assertEqual(result.status, "renamed")

    def test_recent_file_waits_to_settle(self) -> None:
        source = self.root / "recent.png"
        source.write_bytes(b"image")
        result = process_image(source, FakeNamer(), self.state, settle_seconds=60)
        self.assertEqual(result.status, "skipped")
        self.assertIn("waiting for file to settle", result.detail)

    def test_force_reprocesses_recorded_file(self) -> None:
        source = self.root / "already.png"
        source.write_bytes(b"image")
        self.state.mark(source)
        result = process_image(source, FakeNamer(), self.state, force=True)
        self.assertEqual(result.status, "renamed")

    def test_does_not_rename_a_file_that_changes_during_inference(self) -> None:
        source = self.root / "changing.png"
        source.write_bytes(b"first")

        class ChangingNamer(FakeNamer):
            def suggest(self, image_path: Path) -> str:
                image_path.write_bytes(b"changed-during-inference")
                return super().suggest(image_path)

        result = process_image(source, ChangingNamer(), self.state)
        self.assertEqual(result.status, "skipped")
        self.assertTrue(source.exists())
        self.assertIn("changed while", result.detail)


class OllamaTests(unittest.TestCase):
    def test_sends_image_and_reads_structured_filename(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            image = Path(directory) / "image.png"
            image.write_bytes(b"pixels")
            response = FakeResponse(
                {"response": json.dumps({"filename": "Golden Gate at Sunset"})}
            )
            with patch("image_autonamer.core.urlopen", return_value=response) as mocked:
                suggestion = OllamaNamer().suggest(image)

            self.assertEqual(suggestion, "Golden Gate at Sunset")
            request = mocked.call_args.args[0]
            payload = json.loads(request.data)
            self.assertEqual(payload["model"], "qwen3-vl:4b")
            self.assertEqual(payload["images"], ["cGl4ZWxz"])
            self.assertFalse(payload["stream"])
            self.assertEqual(payload["format"]["required"], ["filename"])

    def test_adds_scheme_to_ollama_host_style_endpoint(self) -> None:
        self.assertEqual(
            OllamaNamer(endpoint="127.0.0.1:11434").endpoint, "http://127.0.0.1:11434"
        )

    def test_reads_structured_filename_from_thinking_field(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            image = Path(directory) / "image.png"
            image.write_bytes(b"pixels")
            response = FakeResponse(
                {
                    "response": "",
                    "thinking": json.dumps({"filename": "Colorful Coast"}),
                }
            )
            with patch("image_autonamer.core.urlopen", return_value=response):
                suggestion = OllamaNamer().suggest(image)

            self.assertEqual(suggestion, "Colorful Coast")

    def test_rejects_nonobject_api_response(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            image = Path(directory) / "image.png"
            image.write_bytes(b"pixels")
            with (
                patch("image_autonamer.core.urlopen", return_value=FakeResponse([])),
                self.assertRaisesRegex(AutoNamerError, "unexpected response"),
            ):
                OllamaNamer().suggest(image)

    def test_rejects_malformed_response(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            image = Path(directory) / "image.png"
            image.write_bytes(b"pixels")
            with (
                patch(
                    "image_autonamer.core.urlopen",
                    return_value=FakeResponse({"response": "nope"}),
                ),
                self.assertRaisesRegex(AutoNamerError, "unexpected response"),
            ):
                OllamaNamer().suggest(image)


if __name__ == "__main__":
    unittest.main()
