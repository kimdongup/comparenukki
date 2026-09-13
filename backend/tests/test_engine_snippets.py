from __future__ import annotations

from pathlib import Path
import sys
import unittest


BACKEND_DIR = Path(__file__).resolve().parents[1]
if str(BACKEND_DIR) not in sys.path:
    sys.path.insert(0, str(BACKEND_DIR))

from engine_registry import ENGINE_SPECS, engine_ids, get_engine  # noqa: E402


class EngineSnippetTest(unittest.TestCase):
    def test_registry_metadata_matches_loaded_engines(self) -> None:
        for engine_id, spec in ENGINE_SPECS.items():
            with self.subTest(engine_id=engine_id):
                engine = get_engine(engine_id)
                self.assertEqual(engine.engine_id, engine_id)
                self.assertEqual(engine.name, spec.name)
                self.assertEqual(engine.framework, spec.framework)
                self.assertEqual(engine.description, spec.description)
                self.assertEqual(engine.backend_used, spec.backend_used)
                if engine_id not in {"grabcut", "watershed"}:
                    self.assertEqual(engine.model_version, spec.model_version)

    def test_every_engine_returns_valid_python(self) -> None:
        for engine_id in engine_ids():
            with self.subTest(engine_id=engine_id):
                compile(
                    get_engine(engine_id).get_code_snippet(),
                    f"<{engine_id}-snippet>",
                    "exec",
                )

    def test_onnx_engines_share_the_measured_runtime_path(self) -> None:
        expected_models = {
            "rembg_u2net": ("U2NET_MODEL_PATH", "u2net.onnx"),
            "isnet": ("ISNET_MODEL_PATH", "isnet-general-use.onnx"),
            "birefnet": ("BIREFNET_MODEL_PATH", "birefnet-general.onnx"),
            "rmbg": ("RMBG_MODEL_PATH", "bria_rmbg14.onnx"),
        }
        for engine_id, (environment_name, filename) in expected_models.items():
            with self.subTest(engine_id=engine_id):
                engine = get_engine(engine_id)
                config = engine.get_benchmark_config()
                snippet = engine.get_code_snippet()
                self.assertIn(environment_name, snippet)
                self.assertIn(filename, snippet)
                self.assertIn("import onnxruntime as ort", snippet)
                self.assertIn(
                    "session.run([output_name], {input_name: input_tensor})[0]",
                    snippet,
                )
                self.assertIn(f"input_size = {tuple(config['input_size'])!r}", snippet)
                self.assertIn(
                    f"sigmoid_logits = {config['sigmoid_logits']!r}",
                    snippet,
                )
                self.assertNotIn("from transformers", snippet)
                self.assertNotIn("from rembg", snippet)
                self.assertNotIn("import torch", snippet)

    def test_classic_and_optional_engine_parameters_match_configs(self) -> None:
        grabcut = get_engine("grabcut")
        grabcut_config = grabcut.get_benchmark_config()
        grabcut_snippet = grabcut.get_code_snippet()
        self.assertIn(
            f"width * {grabcut_config['margin_ratio']}",
            grabcut_snippet,
        )
        self.assertIn(
            f"    {grabcut_config['iterations']},",
            grabcut_snippet,
        )
        self.assertIn(
            f"medianBlur(alpha_mask, {grabcut_config['median_blur_kernel']})",
            grabcut_snippet,
        )

        watershed = get_engine("watershed")
        watershed_config = watershed.get_benchmark_config()
        watershed_snippet = watershed.get_code_snippet()
        self.assertIn("cv2.THRESH_OTSU", watershed_snippet)
        self.assertIn(
            f"iterations={watershed_config['opening_iterations']}",
            watershed_snippet,
        )
        self.assertIn(
            f"iterations={watershed_config['dilation_iterations']}",
            watershed_snippet,
        )
        self.assertIn("markers[unknown == 255] = 0", watershed_snippet)

        sam = get_engine("mobilesam")
        sam_snippet = sam.get_code_snippet()
        self.assertIn("MOBILESAM_CHECKPOINT", sam_snippet)
        self.assertIn("multimask_output=True", sam_snippet)
        self.assertIn("np.argmax(scores)", sam_snippet)

        inspyrenet = get_engine("inspyrenet")
        inspyrenet_snippet = inspyrenet.get_code_snippet()
        self.assertIn("INSPYRENET_CHECKPOINT", inspyrenet_snippet)
        self.assertIn("TRANSPARENT_BACKGROUND_FILE_PATH", inspyrenet_snippet)
        self.assertIn('resize="static"', inspyrenet_snippet)
        self.assertIn('type="map"', inspyrenet_snippet)
        self.assertIn('output_map.convert("L")', inspyrenet_snippet)


if __name__ == "__main__":
    unittest.main()
