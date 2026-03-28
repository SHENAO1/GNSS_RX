"""
runtime.py — 接收机运行时配置

这个模块定义了一次 GNSS 信号采集任务所需的全部参数（中心频率、采样率、
增益、时长等），以及围绕这些参数的辅助函数。

核心概念速览：
  • USRP（Universal Software Radio Peripheral）：Ettus Research 出品的软件
    无线电硬件，本项目用 B210 型号通过 USB 连接到电脑进行 IQ 采样。
  • 零中频（Zero-IF / Zero Intermediate Frequency）：接收机直接将射频信号
    下变频到基带（0 Hz 附近），避免了传统超外差接收机的中频阶段。
  • IQ 采样：复数基带信号，I（同相分量）和 Q（正交分量）各是一路实数序列，
    合在一起表示一个复数序列。
  • SC16 格式：每个 IQ 样本用两个 16 位整数表示（I: int16, Q: int16），
    是 UHD 驱动与 MATLAB 之间常用的紧凑存储格式。
  • PRN（Pseudo-Random Noise code）：GPS 中每颗卫星拥有唯一的 PRN 码，
    编号 1~32，用于扩频调制和卫星识别。
"""

from __future__ import annotations

import os
from datetime import datetime
from dataclasses import asdict, dataclass, replace  # dataclass：自动生成 __init__/__repr__；replace：产生修改后的副本
import math
from pathlib import Path
from typing import Any

from gnss_rx.utils.io import load_yaml_file  # 读取 YAML 配置文件的工具函数

# ──────────────────────────────────────────────────────────────
# 模块级常量
# ──────────────────────────────────────────────────────────────

# 采集数据的默认存储目录，优先读取环境变量 GNSS_RX_DATA_DIR。
# 如果该环境变量不存在，则使用右侧的路径（VMware 共享文件夹路径）。
DEFAULT_OUTPUT_BASE_DIR = os.environ.get(
    "GNSS_RX_DATA_DIR",
    "/mnt/hgfs/GongXiangDocument/GNSS_RX_Data",
)

SUPPORTED_PRN_MIN = 1   # GPS PRN 编号最小值
SUPPORTED_PRN_MAX = 32  # GPS PRN 编号最大值（L1 C/A 共 32 颗卫星）

TIMESTAMP_FORMAT = "%Y%m%d_%H%M%S"   # 时间戳格式，例如 "20260326_153045"
DATE_DIRECTORY_FORMAT = "%Y_%m_%d"    # 日期子目录格式，例如 "2026_03_26"


# ──────────────────────────────────────────────────────────────
# 运行时配置数据类
# ──────────────────────────────────────────────────────────────

