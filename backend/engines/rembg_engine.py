import cv2
from .onnx_engine import OnnxSegmentationEngine


class RembgEngine(OnnxSegmentationEngine):
    def __init__(self):
        super().__init__(
            engine_id="rembg_u2net",
            name="U2-Net (rembg ONNX model)",
            framework="ONNX Runtime",
            description="2단계 중첩 U-구조(Nested U-Structure)를 기반으로 전경 현저성(Salience)을 추출하는 대중적인 표준 오픈소스 모델",
            model_env_var="U2NET_MODEL_PATH",
            model_filename="u2net.onnx",
            model_id="u2net.onnx/rembg-release",
            input_size=(320, 320),
            mean=(0.485, 0.456, 0.406),
            std=(0.229, 0.224, 0.225),
            interpolation=cv2.INTER_AREA,
            sigmoid_logits=False,
        )
