from time import perf_counter

import cv2
import numpy as np
from .base_engine import BaseNukkiEngine, PeakRssSampler, PhaseTimings


class WatershedEngine(BaseNukkiEngine):
    def __init__(self):
        super().__init__(
            engine_id="watershed",
            name="OpenCV Watershed & Otsu",
            framework="OpenCV (C++/Python)",
            description="LAB 색공간 변환, 조건부 임계값/Otsu 이진화 및 거리 변환(Distance Transform) 기반의 워터셰드 분할",
            backend_used="opencv.watershed",
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

            with phases.measure("preprocess_ms"):
                lab = cv2.cvtColor(image, cv2.COLOR_BGR2LAB)
                luminance = lab[:, :, 0]
                border_pixels = np.concatenate(
                    [luminance[0, :], luminance[-1, :], luminance[:, 0], luminance[:, -1]]
                )
                if float(np.mean(border_pixels)) > 127.0:
                    _, threshold = cv2.threshold(
                        luminance, 240, 255, cv2.THRESH_BINARY_INV
                    )
                else:
                    _, threshold = cv2.threshold(
                        luminance, 0, 255, cv2.THRESH_BINARY + cv2.THRESH_OTSU
                    )
                kernel = np.ones((3, 3), np.uint8)
                opening = cv2.morphologyEx(
                    threshold, cv2.MORPH_OPEN, kernel, iterations=2
                )
                sure_background = cv2.dilate(opening, kernel, iterations=3)
                distance = cv2.distanceTransform(opening, cv2.DIST_L2, 5)
                distance_max = float(distance.max())
                if distance_max > 0.0:
                    _, sure_foreground = cv2.threshold(
                        distance, 0.2 * distance_max, 255, 0
                    )
                    sure_foreground = sure_foreground.astype(np.uint8)
                else:
                    sure_foreground = np.zeros_like(opening)
                unknown = cv2.subtract(sure_background, sure_foreground)
                _, markers = cv2.connectedComponents(sure_foreground)
                markers += 1
                markers[unknown == 255] = 0

            with phases.measure("inference_ms"):
                markers = cv2.watershed(image, markers)

            with phases.measure("postprocess_ms"):
                alpha_mask = np.where(markers > 1, 255, 0).astype(np.uint8)
                alpha_mask = cv2.GaussianBlur(alpha_mask, (3, 3), 0)
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
            "light_background_threshold": 127.0,
            "fixed_luminance_threshold": 240,
            "distance_ratio": 0.2,
            "opening_iterations": 2,
            "dilation_iterations": 3,
        }

    def get_code_snippet(self) -> str:
        return '''import os

import cv2
import numpy as np

image = cv2.imread("input.jpg", cv2.IMREAD_COLOR)
if image is None:
    raise FileNotFoundError("cannot read image: input.jpg")
height, width = image.shape[:2]

lab = cv2.cvtColor(image, cv2.COLOR_BGR2LAB)
luminance = lab[:, :, 0]
border_pixels = np.concatenate(
    [luminance[0, :], luminance[-1, :], luminance[:, 0], luminance[:, -1]]
)
if float(np.mean(border_pixels)) > 127.0:
    _, threshold = cv2.threshold(
        luminance, 240, 255, cv2.THRESH_BINARY_INV
    )
else:
    _, threshold = cv2.threshold(
        luminance, 0, 255, cv2.THRESH_BINARY + cv2.THRESH_OTSU
    )

kernel = np.ones((3, 3), np.uint8)
opening = cv2.morphologyEx(
    threshold, cv2.MORPH_OPEN, kernel, iterations=2
)
sure_background = cv2.dilate(opening, kernel, iterations=3)
distance = cv2.distanceTransform(opening, cv2.DIST_L2, 5)
distance_max = float(distance.max())
if distance_max > 0.0:
    _, sure_foreground = cv2.threshold(
        distance, 0.2 * distance_max, 255, 0
    )
    sure_foreground = sure_foreground.astype(np.uint8)
else:
    sure_foreground = np.zeros_like(opening)
unknown = cv2.subtract(sure_background, sure_foreground)
_, markers = cv2.connectedComponents(sure_foreground)
markers += 1
markers[unknown == 255] = 0

markers = cv2.watershed(image, markers)
alpha_mask = np.where(markers > 1, 255, 0).astype(np.uint8)
alpha_mask = cv2.GaussianBlur(alpha_mask, (3, 3), 0)

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
output_path = os.path.abspath("output_watershed.png")
mask_path = os.path.abspath("mask_watershed.png")
if not cv2.imwrite(output_path, rgba):
    raise OSError(f"failed to write output image: {output_path}")
if not cv2.imwrite(mask_path, alpha_mask):
    raise OSError(f"failed to write alpha mask: {mask_path}")

print({"mask_compactness": mask_compactness})
'''