@dataclass(frozen=True)  # frozen=True：创建后字段不可修改，确保配置不被意外改变
class RxRuntimeConfig:
    """描述一次 GNSS IQ 采集任务的全部参数。

    这是一个不可变（frozen）的数据类，相当于"采集任务的快照"。
    所有字段都有默认值，因此可以只覆盖需要改变的参数。

    字段说明：
        usrp_addr:         USRP 设备地址。"type=b200" 自动匹配 B200/B210 系列。
                           如果有多台设备，可以用序列号指定，如 "serial=12345678"。
        center_freq_hz:    接收中心频率（Hz）。100 MHz 是一个便于实验室测试的频率，
                           GPS L1 实际中心频率为 1575.42 MHz。
        sample_rate_hz:    采样率（Hz）。4.092 MHz = 4 × 1.023 MHz，
                           其中 1.023 MHz 是 GPS C/A 码的码片速率，
                           4× 过采样可以保留足够的细节供 MATLAB 捕获使用。
        rx_gain_db:        接收增益（dB）。增益过低信号淹没在噪声中，
                           增益过高 ADC 饱和失真，需根据实际环境调整。
        bandwidth_hz:      射频滤波器带宽（Hz）。None 表示使用硬件默认值。
                           通常设置为与采样率相同或略大。
        antenna:           天线端口名称。B210 有 "RX2" 和 "TX/RX" 两个接收端口。
        duration_s:        采集时长（秒）。
        output_base_dir:   采集数据根目录，子目录结构由程序自动创建。
        use_timestamped_stem: True → 用时间戳自动命名文件；
                              False → 必须提供 output_stem。
        output_stem:       手动指定的文件名前缀（不含扩展名），
                           None 时程序根据参数自动生成带时间戳的名称。
        clock_source:      时钟源。"internal" 使用 USRP 内置振荡器；
                           "external" 或 "gpsdo" 使用外部参考时钟（精度更高）。
        time_source:       时间源，同上，影响 PPS（每秒脉冲）对齐。
        signal_mode:       发射端信号模式，供元数据记录使用。
                           "spread" = 扩频信号（正常 GPS 信号）；
                           "tone"   = 单音（纯正弦波，用于校准）。
        prn_id:            目标卫星 PRN 编号（1~32）。
                           当 all_prns=True 时此字段仅作兼容保留。
        all_prns:          True 时表示 TX 端发射了 PRN 1~32 全部叠加信号。
        tx_profile_reference: 对应 TX 端配置文件的相对路径，记录到元数据中
                              方便事后追溯发射端的参数设置。
    """

    usrp_addr: str = "type=b200"
    center_freq_hz: float = 100e6          # 100 MHz（实验室默认值）
    sample_rate_hz: float = 4.092e6        # 4.092 MHz（GPS C/A 码 4× 过采样）
    rx_gain_db: float = 20.0
    bandwidth_hz: float | None = None
    antenna: str = "RX2"
    duration_s: float = 2.0
    capture_mode: str = "single"
    chunk_duration_s: float = 30.0
    output_base_dir: str = DEFAULT_OUTPUT_BASE_DIR
    use_timestamped_stem: bool = True
    output_stem: str | None = None
    clock_source: str = "internal"
    time_source: str = "internal"
    signal_mode: str = "spread"
    prn_id: int = 1
    # True 时表示对应的 TX 端发射了 PRN 1~32 全部叠加信号。
    # 此时 prn_id 字段仅作兼容保留，不参与捕获判决。
    all_prns: bool = False
    tx_profile_reference: str = "../gnss_tx/configs/tx_b210_visible_spectrum.yaml"

    def validate(self) -> "RxRuntimeConfig":
        """检查所有参数的合法性，返回自身；发现问题时抛出 ValueError。

        这个方法在加载配置后立即调用，确保不合理的参数（如负增益、
        空天线名等）在程序运行前就被发现，而不是在采集过程中才报错。

        返回：
            self（经过验证的配置对象本身）

        异常：
            ValueError: 任何参数不满足物理约束时抛出，错误信息为中文。
        """
        if self.center_freq_hz <= 0:
            raise ValueError("center_freq_hz 必须大于 0。")
        if self.sample_rate_hz <= 0:
            raise ValueError("sample_rate_hz 必须大于 0。")
        if self.duration_s <= 0:
            raise ValueError("duration_s 必须大于 0。")
        if self.capture_mode not in {"single", "chunked"}:
            raise ValueError("capture_mode 必须是以下之一：single、chunked。")
        if self.chunk_duration_s <= 0:
            raise ValueError("chunk_duration_s 必须大于 0。")
        if self.rx_gain_db < 0:
            raise ValueError("rx_gain_db 必须大于等于 0。")
        if self.bandwidth_hz is not None and self.bandwidth_hz <= 0:
            raise ValueError("bandwidth_hz 在提供时必须大于 0。")
        if not self.antenna:
            raise ValueError("antenna 不能为空。")
        if self.signal_mode not in {"spread", "tone"}:
            raise ValueError("signal_mode 必须是以下之一：spread、tone。")
        # all_prns 模式下不检查 prn_id（它只是占位符）
        if not self.all_prns and not SUPPORTED_PRN_MIN <= self.prn_id <= SUPPORTED_PRN_MAX:
            raise ValueError(
                f"prn_id 必须在支持范围 {SUPPORTED_PRN_MIN}~{SUPPORTED_PRN_MAX} 内。"
            )
        if not self.output_base_dir:
            raise ValueError("output_base_dir 不能为空。")
        if self.output_stem is not None and not self.output_stem:
            raise ValueError("output_stem 在提供时不能为空。")
        if not self.use_timestamped_stem and self.output_stem is None:
            raise ValueError("当 use_timestamped_stem 为 false 时，必须提供 output_stem。")
        return self

    @property
    def capture_samples(self) -> int:
        """根据采样率和时长计算总采样点数。

        这是一个只读属性（@property），像访问普通字段一样使用：
            config.capture_samples  →  例如 8184000（= 4092000 Hz × 2 s）

        GNU Radio 的 blocks.head 模块需要知道"总共采多少个样本就停止"，
        这个值就是用来设置该模块的上限的。
        """
        return int(round(self.sample_rate_hz * self.duration_s))

    @property
    def chunk_count(self) -> int:
        if self.capture_mode != "chunked":
            return 1
        return int(math.ceil(self.duration_s / self.chunk_duration_s))

    @property
    def chunk_samples(self) -> int:
        effective_chunk_s = min(self.duration_s, self.chunk_duration_s) if self.capture_mode == "chunked" else self.duration_s
        return int(round(self.sample_rate_hz * effective_chunk_s))


