from __future__ import annotations

from collections import OrderedDict
import hashlib
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch


BACKEND_DIR = Path(__file__).resolve().parents[1]
if str(BACKEND_DIR) not in sys.path:
    sys.path.insert(0, str(BACKEND_DIR))

import engine_registry  # noqa: E402
from engines.base_engine import build_engine_result  # noqa: E402


class _FakeHeavyEngine:
    uses_model_resources = True

    def __init__(self, engine_id: str, *, loaded: bool) -> None:
        self.engine_id = engine_id
        self.loaded = loaded
        self.release_count = 0

    @property
    def has_loaded_resources(self) -> bool:
        return self.loaded

    def release_resources(self) -> None:
        self.loaded = False
        self.release_count += 1


class EngineRegistryTest(unittest.TestCase):
    def setUp(self) -> None:
        self._instances = engine_registry._ENGINE_INSTANCES.copy()
        self._lru = OrderedDict(engine_registry._RESOURCE_LRU)
        engine_registry._ENGINE_INSTANCES.clear()
        engine_registry._RESOURCE_LRU.clear()

    def tearDown(self) -> None:
        engine_registry._ENGINE_INSTANCES.clear()
        engine_registry._ENGINE_INSTANCES.update(self._instances)
        engine_registry._RESOURCE_LRU.clear()
        engine_registry._RESOURCE_LRU.update(self._lru)

    def test_model_slot_is_evicted_before_a_new_heavy_model_load(self) -> None:
        oldest = _FakeHeavyEngine("oldest", loaded=True)
        recent = _FakeHeavyEngine("recent", loaded=True)
        incoming = _FakeHeavyEngine("incoming", loaded=False)
        engine_registry._ENGINE_INSTANCES.update(
            oldest=oldest,
            recent=recent,
            incoming=incoming,
        )
        engine_registry._RESOURCE_LRU.update(oldest=None, recent=None)

        with patch.dict(os.environ, {"NUKKI_MAX_RESIDENT_MODELS": "2"}):
            engine_registry._prepare_model_resources(incoming)
            self.assertEqual(list(engine_registry._RESOURCE_LRU), ["recent"])
            self.assertEqual(oldest.release_count, 1)

            incoming.loaded = True
            engine_registry._touch_model_resource(incoming)

        self.assertEqual(
            list(engine_registry._RESOURCE_LRU),
            ["recent", "incoming"],
        )

    def test_zero_cache_limit_releases_the_current_model_after_use(self) -> None:
        engine = _FakeHeavyEngine("current", loaded=True)
        engine_registry._ENGINE_INSTANCES[engine.engine_id] = engine
        engine_registry._RESOURCE_LRU[engine.engine_id] = None

        with patch.dict(os.environ, {"NUKKI_MAX_RESIDENT_MODELS": "0"}):
            engine_registry._touch_model_resource(engine)

        self.assertFalse(engine.loaded)
        self.assertEqual(engine.release_count, 1)
        self.assertFalse(engine_registry._RESOURCE_LRU)

    def test_snapshot_hash_matches_the_exact_bytes_seen_by_engines(self) -> None:
        payload = b"same bytes for every engine\x00\xff"
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory, "input.bin")
            source.write_bytes(payload)

            with engine_registry.snapshot_input(str(source)) as (
                snapshot_path,
                input_sha256,
            ):
                snapshot = Path(snapshot_path)
                self.assertNotEqual(snapshot, source)
                self.assertEqual(snapshot.read_bytes(), payload)
                self.assertEqual(input_sha256, hashlib.sha256(payload).hexdigest())

            self.assertFalse(snapshot.exists())

    def test_result_schema_rejects_removed_status_and_legacy_metric(self) -> None:
        result = build_engine_result(
            engine_id="engine",
            name="Engine",
            framework="test",
            description="test",
            status="success",
            backend_used="test",
            model_version="1",
            provider="CPU",
        )
        self.assertNotIn("edge_smoothness_score", result)
        with self.assertRaises(ValueError):
            build_engine_result(
                engine_id="engine",
                name="Engine",
                framework="test",
                description="test",
                status="degraded",
                backend_used="test",
                model_version="1",
                provider="CPU",
            )

    def test_only_success_is_usable_for_request_completion(self) -> None:
        self.assertEqual(
            engine_registry.completion_status([{"status": "unavailable"}]),
            "failed",
        )
        self.assertEqual(
            engine_registry.completion_status(
                [{"status": "success"}, {"status": "failed"}],
            ),
            "partial",
        )


if __name__ == "__main__":
    unittest.main()
