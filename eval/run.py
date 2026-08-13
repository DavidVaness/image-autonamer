#!/usr/bin/env python3
"""Run the local model against the original, redistributable evaluation corpus."""

from __future__ import annotations

import argparse
import json
import platform
import statistics
import sys
import time
from datetime import UTC, datetime
from pathlib import Path


PROJECT_DIR = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(PROJECT_DIR / "src"))

from image_autonamer.core import AutoNamerError, OllamaNamer, slugify  # noqa: E402


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--model", default="qwen3-vl:4b")
    parser.add_argument("--endpoint", default="http://127.0.0.1:11434")
    parser.add_argument("--output", type=Path)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    manifest_path = PROJECT_DIR / "eval" / "manifest.json"
    manifest = json.loads(manifest_path.read_text())
    namer = OllamaNamer(model=args.model, endpoint=args.endpoint)
    results = []

    for case in manifest["cases"]:
        source = (manifest_path.parent / case["path"]).resolve()
        started = time.monotonic()
        try:
            filename = slugify(namer.suggest(source))
            error = None
        except (AutoNamerError, OSError) as exception:
            filename = None
            error = str(exception)
        latency = time.monotonic() - started
        words = set((filename or "").split("-"))
        matched = [
            any(concept in words for concept in alternatives)
            for alternatives in case["expected_concepts"]
        ]
        forbidden = sorted(words.intersection(case["forbidden_concepts"]))
        recall = sum(matched) / len(matched)
        useful = filename is not None and recall >= 2 / 3 and not forbidden
        result = {
            "id": case["id"],
            "category": case["category"],
            "filename": filename,
            "latency_seconds": round(latency, 2),
            "concept_recall": round(recall, 3),
            "forbidden_concepts": forbidden,
            "useful": useful,
            "error": error,
        }
        results.append(result)
        status = "PASS" if useful else "REVIEW"
        print(f"{status:6} {case['id']:18} {filename or error} ({latency:.1f}s)")

    successful_latencies = [
        result["latency_seconds"] for result in results if result["filename"] is not None
    ]
    summary = {
        "model": args.model,
        "generated_at": datetime.now(UTC).isoformat(),
        "platform": platform.platform(),
        "cases": len(results),
        "successful": sum(result["filename"] is not None for result in results),
        "useful": sum(result["useful"] for result in results),
        "useful_rate": round(sum(result["useful"] for result in results) / len(results), 3),
        "median_latency_seconds": (
            round(statistics.median(successful_latencies), 2) if successful_latencies else None
        ),
        "results": results,
    }
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(summary, indent=2) + "\n")
        print(f"Wrote {args.output}")
    print(
        f"Useful: {summary['useful']}/{summary['cases']} "
        f"({summary['useful_rate']:.0%}); median latency: "
        f"{summary['median_latency_seconds']}s"
    )
    return 0 if summary["successful"] == summary["cases"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
