#!/usr/bin/env python3
"""One-shot CLI compatibility wrapper around the shared lazy engine registry."""

from __future__ import annotations

import argparse
from contextlib import redirect_stdout
import json
import os
import sys

try:
    from .engine_registry import (
        completion_status,
        execute_engine,
        resolve_engine_ids,
        snapshot_input,
    )
except ImportError:
    from engine_registry import (
        completion_status,
        execute_engine,
        resolve_engine_ids,
        snapshot_input,
    )


def main() -> int:
    parser = argparse.ArgumentParser(
        description="CompareNukki Multi-Engine Background Removal Runner"
    )
    parser.add_argument("--image", required=True, help="Path to input image")
    parser.add_argument(
        "--engine", default="all", help="Engine ID to run (or 'all' for all engines)"
    )
    parser.add_argument(
        "--output_dir", default="assets/outputs", help="Output directory for results"
    )
    args = parser.parse_args()

    image_path = os.path.abspath(args.image)
    if not os.path.isfile(image_path):
        print(
            json.dumps({"error": f"Image file not found at {image_path}"}),
            file=sys.stderr,
        )
        return 1

    try:
        selected_engines = resolve_engine_ids(args.engine)
    except ValueError as error:
        print(json.dumps({"error": str(error)}), file=sys.stderr)
        return 2

    output_dir = os.path.abspath(args.output_dir)
    results = {}
    try:
        with snapshot_input(image_path) as (snapshot_path, input_sha256):
            for engine_id in selected_engines:
                with redirect_stdout(sys.stderr):
                    results[engine_id] = execute_engine(
                        engine_id,
                        image_path=snapshot_path,
                        output_dir=output_dir,
                        input_sha256=input_sha256,
                    )
    except ValueError as error:
        print(json.dumps({"error": str(error)}), file=sys.stderr)
        return 1
    status = completion_status(results.values())
    print(
        json.dumps(
            {
                "status": status,
                "image": image_path,
                "input_sha256": input_sha256,
                "results": results,
            },
            indent=2,
            ensure_ascii=False,
            allow_nan=False,
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
