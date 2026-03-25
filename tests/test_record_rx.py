"""record_rx CLI 的 dry-run 行为测试。"""

import io
import unittest
from contextlib import redirect_stdout
from pathlib import Path
from unittest import mock

from scripts import record_rx


class TestRecordRxScript(unittest.TestCase):
    def test_dry_run_prints_output_contract_and_paths(self) -> None:
        argv = [
            "--config",
            "configs/rx_prn1_capture.yaml",
            "--dry-run",
        ]

        fixed_data_path = Path(
            "/mnt/hgfs/GongXiangDocument/GNSS_RX_Data/2026/2026-03-23/"
            "20260323_190530_rawiq_sc16_zeroif_prn1_spread_sr4092000_cf100000000_dur2p0s.sc16"
        )
        fixed_metadata_path = fixed_data_path.with_suffix(".json")

        with (
            mock.patch.object(record_rx, "uhd_find_devices_output", return_value="serial: RX123"),
            mock.patch.object(record_rx, "resolve_capture_paths", return_value=(fixed_data_path, fixed_metadata_path)),
        ):
            buffer = io.StringIO()
            with redirect_stdout(buffer):
                exit_code = record_rx.main(argv)

        output = buffer.getvalue()
        self.assertEqual(exit_code, 0)
        self.assertIn("GNSS_RX 采集配置", output)
        self.assertIn("sample_format=sc16", output)
        self.assertIn(str(fixed_data_path), output)
        self.assertIn("metadata_file=", output)
        self.assertIn("已请求 dry-run", output)

    def test_dry_run_accepts_prn_override(self) -> None:
        argv = [
            "--config",
            "configs/rx_prn1_capture.yaml",
            "--prn-id",
            "7",
            "--dry-run",
        ]

        fixed_data_path = Path(
            "/mnt/hgfs/GongXiangDocument/GNSS_RX_Data/2026/2026-03-23/"
            "20260323_190530_rawiq_sc16_zeroif_prn7_spread_sr4092000_cf100000000_dur2p0s.sc16"
        )
        fixed_metadata_path = fixed_data_path.with_suffix(".json")

        with (
            mock.patch.object(record_rx, "uhd_find_devices_output", return_value="serial: RX123"),
            mock.patch.object(record_rx, "resolve_capture_paths", return_value=(fixed_data_path, fixed_metadata_path)),
        ):
            buffer = io.StringIO()
            with redirect_stdout(buffer):
                exit_code = record_rx.main(argv)

        output = buffer.getvalue()
        self.assertEqual(exit_code, 0)
        self.assertIn("prn_id=7", output)
        self.assertIn("expected_prn=7", output)


if __name__ == "__main__":
    unittest.main()
