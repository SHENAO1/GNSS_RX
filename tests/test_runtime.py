"""GNSS_RX 运行时配置行为测试。

RxRuntimeConfig 是整个接收程序的"参数中心"，它从 YAML 配置文件加载，
并提供采样数、文件路径等派生属性。这些测试确保配置的计算逻辑正确。
"""

from datetime import datetime  # 用于构造固定时间戳，使测试结果可重复
import tempfile                # 临时目录，测试后自动清理
import textwrap                # 用于去除多行字符串的公共缩进，让代码更整洁
import unittest                # Python 内置单元测试框架
from pathlib import Path       # 文件路径工具

# 导入被测的运行时模块中的所有相关符号
from gnss_rx.runtime import (
    DEFAULT_OUTPUT_BASE_DIR,          # 默认输出根目录（共享文件夹路径）
    RxRuntimeConfig,                  # 运行时配置数据类
    SUPPORTED_PRN_MAX,                # GPS PRN 编号上限（32）
    SUPPORTED_PRN_MIN,                # GPS PRN 编号下限（1）
    apply_overrides,                  # 用新参数覆盖配置的函数
    build_timestamped_capture_stem,   # 生成带时间戳的文件名前缀
    load_rx_runtime_config,           # 从 YAML 文件加载配置
    resolve_chunk_capture_paths,
    resolve_capture_paths,            # 根据配置解析输出文件的完整路径
)


