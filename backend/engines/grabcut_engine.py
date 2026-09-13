from time import perf_counter

import cv2
import numpy as np
from .base_engine import BaseNukkiEngine, PeakRssSampler, PhaseTimings


class GrabCutEngine(BaseNukkiEngine):
    def __init__(self):
        super().__init__(
            engine_id="grabcut",
            name="OpenCV GrabCut",
            framework="OpenCV (C++/Python)",
            description="전통적 컴퓨터 비전의 GMM(Gaussian Mixture Models)과 Graph-Cut 에너지 최소화를 이용한 전경/배경 분할",
            backend_used="opencv.grabCut",
            model_version=f"OpenCV {cv2.__version__}",
            provider="CPU",
        )

    def process(self, image_path: str, output_path: str, mask_path: str) -> dict:
        started = perf_counter()
        phases = PhaseTimings()
        with PeakRssSampler() as memory:
            with phases.measure("load_image_ms"):
                image = cv2.imread(image_path, cv2.IMREAD_COLOR)
                if image is None:
                    raise FileNotFoundError(f"cannot read image: {image_path}")
                height, width = image.shape[:2]
                if width < 3 or height < 3:
                    raise ValueError("GrabCut requires an image of at least 3x3 pixels")

            with phases.measure("preprocess_ms"):
                margin_x = max(1, int(width * 0.04))
                margin_y = max(1, int(height * 0.04))
                rectangle = (
                    margin_x,
                    margin_y,
                    width - 2 * margin_x,
                    height - 2 * margin_y,
                )
                if rectangle[2] <= 0 or rectangle[3] <= 0:
                    raise ValueError("image is too small for the configured GrabCut margin")
                mask = np.zeros((height, width), np.uint8)
                background_model = np.zeros((1, 65), np.float64)
                foreground_model = np.zeros((1, 65), np.float64)

            with phases.measure("inference_ms"):
                cv2.grabCut(
                    image,
                    mask,
                    rectangle,
                    background_model,
                    foreground_model,
                    5,
                    cv2.GC_INIT_WITH_RECT,
                )

            with phases.measure("postprocess_ms"):
                alpha_mask = np.where(
                    (mask == cv2.GC_FGD) | (mask == cv2.GC_PR_FGD), 255, 0
                ).astype(np.uint8)
                alpha_mask = cv2.medianBlur(alpha_mask, 3)
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

    def get_benchmark_config(self) -> dict:
        return {
            "pipeline_schema": 2,
            "iterations": 5,
            "margin_ratio": 0.04,
            "median_blur_kernel": 3,
        }

    def get_code_snippet(self) -> str:
        return '''import os

import cv2
import numpy as np

image = cv2.imread("input.jpg", cv2.IMREAD_COLOR)
if image is None:
    raise FileNotFoundError("cannot read image: input.jpg")
height, width = image.shape[:2]
if width < 3 or height < 3:
    raise ValueError("GrabCut requires an image of at least 3x3 pixels")

margin_x = max(1, int(width * 0.04))
margin_y = max(1, int(height * 0.04))
rectangle = (
    margin_x,
    margin_y,
    width - 2 * margin_x,
    height - 2 * margin_y,
)
if rectangle[2] <= 0 or rectangle[3] <= 0:
    raise ValueError("image is too small for the configured GrabCut margin")
mask = np.zeros((height, width), np.uint8)
background_model = np.zeros((1, 65), np.float64)
foreground_model = np.zeros((1, 65), np.float64)

cv2.grabCut(
    image,
    mask,
    rectangle,
    background_model,
    foreground_model,
    5,
    cv2.GC_INIT_WITH_RECT,
)

alpha_mask = np.where(
    (mask == cv2.GC_FGD) | (mask == cv2.GC_PR_FGD), 255, 0
).astype(np.uint8)
alpha_mask = cv2.medianBlur(alpha_mask, 3)

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
output_path = os.path.abspath("output_grabcut.png")
mask_path = os.path.abspath("mask_grabcut.png")
if not cv2.imwrite(output_path, rgba):
    raise OSError(f"failed to write output image: {output_path}")
if not cv2.imwrite(mask_path, alpha_mask):
    raise OSError(f"failed to write alpha mask: {mask_path}")

print({"mask_compactness": mask_compactness})
'''