# ──────────────────────────────────────────────────────────────
# 配置加载与覆盖
# ──────────────────────────────────────────────────────────────

def load_rx_runtime_config(path: str | Path) -> RxRuntimeConfig:
    """从 YAML 文件加载接收机运行配置。

    YAML 文件示例（configs/rx_b210.yaml）：
        sample_rate_hz: 4092000
        center_freq_hz: 100000000
        rx_gain_db: 30
        duration_s: 5.0

    特殊处理：如果 YAML 中没有显式设置 bandwidth_hz，则将其自动
    设置为与 sample_rate_hz 相同的值（这对 B210 是合理的默认值）。

    参数：
        path: YAML 配置文件路径。

    返回：
        验证通过的 RxRuntimeConfig 实例。
    """
    raw = load_yaml_file(path)  # 读取 YAML 文件，得到字典

    # 如果没有显式指定 bandwidth_hz，用 sample_rate_hz 补全，
    # 避免 B210 使用过宽的默认带宽导致采集到多余的混叠信号。
    if "bandwidth_hz" not in raw and "sample_rate_hz" in raw:
        raw["bandwidth_hz"] = float(raw["sample_rate_hz"])

    # **raw 是 Python 的字典展开语法，相当于把字典的键值对作为关键字参数传入
    return RxRuntimeConfig(**raw).validate()


def apply_overrides(config: RxRuntimeConfig, **overrides: Any) -> RxRuntimeConfig:
    """在现有配置基础上应用命令行或代码中指定的覆盖值，返回新配置。

    因为 RxRuntimeConfig 是 frozen（不可变）的，所以修改参数的方式是
    创建一个新的副本，而不是直接修改原对象。

    只有值不为 None 的覆盖才会生效，这样命令行中未指定的参数就不会
    覆盖 YAML 文件中的设置。

    特殊逻辑：如果覆盖了 sample_rate_hz 但没有同时覆盖 bandwidth_hz，
    则自动将 bandwidth_hz 更新为新的 sample_rate_hz（保持同步）。

    参数：
        config:    原始配置（来自 YAML）。
        **overrides: 任意数量的关键字参数，例如 rx_gain_db=40, duration_s=10。

    返回：
        验证通过的新 RxRuntimeConfig 实例（原对象不变）。

    示例：
        new_cfg = apply_overrides(base_cfg, rx_gain_db=40, duration_s=10)
    """
    # 过滤掉 None 值，只保留用户真正指定的覆盖
    effective: dict[str, Any] = {}
    for key, value in overrides.items():
        if value is not None:
            effective[key] = value

    # dataclasses.replace 创建一个副本，并将 effective 中的字段替换掉
    candidate = replace(config, **effective)

    # 如果改变了采样率但没有同时指定带宽，则带宽跟随采样率更新
    if "bandwidth_hz" not in effective and "sample_rate_hz" in effective:
        candidate = replace(candidate, bandwidth_hz=candidate.sample_rate_hz)

    return candidate.validate()


