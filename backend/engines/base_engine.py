"""Shared result, timing, memory, and image-output helpers for engines."""

from __future__ import annotations

from contextlib import contextmanager
import hashlib
import os
import threading
from time import perf_counter
from typing import Any, Iterator

import cv2
import numpy as np
import psutil


MIB = 1024 * 1024


class EngineUnavailableError(RuntimeError):
    """Raised when an optional runtime or required checkpoint is unavailable."""


def build_engine_result(
    *,
    engine_id: str,
    name: str,
    framework: str,
    description: str,
    status: str,
    backend_used: str,
    model_version: str,
    provider: str,
    error: str | None = None,
    session_reused: bool = False,
    latency_ms: float | None = None,
    peak_memory_mb: float | None = None,
    peak_rss_mb: float | None = None,
    baseline_rss_mb: float | None = None,
    phase_timings_ms: dict[str, float] | None = None,
    diagnostics: dict[str, Any] | None = None,
    output_path: str | None = None,
    mask_path: str | None = None,
    resolution: str | None = None,
    benchmark_config: dict[str, Any] | None = None,
    input_sha256: str | None = None,
    cache_key: str | None = None,
    code_snippet: str = "",
) -> dict[str, Any]:
    """Build the single result envelope shared by loaded and unloaded engines."""
    if status not in {"success", "unavailable", "failed"}:
        raise ValueError(f"unsupported engine status: {status}")
    return {
        "engine_id": engine_id,
        "name": name,
        "framework": framework,
        "description": description,
        "status": status,
        "backend_used": backend_used,
        "model_version": model_version,
        "provider": provider,
        "error": error,
        "rankable": status == "success",
        "session_reused": session_reused,
        "latency_ms": latency_ms,
        "peak_memory_mb": peak_memory_mb,
        "peak_rss_mb": peak_rss_mb,
        "baseline_rss_mb": baseline_rss_mb,
        "phase_timings_ms": phase_timings_ms,
        "diagnostics": diagnostics,
        "output_path": output_path,
        "mask_path": mask_path,
        "resolution": resolution,
        "benchmark_config": benchmark_config,
        "input_sha256": input_sha256,
        "cache_key": cache_key,
        "code_snippet": code_snippet,
    }


class PhaseTimings:
    """Collect wall-clock duration for named phases with a monotonic clock."""

    def __init__(self) -> None:
        self._milliseconds: dict[str, float] = {}

    @contextmanager
    def measure(self, name: str) -> Iterator[None]:
        started = perf_counter()
        try:
            yield
        finally:
            elapsed_ms = (perf_counter() - started) * 1000.0
            self._milliseconds[name] = self._milliseconds.get(name, 0.0) + elapsed_ms

    def as_dict(self) -> dict[str, float]:
        return {name: round(value, 2) for name, value in self._milliseconds.items()}


class PeakRssSampler:
    """Sample this process' RSS during one run.

    ``peak_memory_mb`` remains compatible with the old result schema and now means
    the sampled increase above RSS at the start of the run. ``peak_rss_mb`` is the
    sampled absolute process resident-set high-water mark for the same interval.
    """

    def __init__(self, interval_seconds: float = 0.005) -> None:
        self._interval_seconds = interval_seconds
        self._process = psutil.Process(os.getpid())
        self._stop = threading.Event()
        self._thread: threading.Thread | None = None
        self._baseline_bytes = 0
        self._peak_bytes = 0

    def _sample(self) -> None:
        try:
            rss = self._process.memory_info().rss
        except (psutil.Error, OSError):
            return
        self._peak_bytes = max(self._peak_bytes, rss)

    def _run(self) -> None:
        while not self._stop.wait(self._interval_seconds):
            self._sample()

    def __enter__(self) -> "PeakRssSampler":
        self._sample()
        self._baseline_bytes = self._peak_bytes
        self._thread = threading.Thread(
            target=self._run,
            name="nukki-rss-sampler",
            daemon=True,
        )
        self._thread.start()
        return self

    def __exit__(self, exc_type: Any, exc: Any, traceback: Any) -> None:
        self._sample()
        self._stop.set()
        if self._thread is not None:
            self._thread.join()

    @property
    def peak_delta_mb(self) -> float:
        return max(0, self._peak_bytes - self._baseline_bytes) / MIB

    @property
    def peak_rss_mb(self) -> float:
        return self._peak_bytes / MIB

    @property
    def baseline_rss_mb(self) -> float:
        return self._baseline_bytes / MIB


def sha256_file(path: str) -> str:
    digest = hashlib.sha256()
    with open(path, "rb") as source:
        for chunk in iter(lambda: source.read(MIB), b""):
            digest.update(chunk)
    return digest.hexdigest()


