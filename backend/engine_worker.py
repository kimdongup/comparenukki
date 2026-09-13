#!/usr/bin/env python3
"""Long-lived newline-delimited JSON worker for CompareNukki.

The protocol is deliberately sequential. Cancellation/timeout is implemented by
terminating this process, because native ONNX/PyTorch calls cannot be reliably
interrupted from another Python thread.
"""

from __future__ import annotations

from contextlib import redirect_stdout
import json
import logging
import os
import sys
from typing import Any

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


logging.basicConfig(
    stream=sys.stderr,
    level=getattr(
        logging,
        os.environ.get("NUKKI_LOG_LEVEL", "WARNING").upper(),
        logging.WARNING,
    ),
    format="%(asctime)s %(levelname)s %(name)s: %(message)s",
)
LOGGER = logging.getLogger("engine_worker")


def emit(message: dict[str, Any]) -> None:
    """Write one protocol frame; stdout is reserved exclusively for JSONL."""
    sys.stdout.write(
        json.dumps(
            message,
            ensure_ascii=False,
            separators=(",", ":"),
            allow_nan=False,
        )
        + "\n"
    )
    sys.stdout.flush()


def emit_error(request_id: Any, error: str) -> None:
    emit(
        {
            "type": "error",
            "request_id": request_id,
            "error": error,
        }
    )


def run_command(command: dict[str, Any]) -> None:
    request_id = command.get("request_id")
    image = command.get("image")
    output_dir = command.get("output_dir")
    if request_id is None:
        raise ValueError("request_id is required")
    if not isinstance(image, str) or not image:
        raise ValueError("image must be a non-empty path string")
    if not isinstance(output_dir, str) or not output_dir:
        raise ValueError("output_dir must be a non-empty path string")

    selected_engines = resolve_engine_ids(command.get("engine", "all"))
    absolute_image = os.path.abspath(image)
    results: list[dict[str, Any]] = []
    with snapshot_input(absolute_image) as (snapshot_path, input_sha256):
        for engine_id in selected_engines:
            emit(
                {
                    "type": "engine_started",
                    "request_id": request_id,
                    "engine_id": engine_id,
                    "total": len(selected_engines),
                }
            )
            # Some optional third-party runtimes use print() during model loading.
            # Redirect those messages so stdout remains a valid JSONL stream.
            with redirect_stdout(sys.stderr):
                result = execute_engine(
                    engine_id,
                    image_path=snapshot_path,
                    output_dir=os.path.abspath(output_dir),
                    input_sha256=input_sha256,
                )
            results.append(result)
            emit(
                {
                    "type": "engine_result",
                    "request_id": request_id,
                    "result": result,
                }
            )

    emit(
        {
            "type": "complete",
            "request_id": request_id,
            "status": completion_status(results),
        }
    )


def main() -> int:
    for raw_line in sys.stdin:
        if not raw_line.strip():
            continue
        request_id: Any = None
        try:
            decoded = json.loads(raw_line)
            if not isinstance(decoded, dict):
                raise ValueError("protocol message must be a JSON object")
            request_id = decoded.get("request_id")
            command = decoded.get("command")
            if command == "shutdown":
                emit(
                    {
                        "type": "complete",
                        "request_id": request_id,
                        "status": "shutdown",
                    }
                )
                return 0
            if command != "run":
                raise ValueError("command must be 'run' or 'shutdown'")
            run_command(decoded)
        except (TypeError, ValueError) as error:
            emit_error(request_id, str(error))
        except Exception as error:
            LOGGER.exception("Unhandled worker request failure")
            emit_error(request_id, str(error))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