# ──────────────────────────────────────────────────────────────
# 文件命名辅助函数
# ──────────────────────────────────────────────────────────────

def format_capture_tag(value: float, *, keep_decimal: bool = False) -> str:
    """将浮点数格式化为适合嵌入文件名的字符串。

    文件名不能含有小数点和负号，因此做如下替换：
      - 小数点 "."  →  "p"（point 的首字母）
      - 负号   "-"  →  "m"（minus 的首字母）

    示例：
        format_capture_tag(4.092e6)         →  "4092000"
        format_capture_tag(100e6)           →  "100000000"
        format_capture_tag(2.5)             →  "2p5"
        format_capture_tag(2.0, keep_decimal=True)  →  "2p0"
        format_capture_tag(-1.5)            →  "m1p5"

    参数：
        value:        要格式化的数值。
        keep_decimal: True 时即使结果是整数也保留小数点（如时长 "2.0s"）。
    """
    # 如果是整数且不需要保留小数，直接返回整数字符串
    if float(value).is_integer() and not keep_decimal:
        return str(int(round(float(value))))

    # 用 "f" 格式化为十进制字符串（不用科学计数法）
    text = format(float(value), "f")
    if "." in text:
        # 去掉末尾多余的 0（如 "4.500000" → "4.5"）
        text = text.rstrip("0").rstrip(".")
    if keep_decimal and "." not in text:
        # keep_decimal=True 时确保结果包含小数点（如 "2" → "2.0"）
        text = f"{text}.0"

    # 最后将文件名不合法的字符替换掉
    return text.replace("-", "m").replace(".", "p")


def build_timestamped_capture_stem(config: RxRuntimeConfig, when: datetime) -> str:
    """根据配置和时间戳，构造带参数摘要的文件名主干（不含扩展名）。

    生成的文件名包含了所有关键采集参数，便于根据文件名回溯实验条件，
    而无需打开配套的 .json 元数据文件。

    示例输出（格式化后已换行，实际为一行）：
        "20260326_153045_rawiq_sc16_zeroif_prn1_spread_sr4092000_cf100000000_dur2p0s"

    各字段含义：
        20260326_153045  → 采集开始时间
        rawiq            → 原始 IQ 数据
        sc16             → 数据格式（Signed Complex 16-bit）
        zeroif           → 零中频采集模式
        prn1 / prn_all32 → 目标 PRN 编号或全部 32 颗
        spread / tone    → 信号调制模式
        sr4092000        → 采样率 4.092 MHz
        cf100000000      → 中心频率 100 MHz
        dur2p0s          → 采集时长 2.0 秒

    参数：
        config: 当前运行时配置。
        when:   采集开始时刻（datetime 对象）。
    """
    timestamp = when.strftime(TIMESTAMP_FORMAT)
    prn_tag = "prn_all32" if config.all_prns else f"prn{config.prn_id}"
    return "_".join(
        [
            timestamp,
            "rawiq",
            "sc16",
            "zeroif",
            prn_tag,
            config.signal_mode,
            f"sr{format_capture_tag(config.sample_rate_hz)}",
            f"cf{format_capture_tag(config.center_freq_hz)}",
            f"dur{format_capture_tag(config.duration_s, keep_decimal=True)}s",
        ]
    )