class TestRxRuntimeConfig(unittest.TestCase):
    """测试运行时配置的各种计算和派生逻辑。"""

    def test_capture_samples_round_from_duration(self) -> None:
        """验证采样点总数 = 采样率 × 采集时长（结果取整）。

        公式：capture_samples = round(sample_rate_hz × duration_s)
        例：4.0 Hz × 2.5 s = 10.0 → 10 个采样点
        这个值决定了接收程序需要从 SDR 硬件读取多少个 IQ 样本。
        """
        config = RxRuntimeConfig(sample_rate_hz=4.0, duration_s=2.5, bandwidth_hz=4.0)
        self.assertEqual(config.capture_samples, 10)

    def test_load_config_derives_bandwidth(self) -> None:
        """验证从 YAML 文件加载配置时，带宽自动与采样率保持一致。

        带宽（bandwidth_hz）不需要在 YAML 中显式写明，
        加载后会自动设为等于采样率（这是 SDR 接收的标准做法）。
        同时验证输出目录和时间戳开关被正确读取。
        """
        with tempfile.TemporaryDirectory() as tmpdir:
            path = Path(tmpdir) / "rx.yaml"
            # textwrap.dedent 去掉每行开头多余的缩进，保证 YAML 格式正确
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

        # 带宽应自动等于采样率
        self.assertEqual(config.bandwidth_hz, 4092000.0)
        # 输出目录应使用默认的共享文件夹路径
        self.assertEqual(config.output_base_dir, DEFAULT_OUTPUT_BASE_DIR)
        # 时间戳文件名开关应为 True
        self.assertTrue(config.use_timestamped_stem)

    def test_apply_overrides_updates_bandwidth_when_sample_rate_changes(self) -> None:
        """验证通过 apply_overrides 修改采样率时，带宽会同步更新。

        apply_overrides 用于在不修改原配置对象的情况下，
        创建一个新配置（带宽始终跟随采样率同步变化）。
        """
        config = RxRuntimeConfig(bandwidth_hz=4.092e6)           # 初始：4.092 MHz
        updated = apply_overrides(config, sample_rate_hz=2.046e6)  # 修改为一半采样率
        self.assertEqual(updated.sample_rate_hz, 2.046e6)
        self.assertEqual(updated.bandwidth_hz, 2.046e6)          # 带宽也应同步减半

    def test_build_timestamped_capture_stem_uses_required_labels(self) -> None:
        """验证时间戳文件名包含所有必要的标签字段，且格式正确。

        文件名格式：<日期>_<时间>_rawiq_sc16_zeroif_<prn标签>_<模式>_sr<采样率>_cf<中心频率>_dur<时长>
        例：20260323_190530_rawiq_sc16_zeroif_prn1_spread_sr4092000_cf100000000_dur2p0s

        各字段含义：
          rawiq    = 原始 IQ 数据
          sc16     = SC16 格式
          zeroif   = 零中频（Zero-IF）接收模式
          prn1     = 第 1 号 GPS 卫星
          spread   = 扩频信号模式
          sr...    = 采样率（Hz）
          cf...    = 中心频率（Hz）
          dur...   = 采集时长（秒，小数点用 p 替代）
        """
        config = RxRuntimeConfig(bandwidth_hz=4.092e6)
        stem = build_timestamped_capture_stem(config, datetime(2026, 3, 23, 19, 5, 30))
        self.assertEqual(
            stem,
            "20260323_190530_rawiq_sc16_zeroif_prn1_spread_sr4092000_cf100000000_dur2p0s",
        )

    def test_resolve_capture_paths_uses_shared_folder_date_hierarchy(self) -> None:
        """验证输出路径按照年/年月日的层级目录结构组织。

        路径格式：<输出根目录>/<年>/<年_月_日>/<文件名前缀>/<文件名前缀>.sc16
        这种层级结构便于按日期浏览和管理大量采集文件。

        注意：data_path 和 metadata_path 只有扩展名不同（.sc16 vs .json）。
        """
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
        """验证手动指定 output_stem 时，不使用时间戳路径，而直接使用指定的路径。

        用于调试或指定固定输出文件名的场景，此时文件保存在项目目录下，
        而不是共享文件夹的日期层级目录中。
        """
        config = RxRuntimeConfig(bandwidth_hz=4.092e6, output_stem="results/captures/manual_capture")
        data_path, metadata_path = resolve_capture_paths(Path("/project"), config)
        # 路径以 /project 为根，直接拼接 output_stem
        self.assertEqual(str(data_path), "/project/results/captures/manual_capture.sc16")
        self.assertEqual(str(metadata_path), "/project/results/captures/manual_capture.json")

    def test_build_timestamped_capture_stem_tracks_selected_prn(self) -> None:
        """验证指定 prn_id=7 时，文件名中包含 "_prn7_" 标签。

        文件名中的 PRN 标签让用户看文件名就能知道这份数据对应哪颗卫星，
        无需打开文件或查看元数据。
        """
        config = RxRuntimeConfig(bandwidth_hz=4.092e6, prn_id=7)
        stem = build_timestamped_capture_stem(config, datetime(2026, 3, 23, 19, 5, 30))
        self.assertIn("_prn7_", stem)

    def test_prn_range_validation_rejects_values_outside_supported_range(self) -> None:
        """验证 validate() 对超出范围的 PRN 编号抛出 ValueError。

        GPS 系统的 PRN 编号范围是 1~32，超出此范围的值是无效的，
        应在验证阶段提前报错，避免后续采集到无意义的数据。
        """
        # PRN 编号比最小值还小（小于 1）→ 无效
        with self.assertRaises(ValueError):
            RxRuntimeConfig(prn_id=SUPPORTED_PRN_MIN - 1, bandwidth_hz=4.092e6).validate()
        # PRN 编号比最大值还大（大于 32）→ 无效
        with self.assertRaises(ValueError):
            RxRuntimeConfig(prn_id=SUPPORTED_PRN_MAX + 1, bandwidth_hz=4.092e6).validate()

    def test_all_prns_mode_skips_prn_id_range_validation(self) -> None:
        """验证 all_prns=True 时跳过 prn_id 范围校验。

        all_prns 模式采集所有 32 颗卫星的复合信号，prn_id 在此模式下
        没有意义（可能被设为 0 等占位值），所以不应触发范围验证错误。
        """
        # all_prns=True 时 prn_id 超出范围不应抛出 ValueError
        config = RxRuntimeConfig(prn_id=0, bandwidth_hz=4.092e6, all_prns=True)
        config.validate()  # 不应抛出异常

    def test_all_prns_stem_contains_prn_all32_tag(self) -> None:
        """验证全卫星模式的文件名包含 "prn_all32" 标签，而不是单个 PRN 编号。

        "prn_all32" 清晰地表明数据包含全部 32 颗 GPS 卫星的叠加信号，
        与单颗卫星文件（如 "prn7"）明确区分，避免混淆。
        """
        config = RxRuntimeConfig(bandwidth_hz=4.092e6, all_prns=True)
        stem = build_timestamped_capture_stem(config, datetime(2026, 3, 26, 0, 0, 0))
        self.assertIn("prn_all32", stem)
        self.assertNotIn("prn1", stem)   # 不应出现单颗卫星的标签

    def test_default_config_all_prns_is_false(self) -> None:
        """验证默认情况下 all_prns=False，即默认为单颗卫星采集模式。

        这确保了不显式开启全卫星模式时，行为是确定且保守的，
        不会误采集多余的卫星信号。
        """
        config = RxRuntimeConfig(bandwidth_hz=4.092e6)
        self.assertFalse(config.all_prns)

    def test_chunked_mode_reports_chunk_count_and_paths(self) -> None:
        config = RxRuntimeConfig(
            bandwidth_hz=4.092e6,
            duration_s=95.0,
            capture_mode="chunked",
            chunk_duration_s=30.0,
        )
        chunk_specs = resolve_chunk_capture_paths(
            Path("/project"),
            config,
            when=datetime(2026, 3, 23, 19, 5, 30),
        )

        self.assertEqual(config.chunk_count, 4)
        self.assertEqual(len(chunk_specs), 4)
        self.assertEqual(chunk_specs[0][2], 30.0)
        self.assertEqual(chunk_specs[-1][2], 5.0)
        self.assertTrue(str(chunk_specs[0][0]).endswith("_chunk0001of0004.sc16"))


if __name__ == "__main__":
    unittest.main()
