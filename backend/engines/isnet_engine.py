import cv2
from .onnx_engine import OnnxSegmentationEngine


class ISNetEngine(OnnxSegmentationEngine):
    def __init__(self):
        super().__init__(
            engine_id="isnet",
            name="DIS (IS-Net)",
            framework="ONNX Runtime",
            description="초고해상도(1024x1024) 이분 분할(Dichotomous Image Segmentation) 네트워크로, 극도로 얇은 선과 복잡한 엣지 복원에 특화",
            model_env_var="ISNET_MODEL_PATH",
            model_filename="isnet-general-use.onnx",
            model_id="isnet-general-use.onnx/rembg-release",
            input_size=(1024, 1024),
            mean=(0.5, 0.5, 0.5),
            std=(1.0, 1.0, 1.0),
            interpolation=cv2.INTER_LANCZOS4,
            sigmoid_logits=False,
        )
