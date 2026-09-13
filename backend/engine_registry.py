"""Lazy engine registry and shared request execution.

Engine objects are cached for the worker lifetime. Heavy model resources use a
bounded LRU (``NUKKI_MAX_RESIDENT_MODELS``, default 2) so warm sessions are reused
without keeping every ONNX/PyTorch model resident indefinitely.
"""

from __future__ import annotations

from collections import OrderedDict
from contextlib import contextmanager
from dataclasses import dataclass
import hashlib
import importlib
import json
import logging
import os
import tempfile
from typing import Any, Iterable, Iterator

try:
    from .engines.base_engine import (
        BaseNukkiEngine,
        EngineUnavailableError,
        build_engine_result,
    )
except ImportError:
    from engines.base_engine import (
        BaseNukkiEngine,
        EngineUnavailableError,
        build_engine_result,
    )


LOGGER = logging.getLogger(__name__)


@dataclass(frozen=True)
class EngineSpec:
    module: str
    class_name: str
    name: str
    framework: str
    description: str
    backend_used: str
    model_version: str


ENGINE_SPECS: dict[str, EngineSpec] = {
    "grabcut": EngineSpec(
        "grabcut_engine",
        "GrabCutEngine",
        "OpenCV GrabCut",
        "OpenCV (C++/Python)",
        "전통적 컴퓨터 비전의 GMM(Gaussian Mixture Models)과 Graph-Cut 에너지 최소화를 이용한 전경/배경 분할",
        "opencv.grabCut",
        "OpenCV runtime",
    ),
    "watershed": EngineSpec(
        "watershed_engine",
        "WatershedEngine",
        "OpenCV Watershed & Otsu",
        "OpenCV (C++/Python)",
        "LAB 색공간 변환, 조건부 임계값/Otsu 이진화 및 거리 변환(Distance Transform) 기반의 워터셰드 분할",
        "opencv.watershed",
        "OpenCV runtime",
    ),
    "rembg_u2net": EngineSpec(
        "rembg_engine",
        "RembgEngine",
        "U2-Net (rembg ONNX model)",
        "ONNX Runtime",
        "2단계 중첩 U-구조(Nested U-Structure)를 기반으로 전경 현저성(Salience)을 추출하는 대중적인 표준 오픈소스 모델",
        "onnxruntime",
        "u2net.onnx/rembg-release",
    ),
    "isnet": EngineSpec(
        "isnet_engine",
        "ISNetEngine",
        "DIS (IS-Net)",
        "ONNX Runtime",
        "초고해상도(1024x1024) 이분 분할(Dichotomous Image Segmentation) 네트워크로, 극도로 얇은 선과 복잡한 엣지 복원에 특화",
        "onnxruntime",
        "isnet-general-use.onnx/rembg-release",
    ),
    "birefnet": EngineSpec(
        "birefnet_engine",
        "BiRefNetEngine",
        "BiRefNet (ONNX)",
        "ONNX Runtime",
        "양방향 참조 네트워크(Bilateral Reference Network)를 통해 내부 구조와 외곽선 경계 가이던스를 동시에 최적화하는 최신 고성능 분할 모델",
        "onnxruntime",
        "birefnet-general.onnx/rembg-release",
    ),
    "rmbg": EngineSpec(
        "rmbg_engine",
        "RMBGEngine",
        "BRIA RMBG v1.4 (ONNX)",
        "ONNX Runtime",
        "이커머스 상품 사진, 스튜디오 제품 컷에 최적화되어 자연스러운 그림자 분리와 엣지 보존에 뛰어난 상용급 모델",
        "onnxruntime",
        "briaai/RMBG-1.4-onnx",
    ),
    "inspyrenet": EngineSpec(
        "inspyrenet_engine",
        "InSPyReNetEngine",
        "InSPyReNet",
        "PyTorch / Image Pyramid",
        "다해상도 이미지 피라미드 분할(Image-level Pyramid Split)을 통해 반투명 플라스틱, 유리창, 굴절 영역의 경계를 섬세하게 보존",
        "transparent_background.Remover",
        "InSPyReNet base/ckpt_base.pth",
    ),
    "mobilesam": EngineSpec(
        "sam_engine",
        "SAMEngine",
        "MobileSAM (ViT-T)",
        "PyTorch / MobileSAM",
        "Vision Transformer 기반 Zero-Shot 인스턴스 분할 모델로, 이미지 중심의 양성 포인트 프롬프트를 사용해 전경 마스크를 생성",
        "mobile_sam.SamPredictor",
        "MobileSAM vit_t/mobile_sam.pt",
    ),
}

