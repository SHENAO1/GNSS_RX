"""record_rx CLI 的 dry-run 行为测试。

record_rx 是 GNSS_RX 的主采集脚本，通过命令行运行。
dry-run（演练模式）是一种"只打印、不执行"的模式：
  - 打印出将要执行的操作和输出路径
  - 不实际连接 SDR 硬件，不采集数据
  - 适合在没有硬件的环境下验证配置是否正确

这里使用 mock（模拟）替换掉需要硬件的部分，使测试可在任何机器上运行。
"""

import io                           # 用于捕获程序打印到标准输出的内容
import unittest                     # Python 内置单元测试框架
from contextlib import redirect_stdout  # 将 print 输出重定向到内存缓冲区
from pathlib import Path            # 文件路径工具
from unittest import mock           # 模拟（mock）工具，用于替换真实的硬件调用

from scripts import record_rx       # 被测的 CLI 脚本模块


class TestRecordRxScript(unittest.TestCase):
    """测试 record_rx 脚本在 dry-run 模式下的输出内容。"""

    def test_dry_run_prints_output_contract_and_paths(self) -> None:
        """验证 dry-run 模式会打印采集配置摘要和完整的输出文件路径。

        运行方式（等效的命令行）：
          python record_rx.py --config configs/rx_prn1_capture.yaml --dry-run

        测试策略：
          1. 用 mock.patch.object 替换两个需要硬件/文件系统的函数：
             - uhd_find_devices_output：原本会调用 UHD 驱动扫描 USRP 设备，
               这里直接返回伪造的设备序列号字符串
             - resolve_capture_paths：原本会根据当前时间生成路径，
               这里返回固定的路径，使断言可重复
          2. 用 redirect_stdout 把 print 输出捕获到 StringIO 缓冲区
          3. 断言输出中包含预期的关键词
        """
        argv = [
            "--config",
            "configs/rx_prn1_capture.yaml",
            "--dry-run",
        ]

        # 固定的输出路径（通常由当前时间生成，这里固定以便断言）
        fixed_data_path = Path(
            "/mnt/hgfs/GongXiangDocument/GNSS_RX_Data/2026/2026-03-23/"
            "20260323_190530_rawiq_sc16_zeroif_prn1_spread_sr4092000_cf100000000_dur2p0s.sc16"
        )
        fixed_metadata_path = fixed_data_path.with_suffix(".json")  # 同名但扩展名改为 .json

        chunk_specs = [
            (fixed_data_path, fixed_metadata_path, 2.0, 1, 1, "group"),
        ]

        with (
            # 模拟 UHD 设备扫描，返回假设备序列号
            mock.patch.object(record_rx, "uhd_find_devices_output", return_value="serial: RX123"),
            # 模拟路径解析，返回固定路径对
            mock.patch.object(record_rx, "resolve_chunk_capture_paths", return_value=chunk_specs),
        ):
            buffer = io.StringIO()              # 创建内存缓冲区
            with redirect_stdout(buffer):       # 将 print 输出重定向到缓冲区
                exit_code = record_rx.main(argv)

        output = buffer.getvalue()              # 取出捕获的全部输出文本

        # 验证退出码为 0（成功）
        self.assertEqual(exit_code, 0)
        # 验证输出包含各关键信息
        self.assertIn("GNSS_RX 采集配置", output)         # 配置摘要标题
        self.assertIn("sample_format=sc16", output)        # 数据格式
        self.assertIn(str(fixed_data_path), output)        # 数据文件完整路径
        self.assertIn("metadata_file=", output)            # 元数据文件路径标签
        self.assertIn("已请求 dry-run", output)            # dry-run 提示语

    def test_dry_run_accepts_prn_override(self) -> None:
        """验证通过 --prn-id 参数可以覆盖配置文件中的 PRN 编号。

        运行方式（等效的命令行）：
          python record_rx.py --config configs/rx_prn1_capture.yaml --prn-id 7 --dry-run

        这个测试确保命令行参数优先级高于 YAML 配置文件，
        用户可以在不修改配置文件的情况下临时采集不同卫星的信号。
        """
        argv = [
            "--config",
            "configs/rx_prn1_capture.yaml",
            "--prn-id",
            "7",       # 命令行指定 PRN=7，覆盖配置文件中的 prn_id=1
            "--dry-run",
        ]

        fixed_data_path = Path(
            "/mnt/hgfs/GongXiangDocument/GNSS_RX_Data/2026/2026-03-23/"
            "20260323_190530_rawiq_sc16_zeroif_prn7_spread_sr4092000_cf100000000_dur2p0s.sc16"
        )
        fixed_metadata_path = fixed_data_path.with_suffix(".json")

        chunk_specs = [
            (fixed_data_path, fixed_metadata_path, 2.0, 1, 1, "group"),
        ]

        with (
            mock.patch.object(record_rx, "uhd_find_devices_output", return_value="serial: RX123"),
            mock.patch.object(record_rx, "resolve_chunk_capture_paths", return_value=chunk_specs),
        ):
            buffer = io.StringIO()
            with redirect_stdout(buffer):
                exit_code = record_rx.main(argv)

        output = buffer.getvalue()
        self.assertEqual(exit_code, 0)
        # 验证配置摘要中显示的是被覆盖后的 prn_id=7
        self.assertIn("prn_id=7", output)
        # 验证元数据部分也显示正确的预期 PRN
        self.assertIn("expected_prn=7", output)

    def test_dry_run_reports_chunked_capture_summary(self) -> None:
        argv = [
            "--config",
            "configs/rx_prn1_capture.yaml",
            "--capture-mode",
            "chunked",
            "--chunk-duration",
            "30",
            "--duration",
            "95",
            "--dry-run",
        ]

        fixed_data_path = Path(
            "/mnt/hgfs/GongXiangDocument/GNSS_RX_Data/2026/2026-03-23/"
            "20260323_190530_rawiq_sc16_zeroif_prn1_spread_sr4092000_cf100000000_dur95p0s/"
            "20260323_190530_rawiq_sc16_zeroif_prn1_spread_sr4092000_cf100000000_dur95p0s_chunk0001of0004.sc16"
        )
        fixed_metadata_path = fixed_data_path.with_suffix(".json")
        chunk_specs = [
            (fixed_data_path, fixed_metadata_path, 30.0, 1, 4, "group"),
        ]

        with (
            mock.patch.object(record_rx, "uhd_find_devices_output", return_value="serial: RX123"),
            mock.patch.object(record_rx, "resolve_chunk_capture_paths", return_value=chunk_specs),
        ):
            buffer = io.StringIO()
            with redirect_stdout(buffer):
                exit_code = record_rx.main(argv)

        output = buffer.getvalue()
        self.assertEqual(exit_code, 0)
        self.assertIn("capture_mode=chunked", output)
        self.assertIn("chunk_duration_s=30.0", output)
        self.assertIn("chunked 模式：共 1 段", output)


if __name__ == "__main__":
    unittest.main()
