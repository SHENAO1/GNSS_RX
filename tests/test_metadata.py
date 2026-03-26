"""采集元数据测试。"""

import json
import tempfile
import unittest
from pathlib import Path

from gnss_rx.metadata import build_capture_metadata, write_metadata_json
from gnss_rx.runtime import RxRuntimeConfig


class TestMetadata(unittest.TestCase):
    def test_metadata_contains_matlab_handoff_fields(self) -> None:
        config = RxRuntimeConfig(bandwidth_hz=4.092e6)
        metadata = build_capture_metadata(config=config, samples_captured=8192, data_path=Path("demo.sc16"))

        self.assertEqual(metadata.sample_format, "sc16")
        self.assertEqual(metadata.complex_layout, "iq_int16_interleaved_le")
        self.assertEqual(metadata.samples_captured, 8192)
        self.assertEqual(metadata.prn_id, 1)

    def test_write_metadata_json_serializes_expected_keys(self) -> None:
        config = RxRuntimeConfig(bandwidth_hz=4.092e6)
        metadata = build_capture_metadata(config=config, samples_captured=2048, data_path=Path("demo.sc16"))

        with tempfile.TemporaryDirectory() as tmpdir:
            path = Path(tmpdir) / "demo.json"
            write_metadata_json(path, metadata)
            parsed = json.loads(path.read_text(encoding="utf-8"))

        self.assertEqual(parsed["sample_format"], "sc16")
        self.assertEqual(parsed["data_file"], "demo.sc16")
        self.assertEqual(parsed["signal_mode"], "spread")

    def test_metadata_preserves_selected_prn(self) -> None:
        config = RxRuntimeConfig(bandwidth_hz=4.092e6, prn_id=7)
        metadata = build_capture_metadata(config=config, samples_captured=2048, data_path=Path("demo.sc16"))
        self.assertEqual(metadata.prn_id, 7)

    def test_single_prn_metadata_has_all_prns_false_and_no_prn_ids(self) -> None:
        config = RxRuntimeConfig(bandwidth_hz=4.092e6, prn_id=5)
        metadata = build_capture_metadata(config=config, samples_captured=2048, data_path=Path("demo.sc16"))
        self.assertFalse(metadata.all_prns)
        self.assertIsNone(metadata.prn_ids)

    def test_all_prns_metadata_sets_all_prns_flag_and_prn_ids_list(self) -> None:
        config = RxRuntimeConfig(bandwidth_hz=4.092e6, all_prns=True)
        metadata = build_capture_metadata(config=config, samples_captured=2048, data_path=Path("demo.sc16"))
        self.assertTrue(metadata.all_prns)
        self.assertEqual(metadata.prn_ids, list(range(1, 33)))

    def test_all_prns_metadata_serializes_prn_ids_to_json(self) -> None:
        config = RxRuntimeConfig(bandwidth_hz=4.092e6, all_prns=True)
        metadata = build_capture_metadata(config=config, samples_captured=2048, data_path=Path("demo.sc16"))
        with tempfile.TemporaryDirectory() as tmpdir:
            path = Path(tmpdir) / "demo.json"
            write_metadata_json(path, metadata)
            parsed = json.loads(path.read_text(encoding="utf-8"))
        self.assertTrue(parsed["all_prns"])
        self.assertEqual(parsed["prn_ids"], list(range(1, 33)))


if __name__ == "__main__":
    unittest.main()
