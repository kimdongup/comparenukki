"""Hardware acceleration detection and device selection utilities.

Automatically detects Apple Silicon (MPS / CoreML), NVIDIA (CUDA), DirectML,
and falls back safely to CPU across ONNX Runtime and PyTorch engines.
"""

from __future__ import annotations

import logging
import os
from typing import Any

LOGGER = logging.getLogger(__name__)


def get_optimal_torch_device() -> str:
    """Returns the best available PyTorch device ('cuda', 'mps', or 'cpu')."""
    # 1. Check explicit environment override
    override = os.environ.get("NUKKI_TORCH_DEVICE")
    if override:
        return override

    # 2. Check CUDA (NVIDIA GPU)
    try:
        import torch
        if torch.cuda.is_available():
            return "cuda"
    except Exception:
        pass

    # 3. Check Apple Silicon Metal (MPS)
    try:
        import torch
        if hasattr(torch.backends, "mps") and torch.backends.mps.is_available():
            return "mps"
    except Exception:
        pass

    # 4. Fallback to CPU
    return "cpu"


def clear_torch_device_cache() -> None:
    """Frees device cache on GPU or MPS if available."""
    try:
        import torch
        if torch.cuda.is_available():
            torch.cuda.empty_cache()
        elif hasattr(torch.backends, "mps") and torch.backends.mps.is_available():
            if hasattr(torch.mps, "empty_cache"):
                torch.mps.empty_cache()
    except Exception:
        pass


def get_optimal_ort_providers() -> list[str | tuple[str, dict[str, Any]]]:
    """Returns an ordered list of ONNX Runtime execution providers to try.

    Priority:
    1. Explicit override via NUKKI_ORT_PROVIDER
    2. CUDAExecutionProvider / ROCMExecutionProvider
    3. CoreMLExecutionProvider (Apple Silicon NPU/GPU)
    4. DirectMLExecutionProvider (Windows DirectX)
    5. CPUExecutionProvider
    """
    # 1. Check explicit override
    override = os.environ.get("NUKKI_ORT_PROVIDER")
    if override:
        return [override, "CPUExecutionProvider"]

    try:
        import onnxruntime as ort
        available = ort.get_available_providers()
    except Exception:
        return ["CPUExecutionProvider"]

    providers: list[str | tuple[str, dict[str, Any]]] = []

    # CUDA
    if "CUDAExecutionProvider" in available:
        providers.append("CUDAExecutionProvider")

    # ROCm (AMD GPU on Linux)
    if "ROCMExecutionProvider" in available:
        providers.append("ROCMExecutionProvider")

    # Apple Silicon CoreML
    if "CoreMLExecutionProvider" in available:
        providers.append(
            (
                "CoreMLExecutionProvider",
                {
                    "coreml_subgraph_runner_mode": "0",  # 0: Automatic model execution
                },
            )
        )

    # Windows DirectML
    if "DirectMLExecutionProvider" in available:
        providers.append("DirectMLExecutionProvider")

    # Always add CPUExecutionProvider as the safe fallback
    if "CPUExecutionProvider" not in [
        p if isinstance(p, str) else p[0] for p in providers
    ]:
        providers.append("CPUExecutionProvider")

    return providers
