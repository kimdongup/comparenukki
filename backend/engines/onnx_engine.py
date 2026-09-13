"""Common implementation for local ONNX foreground segmentation models."""

from __future__ import annotations

import os
from time import perf_counter
from typing import Any

import cv2
import numpy as np

from .base_engine import (
    BaseNukkiEngine,
    EngineUnavailableError,
    PeakRssSampler,
    PhaseTimings,
    sha256_file,
)
try:
    from .hardware_utils import get_optimal_ort_providers
except ImportError:
    from hardware_utils import get_optimal_ort_providers


def _ort_thread_count() -> int:
    try:
        return max(1, int(os.environ.get("NUKKI_ORT_THREADS", "4")))
    except ValueError:
        return 4


class OnnxSegmentationEngine(BaseNukkiEngine):
    def __init__(
        self,
        *,
        engine_id: str,
        name: str,
        framework: str,
        description: str,
        model_env_var: str,
        model_filename: str,
        model_id: str,
        input_size: tuple[int, int],
        mean: tuple[float, float, float],
        std: tuple[float, float, float],
        interpolation: int,
        sigmoid_logits: bool,
    ) -> None:
        super().__init__(
            engine_id=engine_id,
            name=name,
            framework=framework,
            description=description,
            backend_used="onnxruntime",
            model_version=model_id,
            provider="not-loaded",
        )
        model_dir = os.path.expanduser(os.environ.get("NUKKI_MODEL_DIR", "~/.u2net"))
        self.model_env_var = model_env_var
        self.model_filename = model_filename
        self.model_path = os.path.abspath(
            os.path.expanduser(
                os.environ.get(model_env_var, os.path.join(model_dir, model_filename))
            )
        )
        self.model_id = model_id
        self.input_size = input_size
        self.mean = np.asarray(mean, dtype=np.float32).reshape(1, 1, 3)
        self.std = np.asarray(std, dtype=np.float32).reshape(1, 1, 3)
        self.interpolation = interpolation
        self.sigmoid_logits = sigmoid_logits
        self.session: Any | None = None
        self.input_name: str | None = None
        self.output_name: str | None = None

    @property
    def has_loaded_resources(self) -> bool:
        return self.session is not None

    @property
    def uses_model_resources(self) -> bool:
        return True

    def release_resources(self) -> None:
        self.session = None
        self.input_name = None
        self.output_name = None
        super().release_resources()

    def _ensure_session(self) -> None:
        if self.session is not None:
            return
        if not os.path.isfile(self.model_path):
            raise EngineUnavailableError(
                f"required checkpoint is not installed: {self.model_path}"
            )
        try:
            import onnxruntime as ort
        except ImportError as error:
            raise EngineUnavailableError(
                "onnxruntime is not installed; install it to use this engine"
            ) from error

        options = ort.SessionOptions()
        options.intra_op_num_threads = _ort_thread_count()
        options.enable_mem_pattern = True

        providers_to_try = get_optimal_ort_providers()
        session = None
        last_error = None

        try:
            session = ort.InferenceSession(
                self.model_path,
                options,
                providers=providers_to_try,
            )
        except Exception as error:
            last_error = error
            # If accelerated provider fails (e.g. CoreML subgraph issue), fallback to CPU
            try:
                session = ort.InferenceSession(
                    self.model_path,
                    options,
                    providers=["CPUExecutionProvider"],
                )
            except Exception as cpu_error:
                raise EngineUnavailableError(
                    f"Failed to initialize ONNX session: {last_error}; CPU fallback error: {cpu_error}"
                ) from cpu_error

        inputs = session.get_inputs()
        outputs = session.get_outputs()
        if not inputs or not outputs:
            raise RuntimeError("ONNX model has no usable input or output")
        providers = session.get_providers()
        if not providers:
            raise RuntimeError("ONNX Runtime did not report an active provider")
        model_sha256 = sha256_file(self.model_path)

        # Commit only after the session and all identity metadata are complete.
        self.session = session
        self.input_name = inputs[0].name
        self.output_name = outputs[0].name
        self.provider = providers[0]
        self.model_sha256 = model_sha256
        self.model_version = f"{self.model_id}@sha256:{model_sha256[:12]}"

    def get_benchmark_config(self) -> dict[str, Any]:
        return {
            "pipeline_schema": 2,
            "input_size": list(self.input_size),
            "mean": self.mean.reshape(3).tolist(),
            "std": self.std.reshape(3).tolist(),
            "output_index": 0,
            "sigmoid_logits": self.sigmoid_logits,
            "resize_interpolation": int(self.interpolation),
            "ort_threads": _ort_thread_count(),
        }

    def get_code_snippet(self) -> str:
        """Return a runnable reproduction of this engine's measured ONNX path."""
        mean = tuple(float(value) for value in self.mean.reshape(3))
        std = tuple(float(value) for value in self.std.reshape(3))
        interpolation_name = {
            cv2.INTER_AREA: "cv2.INTER_AREA",
            cv2.INTER_LANCZOS4: "cv2.INTER_LANCZOS4",
        }.get(self.interpolation, str(int(self.interpolation)))
        return f'''import hashlib
import os

import cv2
import numpy as np

# This is the same direct ONNX Runtime path used by the benchmark engine.
model_dir = os.path.expanduser(os.environ.get("NUKKI_MODEL_DIR", "~/.u2net"))
model_path = os.path.abspath(os.path.expanduser(os.environ.get(
    {self.model_env_var!r}, os.path.join(model_dir, {self.model_filename!r})
)))
if not os.path.isfile(model_path):
    raise FileNotFoundError(f"required checkpoint is not installed: {{model_path}}")

try:
    import onnxruntime as ort
except ImportError as error:
    raise RuntimeError("onnxruntime is not installed") from error

try:
    ort_threads = max(1, int(os.environ.get("NUKKI_ORT_THREADS", "4")))
except ValueError:
    ort_threads = 4
options = ort.SessionOptions()
options.intra_op_num_threads = ort_threads
preferred_provider = os.environ.get("NUKKI_ORT_PROVIDER", "CPUExecutionProvider")
available_providers = ort.get_available_providers()
if preferred_provider not in available_providers:
    raise RuntimeError(
        f"requested ONNX provider {{preferred_provider!r}} is unavailable; "
        f"available providers: {{available_providers}}"
    )

session = ort.InferenceSession(
    model_path,
    options,
    providers=[preferred_provider],
)
inputs = session.get_inputs()
outputs = session.get_outputs()
if not inputs or not outputs:
    raise RuntimeError("ONNX model has no usable input or output")
active_providers = session.get_providers()
if not active_providers:
    raise RuntimeError("ONNX Runtime did not report an active provider")
input_name = inputs[0].name
output_name = outputs[0].name

# The benchmark hashes the same checkpoint bytes for its cache identity.
digest = hashlib.sha256()
with open(model_path, "rb") as checkpoint:
    for chunk in iter(lambda: checkpoint.read(1024 * 1024), b""):
        digest.update(chunk)
model_sha256 = digest.hexdigest()

image = cv2.imread("input.jpg", cv2.IMREAD_COLOR)
if image is None:
    raise FileNotFoundError("cannot read image: input.jpg")
height, width = image.shape[:2]

input_size = {self.input_size!r}
mean = np.asarray({mean!r}, dtype=np.float32).reshape(1, 1, 3)
std = np.asarray({std!r}, dtype=np.float32).reshape(1, 1, 3)
resized = cv2.resize(image, input_size, interpolation={interpolation_name})
normalized = cv2.cvtColor(resized, cv2.COLOR_BGR2RGB).astype(np.float32)
normalized *= 1.0 / 255.0
normalized -= mean
normalized /= std
input_tensor = np.ascontiguousarray(normalized.transpose(2, 0, 1)[None, ...])

output = session.run([output_name], {{input_name: input_tensor}})[0]
prediction = np.squeeze(output).astype(np.float32, copy=False)
if prediction.ndim != 2:
    raise RuntimeError("unexpected ONNX output shape %r" % (tuple(output.shape),))
if not np.isfinite(prediction).all():
    raise RuntimeError("ONNX output contains non-finite values")
sigmoid_logits = {self.sigmoid_logits!r}
if sigmoid_logits:
    np.clip(prediction, -60.0, 60.0, out=prediction)
    prediction = 1.0 / (1.0 + np.exp(-prediction))
low = float(prediction.min())
high = float(prediction.max())
if high - low <= 1e-8:
    normalized = np.zeros_like(prediction, dtype=np.float32)
else:
    normalized = prediction - low
    normalized *= 1.0 / (high - low)
alpha_mask = np.clip(normalized * 255.0, 0.0, 255.0).astype(np.uint8)
alpha_mask = cv2.resize(
    alpha_mask, (width, height), interpolation=cv2.INTER_LANCZOS4
)

contours, _ = cv2.findContours(
    alpha_mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_NONE
)
total_points = sum(len(contour) for contour in contours)
total_area = cv2.countNonZero(alpha_mask)
if not contours or total_points == 0 or total_area == 0:
    mask_compactness = 0.0
else:
    compactness = (total_area / (total_points**2 + 1e-5)) * 12.56
    mask_compactness = round(float(min(1.0, max(0.0, compactness))), 4)

rgba = np.empty((*image.shape[:2], 4), dtype=np.uint8)
rgba[:, :, :3] = image
rgba[:, :, 3] = alpha_mask
output_path = os.path.abspath("output_{self.engine_id}.png")
mask_path = os.path.abspath("mask_{self.engine_id}.png")
if not cv2.imwrite(output_path, rgba):
    raise OSError(f"failed to write output image: {{output_path}}")
if not cv2.imwrite(mask_path, alpha_mask):
    raise OSError(f"failed to write alpha mask: {{mask_path}}")

print({{"provider": active_providers[0], "model_sha256": model_sha256,
       "mask_compactness": mask_compactness}})
'''

    def _preprocess(self, image_bgr: np.ndarray) -> np.ndarray:
        resized = cv2.resize(image_bgr, self.input_size, interpolation=self.interpolation)
        normalized = cv2.cvtColor(resized, cv2.COLOR_BGR2RGB).astype(np.float32)
        normalized *= 1.0 / 255.0
        normalized -= self.mean
        normalized /= self.std
        return np.ascontiguousarray(normalized.transpose(2, 0, 1)[None, ...])

    def _postprocess(self, output: np.ndarray, width: int, height: int) -> np.ndarray:
        prediction = np.squeeze(output).astype(np.float32, copy=False)
        if prediction.ndim != 2:
            raise RuntimeError(
                f"unexpected ONNX output shape {tuple(output.shape)} from {self.output_name}"
            )
        if not np.isfinite(prediction).all():
            raise RuntimeError("ONNX output contains non-finite values")
        if self.sigmoid_logits:
            np.clip(prediction, -60.0, 60.0, out=prediction)
            prediction = 1.0 / (1.0 + np.exp(-prediction))
        low = float(prediction.min())
        high = float(prediction.max())
        if high - low <= 1e-8:
            normalized = np.zeros_like(prediction, dtype=np.float32)
        else:
            normalized = prediction - low
            normalized *= 1.0 / (high - low)
        alpha = np.clip(normalized * 255.0, 0.0, 255.0).astype(np.uint8)
        return cv2.resize(alpha, (width, height), interpolation=cv2.INTER_LANCZOS4)

    def process(self, image_path: str, output_path: str, mask_path: str) -> dict[str, Any]:
        started = perf_counter()
        phases = PhaseTimings()
        with PeakRssSampler() as memory:
            with phases.measure("load_image_ms"):
                image = cv2.imread(image_path, cv2.IMREAD_COLOR)
                if image is None:
                    raise FileNotFoundError(f"cannot read image: {image_path}")
                height, width = image.shape[:2]

            with phases.measure("model_load_ms"):
                self._ensure_session()

            with phases.measure("preprocess_ms"):
                input_tensor = self._preprocess(image)

            with phases.measure("inference_ms"):
                assert self.session is not None
                assert self.input_name is not None
                assert self.output_name is not None
                output = self.session.run(
                    [self.output_name],
                    {self.input_name: input_tensor},
                )[0]

            with phases.measure("postprocess_ms"):
                alpha_mask = self._postprocess(output, width, height)
                mask_compactness = self.compute_mask_compactness(alpha_mask)

            with phases.measure("save_ms"):
                self.save_results(image, alpha_mask, output_path, mask_path)

        latency_ms = (perf_counter() - started) * 1000.0
        return self.success_result(
            latency_ms=latency_ms,
            peak_memory_mb=memory.peak_delta_mb,
            peak_rss_mb=memory.peak_rss_mb,
            baseline_rss_mb=memory.baseline_rss_mb,
            phase_timings_ms=phases.as_dict(),
            mask_compactness=mask_compactness,
            output_path=output_path,
            mask_path=mask_path,
            resolution=f"{width}x{height}",
        )
