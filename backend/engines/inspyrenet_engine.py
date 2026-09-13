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


class InSPyReNetEngine(BaseNukkiEngine):
    def __init__(self):
        self.device = os.environ.get("INSPYRENET_DEVICE") or get_optimal_torch_device()
        super().__init__(
            engine_id="inspyrenet",
            name="InSPyReNet",
            framework="PyTorch / Image Pyramid",
            description="다해상도 이미지 피라미드 분할(Image-level Pyramid Split)을 통해 반투명 플라스틱, 유리창, 굴절 영역의 경계를 섬세하게 보존",
            backend_used="transparent_background.Remover",
            model_version="InSPyReNet base/ckpt_base.pth",
            provider=f"PyTorch {self.device}",
        )
        self.checkpoint_path = self._checkpoint_candidate()
        self.remover = None

    @property
    def has_loaded_resources(self) -> bool:
        return self.remover is not None

    @property
    def uses_model_resources(self) -> bool:
        return True

    def release_resources(self) -> None:
        self.remover = None
        clear_torch_device_cache()
        super().release_resources()

    @staticmethod
    def _checkpoint_candidate() -> str:
        explicit = os.environ.get("INSPYRENET_CHECKPOINT")
        if explicit:
            return os.path.abspath(os.path.expanduser(explicit))
        config_location = os.environ.get("TRANSPARENT_BACKGROUND_FILE_PATH")
        if config_location:
            expanded = os.path.abspath(os.path.expanduser(config_location))
            config_dir = expanded if os.path.isdir(expanded) else os.path.dirname(expanded)
            candidate = os.path.join(config_dir, "ckpt_base.pth")
            if os.path.isfile(candidate):
                return candidate
        return os.path.expanduser("~/.transparent-background/ckpt_base.pth")

    def _ensure_remover(self) -> None:
        if self.remover is not None:
            return
        if not os.path.isfile(self.checkpoint_path):
            raise EngineUnavailableError(
                "InSPyReNet checkpoint is not installed; set INSPYRENET_CHECKPOINT "
                f"to ckpt_base.pth (looked at {self.checkpoint_path})"
            )
        try:
            from transparent_background import Remover
        except ImportError as error:
            raise EngineUnavailableError(
                "transparent-background is not installed; install it to run InSPyReNet"
            ) from error

        remover = Remover(
            mode="base",
            device=self.device,
            ckpt=self.checkpoint_path,
            resize="static",
        )
        model_sha256 = sha256_file(self.checkpoint_path)
        try:
            package_version = metadata.version("transparent-background")
        except metadata.PackageNotFoundError:
            package_version = "unknown"
        model_version = (
            f"InSPyReNet base/transparent-background-{package_version}"
            f"@sha256:{model_sha256[:12]}"
        )

        # Publish a usable remover only after its reproducibility metadata exists.
        self.remover = remover
        self.model_sha256 = model_sha256
        self.model_version = model_version

    def get_benchmark_config(self) -> dict:
        return {
            "pipeline_schema": 2,
            "mode": "base",
            "resize": "static",
            "output_type": "map",
            "device": self.device,
        }

    def process(self, image_path: str, output_path: str, mask_path: str) -> dict:
        from PIL import Image

        started = perf_counter()
        phases = PhaseTimings()
        with PeakRssSampler() as memory:
            with phases.measure("load_image_ms"):
                image = cv2.imread(image_path, cv2.IMREAD_COLOR)
                if image is None:
                    raise FileNotFoundError(f"cannot read image: {image_path}")
                height, width = image.shape[:2]

            with phases.measure("model_load_ms"):
                self._ensure_remover()

            with phases.measure("preprocess_ms"):
                pil_image = Image.fromarray(cv2.cvtColor(image, cv2.COLOR_BGR2RGB))

            with phases.measure("inference_ms"):
                output_map = self.remover.process(pil_image, type="map")

            with phases.measure("postprocess_ms"):
                alpha_mask = np.asarray(output_map.convert("L"), dtype=np.uint8)
                if alpha_mask.shape != (height, width):
                    alpha_mask = cv2.resize(
                        alpha_mask, (width, height), interpolation=cv2.INTER_LANCZOS4
                    )
                compactness = self.compute_mask_compactness(alpha_mask)

            with phases.measure("save_ms"):
                self.save_results(image, alpha_mask, output_path, mask_path)

        latency_ms = (perf_counter() - started) * 1000.0
        return self.success_result(
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

    def get_code_snippet(self) -> str:
        return '''import hashlib
import os
from importlib import metadata

import cv2
import numpy as np
from PIL import Image


def checkpoint_candidate():
    explicit = os.environ.get("INSPYRENET_CHECKPOINT")
    if explicit:
        return os.path.abspath(os.path.expanduser(explicit))
    config_location = os.environ.get("TRANSPARENT_BACKGROUND_FILE_PATH")
    if config_location:
        expanded = os.path.abspath(os.path.expanduser(config_location))
        config_dir = expanded if os.path.isdir(expanded) else os.path.dirname(expanded)
        candidate = os.path.join(config_dir, "ckpt_base.pth")
        if os.path.isfile(candidate):
            return candidate
    return os.path.expanduser("~/.transparent-background/ckpt_base.pth")


device = os.environ.get("INSPYRENET_DEVICE", "cpu")
checkpoint_path = checkpoint_candidate()
if not os.path.isfile(checkpoint_path):
    raise FileNotFoundError(
        "InSPyReNet checkpoint is not installed; set INSPYRENET_CHECKPOINT "
        f"to ckpt_base.pth (looked at {checkpoint_path})"
    )
try:
    from transparent_background import Remover
except ImportError as error:
    raise RuntimeError(
        "transparent-background is not installed; install it to run InSPyReNet"
    ) from error

remover = Remover(
    mode="base",
    device=device,
    ckpt=checkpoint_path,
    resize="static",
)
digest = hashlib.sha256()
with open(checkpoint_path, "rb") as checkpoint:
    for chunk in iter(lambda: checkpoint.read(1024 * 1024), b""):
        digest.update(chunk)
model_sha256 = digest.hexdigest()
try:
    package_version = metadata.version("transparent-background")
except metadata.PackageNotFoundError:
    package_version = "unknown"
model_version = (
    f"InSPyReNet base/transparent-background-{package_version}"
    f"@sha256:{model_sha256[:12]}"
)

image = cv2.imread("input.jpg", cv2.IMREAD_COLOR)
if image is None:
    raise FileNotFoundError("cannot read image: input.jpg")
height, width = image.shape[:2]
pil_image = Image.fromarray(cv2.cvtColor(image, cv2.COLOR_BGR2RGB))
output_map = remover.process(pil_image, type="map")
alpha_mask = np.asarray(output_map.convert("L"), dtype=np.uint8)
if alpha_mask.shape != (height, width):
    alpha_mask = cv2.resize(
        alpha_mask, (width, height), interpolation=cv2.INTER_LANCZOS4
    )

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
output_path = os.path.abspath("output_inspyrenet.png")
mask_path = os.path.abspath("mask_inspyrenet.png")
if not cv2.imwrite(output_path, rgba):
    raise OSError(f"failed to write output image: {output_path}")
if not cv2.imwrite(mask_path, alpha_mask):
    raise OSError(f"failed to write alpha mask: {mask_path}")

print({
    "model_version": model_version,
    "mask_compactness": mask_compactness,
})
'''
