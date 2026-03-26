"""GNSS_RX 运行时配置行为测试。"""

from datetime import datetime
import tempfile
import textwrap
import unittest
from pathlib import Path

from gnss_rx.runtime import (
    DEFAULT_OUTPUT_BASE_DIR,
    RxRuntimeConfig,
    SUPPORTED_PRN_MAX,
    SUPPORTED_PRN_MIN,
    apply_overrides,
    build_timestamped_capture_stem,
    load_rx_runtime_config,
    resolve_capture_paths,
)


class TestRxRuntimeConfig(unittest.TestCase):
    def test_capture_samples_round_from_duration(self) -> None:
        config = RxRuntimeConfig(sample_rate_hz=4.0, duration_s=2.5, bandwidth_hz=4.0)
        self.assertEqual(config.capture_samples, 10)

    def test_load_config_derives_bandwidth(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            path = Path(tmpdir) / "rx.yaml"
            path.write_text(
                textwrap.dedent(
                    """
                    usrp_addr: "type=b200"
                    center_freq_hz: 100000000.0
                    sample_rate_hz: 4092000.0
                    rx_gain_db: 18.0
                    antenna: "RX2"
                    duration_s: 2.0
                    output_base_dir: "/mnt/hgfs/GongXiangDocument/GNSS_RX_Data"
                    use_timestamped_stem: true
                    clock_source: "internal"
                    time_source: "internal"
                    signal_mode: "spread"
                    prn_id: 1
                    tx_profile_reference: "../gnss_tx/configs/tx_b210_visible_spectrum.yaml"
                    """
                ).strip(),
                encoding="utf-8",
            )

            config = load_rx_runtime_config(path)

        self.assertEqual(config.bandwidth_hz, 4092000.0)
        self.assertEqual(config.output_base_dir, DEFAULT_OUTPUT_BASE_DIR)
        self.assertTrue(config.use_timestamped_stem)

    def test_apply_overrides_updates_bandwidth_when_sample_rate_changes(self) -> None:
        config = RxRuntimeConfig(bandwidth_hz=4.092e6)
        updated = apply_overrides(config, sample_rate_hz=2.046e6)
        self.assertEqual(updated.sample_rate_hz, 2.046e6)
        self.assertEqual(updated.bandwidth_hz, 2.046e6)

    def test_build_timestamped_capture_stem_uses_required_labels(self) -> None:
        config = RxRuntimeConfig(bandwidth_hz=4.092e6)
        stem = build_timestamped_capture_stem(config, datetime(2026, 3, 23, 19, 5, 30))
        self.assertEqual(
            stem,
            "20260323_190530_rawiq_sc16_zeroif_prn1_spread_sr4092000_cf100000000_dur2p0s",
        )

    def test_resolve_capture_paths_uses_shared_folder_date_hierarchy(self) -> None:
        config = RxRuntimeConfig(bandwidth_hz=4.092e6)
        data_path, metadata_path = resolve_capture_paths(
            Path("/project"),
            config,
            when=datetime(2026, 3, 23, 19, 5, 30),
        )
        expected_stem = (
            "/mnt/hgfs/GongXiangDocument/GNSS_RX_Data/2026/2026_03_23/"
            "20260323_190530_rawiq_sc16_zeroif_prn1_spread_sr4092000_cf100000000_dur2p0s/"
            "20260323_190530_rawiq_sc16_zeroif_prn1_spread_sr4092000_cf100000000_dur2p0s"
        )
        self.assertEqual(str(data_path), f"{expected_stem}.sc16")
        self.assertEqual(str(metadata_path), f"{expected_stem}.json")

    def test_resolve_capture_paths_keeps_manual_output_stem_override(self) -> None:
        config = RxRuntimeConfig(bandwidth_hz=4.092e6, output_stem="results/captures/manual_capture")
        data_path, metadata_path = resolve_capture_paths(Path("/project"), config)
        self.assertEqual(str(data_path), "/project/results/captures/manual_capture.sc16")
        self.assertEqual(str(metadata_path), "/project/results/captures/manual_capture.json")

    def test_build_timestamped_capture_stem_tracks_selected_prn(self) -> None:
        config = RxRuntimeConfig(bandwidth_hz=4.092e6, prn_id=7)
        stem = build_timestamped_capture_stem(config, datetime(2026, 3, 23, 19, 5, 30))
        self.assertIn("_prn7_", stem)

    def test_prn_range_validation_rejects_values_outside_supported_range(self) -> None:
        with self.assertRaises(ValueError):
            RxRuntimeConfig(prn_id=SUPPORTED_PRN_MIN - 1, bandwidth_hz=4.092e6).validate()
        with self.assertRaises(ValueError):
            RxRuntimeConfig(prn_id=SUPPORTED_PRN_MAX + 1, bandwidth_hz=4.092e6).validate()

    def test_all_prns_mode_skips_prn_id_range_validation(self) -> None:
        # all_prns=True 时 prn_id 超出范围不应抛出 ValueError
        config = RxRuntimeConfig(prn_id=0, bandwidth_hz=4.092e6, all_prns=True)
        config.validate()  # 不应抛出异常

    def test_all_prns_stem_contains_prn_all32_tag(self) -> None:
        config = RxRuntimeConfig(bandwidth_hz=4.092e6, all_prns=True)
        stem = build_timestamped_capture_stem(config, datetime(2026, 3, 26, 0, 0, 0))
        self.assertIn("prn_all32", stem)
        self.assertNotIn("prn1", stem)

    def test_default_config_all_prns_is_false(self) -> None:
        config = RxRuntimeConfig(bandwidth_hz=4.092e6)
        self.assertFalse(config.all_prns)


if __name__ == "__main__":
    unittest.main()
