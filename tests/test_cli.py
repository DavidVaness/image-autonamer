from __future__ import annotations

import tempfile
import unittest
from contextlib import redirect_stdout
from io import StringIO
from pathlib import Path
from unittest.mock import patch

from image_autonamer.cli import main


class CliTests(unittest.TestCase):
    def test_empty_directory_is_successful(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            output = StringIO()
            with redirect_stdout(output):
                result = main([directory])
        self.assertEqual(result, 0)
        self.assertIn("No supported images", output.getvalue())

    def test_mark_existing_avoids_model_call(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "image.png").write_bytes(b"image")
            state = root / "state.sqlite3"
            output = StringIO()
            with (
                patch("image_autonamer.cli.OllamaNamer") as namer,
                redirect_stdout(output),
            ):
                result = main(
                    ["--state-file", str(state), "--mark-existing", str(root)]
                )
        self.assertEqual(result, 0)
        namer.assert_not_called()
        self.assertIn("Marked 1 existing image", output.getvalue())

    def test_renames_an_image_end_to_end_with_model_stub(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "IMG_0001.PNG"
            source.write_bytes(b"image")
            output = StringIO()
            with (
                patch(
                    "image_autonamer.cli.OllamaNamer.suggest",
                    return_value="Blue Bird on Branch",
                ),
                redirect_stdout(output),
            ):
                result = main(
                    ["--state-file", str(root / "state.sqlite3"), str(source)]
                )

            self.assertEqual(result, 0)
            self.assertFalse(source.exists())
            self.assertTrue((root / "blue-bird-on-branch.png").exists())
            self.assertIn("IMG_0001.PNG -> blue-bird-on-branch.png", output.getvalue())


if __name__ == "__main__":
    unittest.main()