_ENGINE_INSTANCES: dict[str, BaseNukkiEngine] = {}
_RESOURCE_LRU: OrderedDict[str, None] = OrderedDict()


def _model_cache_limit() -> int:
    raw_value = os.environ.get("NUKKI_MAX_RESIDENT_MODELS", "2")
    try:
        return max(0, int(raw_value))
    except ValueError:
        LOGGER.warning(
            "Invalid NUKKI_MAX_RESIDENT_MODELS=%r; using the default of 2",
            raw_value,
        )
        return 2


def engine_ids() -> list[str]:
    return list(ENGINE_SPECS)


@contextmanager
def snapshot_input(path: str) -> Iterator[tuple[str, str]]:
    """Yield an immutable request-local copy and the hash of those exact bytes."""
    source_path = os.path.abspath(path)
    source_name = os.path.basename(source_path) or "input"
    with tempfile.TemporaryDirectory(
        prefix="comparenukki-input-",
        ignore_cleanup_errors=True,
    ) as snapshot_dir:
        snapshot_path = os.path.join(snapshot_dir, source_name)
        digest = hashlib.sha256()
        try:
            with open(source_path, "rb") as source, open(snapshot_path, "xb") as target:
                for chunk in iter(lambda: source.read(1024 * 1024), b""):
                    digest.update(chunk)
                    target.write(chunk)
        except OSError as error:
            raise ValueError(f"could not snapshot input {source_path}: {error}") from error
        yield snapshot_path, digest.hexdigest()


def resolve_engine_ids(selection: Any) -> list[str]:
    if selection == "all":
        return engine_ids()
    selected = selection if isinstance(selection, list) else [selection]
    if not selected or not all(isinstance(value, str) for value in selected):
        raise ValueError("engine must be an engine id, a list of ids, or 'all'")
    unknown = [engine_id for engine_id in selected if engine_id not in ENGINE_SPECS]
    if unknown:
        raise ValueError(f"unknown engine id(s): {', '.join(unknown)}")
    return list(dict.fromkeys(selected))


def _module_name(short_name: str) -> str:
    package = __package__
    if package:
        return f"{package}.engines.{short_name}"
    return f"engines.{short_name}"


def get_engine(engine_id: str) -> BaseNukkiEngine:
    if engine_id in _ENGINE_INSTANCES:
        return _ENGINE_INSTANCES[engine_id]
    spec = ENGINE_SPECS[engine_id]
    module = importlib.import_module(_module_name(spec.module))
    engine_class = getattr(module, spec.class_name)
    engine = engine_class()
    _ENGINE_INSTANCES[engine_id] = engine
    return engine


def _evict_model_resources(
    max_resident: int,
    *,
    protected_engine_id: str | None = None,
) -> None:
    target = max(0, max_resident)
    while len(_RESOURCE_LRU) > target:
        evicted_id = next(
            (
                candidate
                for candidate in _RESOURCE_LRU
                if candidate != protected_engine_id
            ),
            None,
        )
        if evicted_id is None:
            return
        _RESOURCE_LRU.pop(evicted_id, None)
        evicted = _ENGINE_INSTANCES.get(evicted_id)
        if evicted is not None:
            LOGGER.info(
                "Releasing %s model resources (resident model cache limit=%d)",
                evicted_id,
                max_resident,
            )
            evicted.release_resources()