def resolve_output_stem_path(project_root: Path, config: RxRuntimeConfig, when: datetime | None = None) -> Path:
    """解析输出文件名的完整路径（不含扩展名）。

    有两种模式：
    1. 手动指定（output_stem 不为 None）：直接使用给定的路径。
       相对路径以 project_root 为基准。
    2. 自动时间戳（use_timestamped_stem=True）：在 output_base_dir 下
       自动创建"年/年_月_日/文件名/"结构，文件名包含参数摘要和时间戳。

    目录结构示例（自动模式）：
        /mnt/hgfs/.../GNSS_RX_Data/
          2026/
            2026_03_26/
              20260326_153045_rawiq_sc16_zeroif_prn1_spread_sr4092000_cf100000000_dur2p0s/
                20260326_153045_rawiq_sc16_zeroif_prn1_spread_sr4092000_cf100000000_dur2p0s.sc16
                20260326_153045_rawiq_sc16_zeroif_prn1_spread_sr4092000_cf100000000_dur2p0s.json

    参数：
        project_root: 项目根目录，用于将相对路径转换为绝对路径。
        config:       运行时配置。
        when:         采集时刻，None 时使用当前系统时间。

    返回：
        不含扩展名的完整路径（Path 对象）。
    """
    # 情况 1：用户手动指定了 output_stem
    if config.output_stem is not None:
        stem_path = Path(config.output_stem)
        if not stem_path.is_absolute():
            # 相对路径以项目根目录为基准
            stem_path = project_root / stem_path
        return stem_path

    # 情况 2：自动生成时间戳文件名
    capture_time = when if when is not None else datetime.now()

    base_dir = Path(config.output_base_dir)
    if not base_dir.is_absolute():
        base_dir = project_root / base_dir  # 相对路径转绝对路径

    # 创建"年/年_月_日"两级日期子目录，再在里面放一个同名子目录（便于归档）
    dated_dir = base_dir / capture_time.strftime("%Y") / capture_time.strftime(DATE_DIRECTORY_FORMAT)
    stem = build_timestamped_capture_stem(config, capture_time)

    # 返回 dated_dir/stem/stem（目录名与文件名主干相同）
    return dated_dir / stem / stem


def resolve_capture_paths(project_root: Path, config: RxRuntimeConfig, when: datetime | None = None) -> tuple[Path, Path]:
    """解析采集数据文件（.sc16）和元数据文件（.json）的完整路径。

    这是最常用的路径解析入口。内部调用 resolve_output_stem_path 获取
    共同的文件名主干，然后分别追加两种扩展名。

    参数：
        project_root: 项目根目录。
        config:       运行时配置。
        when:         采集时刻，None 时使用当前系统时间。

    返回：
        (data_path, metadata_path) 元组，例如：
            (Path(".../stem.sc16"), Path(".../stem.json"))
    """
    stem_path = resolve_output_stem_path(project_root, config, when=when)
    return stem_path.with_suffix(".sc16"), stem_path.with_suffix(".json")


def resolve_chunk_capture_paths(
    project_root: Path,
    config: RxRuntimeConfig,
    when: datetime | None = None,
) -> list[tuple[Path, Path, float, int, int, str]]:
    """解析 chunked 采集模式下每个 chunk 的输出路径和时长。"""
    if config.capture_mode != "chunked":
        data_path, metadata_path = resolve_capture_paths(project_root, config, when=when)
        group_id = data_path.stem
        return [(data_path, metadata_path, config.duration_s, 1, 1, group_id)]

    base_stem = resolve_output_stem_path(project_root, config, when=when)
    group_id = base_stem.name
    chunk_specs: list[tuple[Path, Path, float, int, int, str]] = []
    total_chunks = config.chunk_count
    remaining_s = config.duration_s

    for chunk_index in range(1, total_chunks + 1):
        chunk_duration_s = min(config.chunk_duration_s, remaining_s)
        chunk_stem = base_stem.parent / f"{base_stem.name}_chunk{chunk_index:04d}of{total_chunks:04d}"
        chunk_specs.append((
            chunk_stem.with_suffix(".sc16"),
            chunk_stem.with_suffix(".json"),
            chunk_duration_s,
            chunk_index,
            total_chunks,
            group_id,
        ))
        remaining_s -= chunk_duration_s

    return chunk_specs


