# Contributing

Thanks for helping improve Image Autonamer.

## Local setup

Image Autonamer has no runtime dependencies beyond Python 3.11 or newer.
Clone the repository and run the tests directly:

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
Do not include personal images, generated state databases, model files, or launchd logs.
Run the full test suite before opening a pull request.