def _prepare_model_resources(engine: BaseNukkiEngine) -> None:
    """Reserve room before a model load so inference does not exceed the limit."""
    engine_id = engine.engine_id
    configured_limit = _model_cache_limit()

    if not engine.has_loaded_resources:
        _RESOURCE_LRU.pop(engine_id, None)

    if not engine.uses_model_resources:
        _evict_model_resources(configured_limit)
        return

    active_limit = max(1, configured_limit)
    if engine.has_loaded_resources:
        _RESOURCE_LRU.pop(engine_id, None)
        _RESOURCE_LRU[engine_id] = None
        _evict_model_resources(
            active_limit,
            protected_engine_id=engine_id,
        )
        return

    _evict_model_resources(active_limit - 1)


def _touch_model_resource(engine: BaseNukkiEngine) -> None:
    engine_id = engine.engine_id
    if not engine.uses_model_resources or not engine.has_loaded_resources:
        _RESOURCE_LRU.pop(engine_id, None)
        return
    _RESOURCE_LRU.pop(engine_id, None)
    _RESOURCE_LRU[engine_id] = None
    _evict_model_resources(_model_cache_limit())


def _cache_key(input_sha256: str | None, identity: dict[str, Any]) -> str | None:
    if input_sha256 is None:
        return None
    payload = {
        "schema": 2,
        "input_sha256": input_sha256,
        "engine": identity,
    }
    encoded = json.dumps(
        payload,
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
    ).encode("utf-8")
    return f"sha256:{hashlib.sha256(encoded).hexdigest()}"


def _generic_error_result(
    engine_id: str,
    *,
    status: str,
    error: str,
    input_sha256: str | None,
) -> dict[str, Any]:
    spec = ENGINE_SPECS[engine_id]
    identity = {
        "engine_id": engine_id,
        "backend_used": spec.backend_used,
        "model_version": spec.model_version,
        "model_sha256": None,
        "provider": "not-loaded",
        "config": {"pipeline_schema": 2},
    }
    return build_engine_result(
        engine_id=engine_id,
        name=spec.name,
        framework=spec.framework,
        description=spec.description,
        status=status,
        backend_used=spec.backend_used,
        model_version=spec.model_version,
        provider="not-loaded",
        error=error,
        benchmark_config=identity["config"],
        input_sha256=input_sha256,
        cache_key=_cache_key(input_sha256, identity),
    )


def execute_engine(
    engine_id: str,
    *,
    image_path: str,
    output_dir: str,
    input_sha256: str | None,
) -> dict[str, Any]:
    try:
        engine = get_engine(engine_id)
    except (EngineUnavailableError, ImportError) as error:
        return _generic_error_result(
            engine_id,
            status="unavailable",
            error=str(error),
            input_sha256=input_sha256,
        )
    except Exception as error:
        LOGGER.exception("Failed to initialize engine %s", engine_id)
        return _generic_error_result(
            engine_id,
            status="failed",
            error=str(error),
            input_sha256=input_sha256,
        )

    base_name = os.path.splitext(os.path.basename(image_path))[0] or "input"
    output_base = os.path.join(os.path.abspath(output_dir), base_name)
    output_path = os.path.join(output_base, f"{engine_id}_result.png")
    mask_path = os.path.join(output_base, f"{engine_id}_mask.png")

    _prepare_model_resources(engine)
    session_reused = engine.has_loaded_resources
    try:
        result = engine.process(image_path, output_path, mask_path)
    except EngineUnavailableError as error:
        result = engine.error_result(status="unavailable", error=str(error))
    except Exception as error:
        LOGGER.exception("Engine %s failed", engine_id)
        result = engine.error_result(status="failed", error=str(error))

    identity = engine.cache_identity()
    result["session_reused"] = session_reused
    result["input_sha256"] = input_sha256
    result["cache_key"] = _cache_key(input_sha256, identity)
    _touch_model_resource(engine)
    return result


def completion_status(results: Iterable[dict[str, Any]]) -> str:
    statuses = [result.get("status") for result in results]
    if not statuses:
        return "failed"
    usable = sum(status == "success" for status in statuses)
    if usable == len(statuses):
        return "success"
    if usable:
        return "partial"
    return "failed"
