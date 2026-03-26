"""采集元数据测试。

元数据（metadata）是描述采集数据的"说明书"，保存在 .json 文件中，
与 .sc16 原始采样数据文件配对存放。接收端（如 MATLAB）读取元数据后
才能正确解析原始数据（知道采样率、格式、PRN 号等信息）。
"""

import json           # 用于解析 JSON 文件内容
import tempfile       # 用于创建临时目录，测试后自动清理
import unittest       # Python 内置单元测试框架
from pathlib import Path  # 文件路径工具

# 从项目中导入被测函数
from gnss_rx.metadata import build_capture_metadata, write_metadata_json
from gnss_rx.runtime import RxRuntimeConfig


class TestMetadata(unittest.TestCase):
    """验证元数据的构建和序列化行为。"""

    def test_metadata_contains_matlab_handoff_fields(self) -> None:
        """验证元数据包含 MATLAB 解析所需的关键字段。

        MATLAB 脚本会读取这些字段来决定如何加载原始 IQ 数据：
          - sample_format: 文件格式标识，"sc16" 表示有符号 16 位整数 IQ
          - complex_layout: 数据在文件中的排列方式（I/Q 交替、小端字节序）
          - samples_captured: 文件中的采样点总数
          - prn_id: 对应的 GPS 卫星 PRN 编号（默认为 1）
        """
        config = RxRuntimeConfig(bandwidth_hz=4.092e6)
        metadata = build_capture_metadata(config=config, samples_captured=8192, data_path=Path("demo.sc16"))

        self.assertEqual(metadata.sample_format, "sc16")
        self.assertEqual(metadata.complex_layout, "iq_int16_interleaved_le")  # le = little-endian 小端
        self.assertEqual(metadata.samples_captured, 8192)
        self.assertEqual(metadata.prn_id, 1)  # 默认 PRN 为 1

    def test_write_metadata_json_serializes_expected_keys(self) -> None:
        """验证元数据写入 JSON 文件后，反序列化结果包含正确的键值。

        确保 JSON 文件中的字段名和内容与元数据对象一致，
        以便下游工具（MATLAB、Python 分析脚本）能正常读取。
        """
        config = RxRuntimeConfig(bandwidth_hz=4.092e6)
        metadata = build_capture_metadata(config=config, samples_captured=2048, data_path=Path("demo.sc16"))

        with tempfile.TemporaryDirectory() as tmpdir:
            path = Path(tmpdir) / "demo.json"
            write_metadata_json(path, metadata)              # 写入 JSON 文件
            parsed = json.loads(path.read_text(encoding="utf-8"))  # 读回并解析

        self.assertEqual(parsed["sample_format"], "sc16")
        self.assertEqual(parsed["data_file"], "demo.sc16")   # 关联的数据文件名
        self.assertEqual(parsed["signal_mode"], "spread")    # 扩频模式

    def test_metadata_preserves_selected_prn(self) -> None:
        """验证当用户指定 prn_id 时，元数据中记录的是正确的 PRN 编号。

        GPS 共有 32 颗卫星，每颗分配一个 PRN（伪随机码）编号（1~32）。
        这里指定 prn_id=7，验证元数据不会误用默认值 1。
        """
        config = RxRuntimeConfig(bandwidth_hz=4.092e6, prn_id=7)
        metadata = build_capture_metadata(config=config, samples_captured=2048, data_path=Path("demo.sc16"))
        self.assertEqual(metadata.prn_id, 7)

    def test_single_prn_metadata_has_all_prns_false_and_no_prn_ids(self) -> None:
        """验证单颗卫星采集模式下：all_prns 标志为 False，且 prn_ids 列表为空。

        单颗模式（single PRN）只采集一颗卫星的信号，
        all_prns=False 表示不是全卫星采集，prn_ids=None 表示无卫星列表。
        """
        config = RxRuntimeConfig(bandwidth_hz=4.092e6, prn_id=5)
        metadata = build_capture_metadata(config=config, samples_captured=2048, data_path=Path("demo.sc16"))
        self.assertFalse(metadata.all_prns)
        self.assertIsNone(metadata.prn_ids)  # 单颗模式不需要列表

    def test_all_prns_metadata_sets_all_prns_flag_and_prn_ids_list(self) -> None:
        """验证全卫星采集模式下：all_prns=True，且 prn_ids 包含 1~32 的完整列表。

        all_prns=True 表示同时采集全部 32 颗 GPS 卫星的复合信号。
        prn_ids 列表用于告知下游工具这份数据中包含哪些卫星。
        """
        config = RxRuntimeConfig(bandwidth_hz=4.092e6, all_prns=True)
        metadata = build_capture_metadata(config=config, samples_captured=2048, data_path=Path("demo.sc16"))
        self.assertTrue(metadata.all_prns)
        self.assertEqual(metadata.prn_ids, list(range(1, 33)))  # [1, 2, ..., 32]

    def test_all_prns_metadata_serializes_prn_ids_to_json(self) -> None:
        """验证全卫星模式的元数据写入 JSON 后，prn_ids 列表被正确序列化。

        确保 JSON 文件中的 prn_ids 字段是完整的 1~32 数组，
        供 MATLAB 等工具识别数据中包含的所有卫星 PRN 编号。
        """
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