class BaseNukkiEngine:
    def __init__(
        self,
        *,
        engine_id: str,
        name: str,
        framework: str,
        description: str,
        backend_used: str,
        model_version: str,
        provider: str,
    ) -> None:
        self.engine_id = engine_id
        self.name = name
        self.framework = framework
        self.description = description
        self.backend_used = backend_used
        self.model_version = model_version
        self.provider = provider
        self._initial_model_version = model_version
        self._initial_provider = provider
        self.model_sha256: str | None = None

    def process(self, image_path: str, output_path: str, mask_path: str) -> dict[str, Any]:
        raise NotImplementedError

    def get_code_snippet(self) -> str:
        raise NotImplementedError

    def get_benchmark_config(self) -> dict[str, Any]:
        return {"pipeline_schema": 2}

    def cache_identity(self) -> dict[str, Any]:
        return {
            "engine_id": self.engine_id,
            "backend_used": self.backend_used,
            "model_version": self.model_version,
            "model_sha256": self.model_sha256,
            "provider": self.provider,
            "config": self.get_benchmark_config(),
        }

    @property
    def has_loaded_resources(self) -> bool:
        return False

    @property
    def uses_model_resources(self) -> bool:
        """Whether running this engine may load a resident model/session."""
        return False

    def release_resources(self) -> None:
        """Release heavyweight model/session references when the LRU evicts this engine."""
        self.model_sha256 = None
        self.model_version = self._initial_model_version
        self.provider = self._initial_provider

    def compute_mask_compactness(self, mask: np.ndarray) -> float:
        """Return a shape diagnostic; this is not a ground-truth quality score."""
        contours, _ = cv2.findContours(mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_NONE)
        if not contours:
            return 0.0
        total_points = sum(len(contour) for contour in contours)
        total_area = cv2.countNonZero(mask)
        if total_points == 0 or total_area == 0:
            return 0.0
        compactness = (total_area / (total_points**2 + 1e-5)) * 12.56
        return round(float(min(1.0, max(0.0, compactness))), 4)

    def save_results(
        self,
        original_bgr: np.ndarray,
        alpha_mask: np.ndarray,
        output_path: str,
        mask_path: str,
    ) -> None:
        """Save BGRA output and grayscale alpha, checking both encoder writes."""
        if original_bgr.ndim != 3 or original_bgr.shape[2] != 3:
            raise ValueError("original image must be an HxWx3 BGR array")
        if alpha_mask.shape != original_bgr.shape[:2]:
            raise ValueError(
                f"mask shape {alpha_mask.shape} does not match image shape "
                f"{original_bgr.shape[:2]}"
            )
        if alpha_mask.dtype != np.uint8:
            alpha = np.asarray(alpha_mask, dtype=np.float32)
            if not np.isfinite(alpha).all():
                raise ValueError("alpha mask contains non-finite values")
            if alpha.size and alpha.max() <= 1.0 and alpha.min() >= 0.0:
                alpha *= 255.0
            alpha_mask = np.clip(alpha, 0.0, 255.0).astype(np.uint8)

        os.makedirs(os.path.dirname(os.path.abspath(output_path)), exist_ok=True)
        os.makedirs(os.path.dirname(os.path.abspath(mask_path)), exist_ok=True)
        rgba = np.empty((*original_bgr.shape[:2], 4), dtype=np.uint8)
        rgba[:, :, :3] = original_bgr
        rgba[:, :, 3] = alpha_mask
        if not cv2.imwrite(output_path, rgba):
            raise OSError(f"failed to write output image: {output_path}")
        if not cv2.imwrite(mask_path, alpha_mask):
            raise OSError(f"failed to write alpha mask: {mask_path}")

    def success_result(
        self,
        *,
        latency_ms: float,
        peak_memory_mb: float,
        peak_rss_mb: float,
        baseline_rss_mb: float,
        phase_timings_ms: dict[str, float],
        mask_compactness: float,
        output_path: str,
        mask_path: str,
        resolution: str,
    ) -> dict[str, Any]:
        return build_engine_result(
            engine_id=self.engine_id,
            name=self.name,
            framework=self.framework,
            description=self.description,
            status="success",
            backend_used=self.backend_used,
            model_version=self.model_version,
            provider=self.provider,
            latency_ms=round(latency_ms, 2),
            peak_memory_mb=round(peak_memory_mb, 2),
            peak_rss_mb=round(peak_rss_mb, 2),
            baseline_rss_mb=round(baseline_rss_mb, 2),
            phase_timings_ms=phase_timings_ms,
            diagnostics={"mask_compactness": mask_compactness},
            output_path=output_path,
            mask_path=mask_path,
            resolution=resolution,
            benchmark_config=self.get_benchmark_config(),
            code_snippet=self.get_code_snippet(),
        )

    def error_result(self, *, status: str, error: str) -> dict[str, Any]:
        if status not in {"unavailable", "failed"}:
            raise ValueError(f"unsupported error status: {status}")
        return build_engine_result(
            engine_id=self.engine_id,
            name=self.name,
            framework=self.framework,
            description=self.description,
            status=status,
            backend_used=self.backend_used,
            model_version=self.model_version,
            provider=self.provider,
            error=error,
            benchmark_config=self.get_benchmark_config(),
            code_snippet=self.get_code_snippet(),
        )
