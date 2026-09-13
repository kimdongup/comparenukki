import cv2
from .onnx_engine import OnnxSegmentationEngine


class BiRefNetEngine(OnnxSegmentationEngine):
    def __init__(self):
        super().__init__(
            engine_id="birefnet",
            name="BiRefNet (ONNX)",
            framework="ONNX Runtime",
            description="양방향 참조 네트워크(Bilateral Reference Network)를 통해 내부 구조와 외곽선 경계 가이던스를 동시에 최적화하는 최신 고성능 분할 모델",
            model_env_var="BIREFNET_MODEL_PATH",
            model_filename="birefnet-general.onnx",
            model_id="birefnet-general.onnx/rembg-release",
            input_size=(1024, 1024),
            mean=(0.485, 0.456, 0.406),
            std=(0.229, 0.224, 0.225),
            interpolation=cv2.INTER_LANCZOS4,
            sigmoid_logits=True,
        )
