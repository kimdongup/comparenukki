import cv2
from .onnx_engine import OnnxSegmentationEngine


class RMBGEngine(OnnxSegmentationEngine):
    def __init__(self):
        super().__init__(
            engine_id="rmbg",
            name="BRIA RMBG v1.4 (ONNX)",
            framework="ONNX Runtime",
            description="이커머스 상품 사진, 스튜디오 제품 컷에 최적화되어 자연스러운 그림자 분리와 엣지 보존에 뛰어난 상용급 모델",
            model_env_var="RMBG_MODEL_PATH",
            model_filename="bria_rmbg14.onnx",
            model_id="briaai/RMBG-1.4-onnx",
            input_size=(1024, 1024),
            mean=(0.5, 0.5, 0.5),
            std=(1.0, 1.0, 1.0),
            interpolation=cv2.INTER_LANCZOS4,
            sigmoid_logits=False,
        )
