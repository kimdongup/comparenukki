import os
from importlib import metadata
from time import perf_counter

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
    from .hardware_utils import clear_torch_device_cache, get_optimal_torch_device
except ImportError:
    from hardware_utils import clear_torch_device_cache, get_optimal_torch_device


class SAMEngine(BaseNukkiEngine):
    def __init__(self):
        self.device = os.environ.get("MOBILESAM_DEVICE") or get_optimal_torch_device()
        model_dir = os.path.expanduser(os.environ.get("NUKKI_MODEL_DIR", "~/.u2net"))
        self.checkpoint_path = os.path.abspath(
            os.path.expanduser(
                os.environ.get(
                    "MOBILESAM_CHECKPOINT", os.path.join(model_dir, "mobile_sam.pt")
                )
            )
        )
        super().__init__(
            engine_id="mobilesam",
            name="MobileSAM (ViT-T)",
            framework="PyTorch / MobileSAM",
            description="Vision Transformer 기반 Zero-Shot 인스턴스 분할 모델로, 이미지 중심의 양성 포인트 프롬프트를 사용해 전경 마스크를 생성",
            backend_used="mobile_sam.SamPredictor",
            model_version="MobileSAM vit_t/mobile_sam.pt",
            provider=f"PyTorch {self.device}",
        )
        self.predictor = None

    @property
    def has_loaded_resources(self) -> bool:
        return self.predictor is not None

    @property
    def uses_model_resources(self) -> bool:
        return True

    def release_resources(self) -> None:
        self.predictor = None
        clear_torch_device_cache()
        super().release_resources()

    def _ensure_predictor(self) -> None:
        if self.predictor is not None:
            return
        if not os.path.isfile(self.checkpoint_path):
            raise EngineUnavailableError(
                "MobileSAM checkpoint is not installed; set MOBILESAM_CHECKPOINT "
                f"to mobile_sam.pt (looked at {self.checkpoint_path})"
            )
        try:
            from mobile_sam import SamPredictor, sam_model_registry
        except ImportError as error:
            raise EngineUnavailableError("mobile-sam is not installed") from error
        try:
            import torch
        except ImportError as error:
            raise EngineUnavailableError("PyTorch is not installed") from error
        if self.device.startswith("cuda") and not torch.cuda.is_available():
            raise EngineUnavailableError("MOBILESAM_DEVICE requests CUDA, but CUDA is unavailable")
        if self.device.startswith("mps") and not torch.backends.mps.is_available():
            raise EngineUnavailableError("MOBILESAM_DEVICE requests MPS, but MPS is unavailable")

        model = sam_model_registry["vit_t"](checkpoint=self.checkpoint_path)
        model.to(device=self.device)
        model.eval()
        predictor = SamPredictor(model)
        model_sha256 = sha256_file(self.checkpoint_path)
        try:
            package_version = metadata.version("mobile-sam")
        except metadata.PackageNotFoundError:
            package_version = "unknown"
        model_version = (
            f"MobileSAM vit_t/mobile-sam-{package_version}"
            f"@sha256:{model_sha256[:12]}"
        )

        # Publish the predictor only after its reproducibility metadata is complete.
        self.predictor = predictor
        self.model_sha256 = model_sha256
        self.model_version = model_version

    def get_benchmark_config(self) -> dict:
        return {
            "pipeline_schema": 2,
            "model_type": "vit_t",
            "prompt": "single-positive-center-point",
            "multimask_output": True,
            "selection": "highest-model-score",
            "device": self.device,
        }

    def process(self, image_path: str, output_path: str, mask_path: str) -> dict:
        started = perf_counter()
        phases = PhaseTimings()
        with PeakRssSampler() as memory:
            with phases.measure("load_image_ms"):
                image = cv2.imread(image_path, cv2.IMREAD_COLOR)
                if image is None:
                    raise FileNotFoundError(f"cannot read image: {image_path}")
                height, width = image.shape[:2]

            with phases.measure("model_load_ms"):
                self._ensure_predictor()

            with phases.measure("preprocess_ms"):
                image_rgb = cv2.cvtColor(image, cv2.COLOR_BGR2RGB)
                input_points = np.asarray([[width // 2, height // 2]], dtype=np.float32)
                input_labels = np.asarray([1], dtype=np.int32)

            with phases.measure("inference_ms"):
                self.predictor.set_image(image_rgb)
                masks, scores, _ = self.predictor.predict(
                    point_coords=input_points,
                    point_labels=input_labels,
                    multimask_output=True,
                )

            with phases.measure("postprocess_ms"):
                if len(masks) == 0 or len(scores) == 0:
                    raise RuntimeError("MobileSAM returned no masks")
                selected_index = int(np.argmax(scores))
                alpha_mask = np.asarray(masks[selected_index], dtype=np.uint8) * 255
                compactness = self.compute_mask_compactness(alpha_mask)
                selected_score = float(scores[selected_index])

            with phases.measure("save_ms"):
                self.save_results(image, alpha_mask, output_path, mask_path)

        latency_ms = (perf_counter() - started) * 1000.0
        result = self.success_result(
            latency_ms=latency_ms,
            peak_memory_mb=memory.peak_delta_mb,
            peak_rss_mb=memory.peak_rss_mb,
            baseline_rss_mb=memory.baseline_rss_mb,
            phase_timings_ms=phases.as_dict(),
            mask_compactness=compactness,
            output_path=output_path,
            mask_path=mask_path,
            resolution=f"{width}x{height}",
        )
        result["diagnostics"]["model_mask_confidence"] = round(selected_score, 4)
        return result

    def get_code_snippet(self) -> str:
        return '''import hashlib
import os
from importlib import metadata

import cv2
import numpy as np

device = os.environ.get("MOBILESAM_DEVICE", "cpu")
model_dir = os.path.expanduser(os.environ.get("NUKKI_MODEL_DIR", "~/.u2net"))
checkpoint_path = os.path.abspath(os.path.expanduser(os.environ.get(
    "MOBILESAM_CHECKPOINT", os.path.join(model_dir, "mobile_sam.pt")
)))
if not os.path.isfile(checkpoint_path):
    raise FileNotFoundError(
        "MobileSAM checkpoint is not installed; set MOBILESAM_CHECKPOINT "
        f"to mobile_sam.pt (looked at {checkpoint_path})"
    )

try:
    from mobile_sam import SamPredictor, sam_model_registry
except ImportError as error:
    raise RuntimeError("mobile-sam is not installed") from error
try:
    import torch
except ImportError as error:
    raise RuntimeError("PyTorch is not installed") from error
if device.startswith("cuda") and not torch.cuda.is_available():
    raise RuntimeError("MOBILESAM_DEVICE requests CUDA, but CUDA is unavailable")
if device.startswith("mps") and not torch.backends.mps.is_available():
    raise RuntimeError("MOBILESAM_DEVICE requests MPS, but MPS is unavailable")

model = sam_model_registry["vit_t"](checkpoint=checkpoint_path)
model.to(device=device)
model.eval()
predictor = SamPredictor(model)

digest = hashlib.sha256()
with open(checkpoint_path, "rb") as checkpoint:
    for chunk in iter(lambda: checkpoint.read(1024 * 1024), b""):
        digest.update(chunk)
model_sha256 = digest.hexdigest()
try:
    package_version = metadata.version("mobile-sam")
except metadata.PackageNotFoundError:
    package_version = "unknown"
model_version = (
    f"MobileSAM vit_t/mobile-sam-{package_version}"
    f"@sha256:{model_sha256[:12]}"
)

image = cv2.imread("input.jpg", cv2.IMREAD_COLOR)
if image is None:
    raise FileNotFoundError("cannot read image: input.jpg")
height, width = image.shape[:2]
image_rgb = cv2.cvtColor(image, cv2.COLOR_BGR2RGB)
input_points = np.asarray([[width // 2, height // 2]], dtype=np.float32)
input_labels = np.asarray([1], dtype=np.int32)

predictor.set_image(image_rgb)
masks, scores, _ = predictor.predict(
    point_coords=input_points,
    point_labels=input_labels,
    multimask_output=True,
)
if len(masks) == 0 or len(scores) == 0:
    raise RuntimeError("MobileSAM returned no masks")
selected_index = int(np.argmax(scores))
alpha_mask = np.asarray(masks[selected_index], dtype=np.uint8) * 255
selected_score = float(scores[selected_index])

contours, _ = cv2.findContours(
    alpha_mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_NONE
)
if not contours:
    mask_compactness = 0.0
else:
    total_points = sum(len(contour) for contour in contours)
    total_area = cv2.countNonZero(alpha_mask)
    if total_points == 0 or total_area == 0:
        mask_compactness = 0.0
    else:
        compactness = (total_area / (total_points**2 + 1e-5)) * 12.56
        mask_compactness = round(float(min(1.0, max(0.0, compactness))), 4)

rgba = np.empty((*image.shape[:2], 4), dtype=np.uint8)
rgba[:, :, :3] = image
rgba[:, :, 3] = alpha_mask
output_path = os.path.abspath("output_mobilesam.png")
mask_path = os.path.abspath("mask_mobilesam.png")
if not cv2.imwrite(output_path, rgba):
    raise OSError(f"failed to write output image: {output_path}")
if not cv2.imwrite(mask_path, alpha_mask):
    raise OSError(f"failed to write alpha mask: {mask_path}")

print({
    "model_version": model_version,
    "mask_compactness": mask_compactness,
    "model_mask_confidence": round(selected_score, 4),
})
'''