# ──────────────────────────────────────────────────────────────
# 终端报告格式化函数
# ──────────────────────────────────────────────────────────────

def format_capture_report(config: RxRuntimeConfig, *, data_path: Path, metadata_path: Path) -> str:
    """生成一段可打印到终端的采集配置摘要报告。

    在采集开始前打印，供操作员核对参数是否正确。

    参数：
        config:        运行时配置。
        data_path:     .sc16 文件的目标路径。
        metadata_path: .json 文件的目标路径。

    返回：
        多行字符串，可直接 print() 或写入日志。
    """
    lines = [
        "=" * 60,
        "GNSS_RX 采集配置",
        "=" * 60,
    ]
    # asdict 将 dataclass 转换为字典，便于遍历所有字段
    for key, value in asdict(config).items():
        lines.append(f"{key}={value}")
    lines.extend(
        [
            f"capture_samples={config.capture_samples}",   # 派生属性，额外打印
            f"chunk_samples={config.chunk_samples}",
            f"chunk_count={config.chunk_count}",
            f"data_path={data_path}",
            f"metadata_path={metadata_path}",
            "",
            "采集模式                   : 零中频复基带",
            "输出约定                   : .sc16 IQ 文件 + .json 伴随文件",
            "接收端说明                 : 该阶段记录原始观测数据，供 MATLAB 离线捕获使用。",
        ]
    )
    return "\n".join(lines)


def format_matlab_handoff(config: RxRuntimeConfig, *, data_path: Path, metadata_path: Path) -> str:
    """生成交接给 MATLAB 处理阶段的关键参数摘要。

    MATLAB 读取 .sc16 文件时需要知道数据格式、采样率、中心频率等参数，
    这些参数在 .json 元数据文件中也有记录，此函数以更简洁的格式
    在终端输出，方便操作员快速确认后续处理所需信息。

    参数：
        config:        运行时配置。
        data_path:     .sc16 数据文件路径。
        metadata_path: .json 元数据文件路径。

    返回：
        多行字符串，格式为 key=value 对。
    """
    return "\n".join(
        [
            "=" * 60,
            "MATLAB 交接摘要",
            "=" * 60,
            f"sample_format=sc16",                              # IQ 样本格式
            f"complex_layout=iq_int16_interleaved_le",         # 字节布局：I/Q 交错，小端序 int16
            f"sample_rate_hz={config.sample_rate_hz}",
            f"center_freq_hz={config.center_freq_hz}",
            f"duration_s={config.duration_s}",
            f"capture_mode={config.capture_mode}",
            f"chunk_duration_s={config.chunk_duration_s}",
            f"expected_prn={config.prn_id}",                   # MATLAB 捕获时要搜索的 PRN
            f"data_file={data_path}",
            f"metadata_file={metadata_path}",
        ]
    )


__all__ = [
    "DEFAULT_OUTPUT_BASE_DIR",
    "RxRuntimeConfig",
    "SUPPORTED_PRN_MAX",
    "SUPPORTED_PRN_MIN",
    "apply_overrides",
    "build_timestamped_capture_stem",
    "format_capture_tag",
    "format_capture_report",
    "format_matlab_handoff",
    "load_rx_runtime_config",
    "resolve_chunk_capture_paths",
    "resolve_capture_paths",
    "resolve_output_stem_path",
]
