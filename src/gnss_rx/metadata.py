"""
metadata.py — 采集元数据定义与序列化

这个模块定义了伴随每次采集产生的 .json 元数据文件的数据结构。
元数据文件与 .sc16 数据文件配套使用，记录了重建信号所需的
全部参数（采样率、中心频率、格式说明等）。

为什么需要元数据文件？
  .sc16 是纯二进制文件，里面只有密密麻麻的数字，没有任何自描述信息。
  如果不知道采样率是多少、中心频率是多少、字节是大端还是小端，
  就无法正确解读文件内容。元数据文件解决了这个问题。

与 SigMF 标准的关系：
  SigMF（Signal Metadata Format）是业界通用的 IQ 元数据标准，
  本项目 v1 使用的是最小化自定义格式，未来可以迁移到 SigMF。
"""

from __future__ import annotations

from dataclasses import asdict, dataclass  # dataclass：自动生成 __init__ 等方法
from pathlib import Path
import json  # Python 标准库：JSON 序列化与反序列化

from gnss_rx.runtime import RxRuntimeConfig  # 运行时配置（包含所有采集参数）


@dataclass(frozen=True)  # frozen=True：创建后不可修改，保持元数据的一致性
class CaptureMetadata:
    """描述一次 GNSS IQ 采集的完整元数据。

    这是一个不可变数据类，对应磁盘上的 .json 文件。
    所有字段在写入文件后不应被修改，以保证可重现性。

    这是 v1 刻意保持的最小 MATLAB 交接约定。后续阶段可以在不改变
    原始 IQ 文件格式的前提下，逐步扩展到 SigMF、更完整的硬件来源
    信息或共享时钟元数据。

    字段说明：
        sample_format:         数据格式标识符，固定为 "sc16"。
        complex_layout:        字节布局描述，固定为 "iq_int16_interleaved_le"
                               （I/Q 交错，小端序 int16）。
        sample_rate_hz:        采样率（Hz），MATLAB 读取时必须使用此值。
        center_freq_hz:        射频中心频率（Hz）。
        duration_s:            配置的采集时长（秒）。
        samples_captured:      实际写入磁盘的样本数（可能略少于理论值）。
        rx_gain_db:            接收增益（dB）。
        bandwidth_hz:          射频带宽（Hz），None 表示使用硬件默认值。
        antenna:               天线端口名称（如 "RX2"）。
        usrp_addr:             USRP 设备地址字符串（如 "type=b200"）。
        zero_if:               是否为零中频采集模式，固定为 True（v1 只支持零中频）。
        signal_mode:           TX 端信号模式，"spread" 或 "tone"。
        prn_id:                目标 GPS PRN 编号（1~32）。
        all_prns:              True 表示 TX 端发射了 PRN 1~32 全部叠加信号；
                               此时 prn_id 字段仅作兼容保留。
        prn_ids:               多星场景下实际叠加的 PRN 编号列表；
                               单星场景下为 None。
        tx_profile_reference:  TX 端配置文件的相对路径，便于追溯发射参数。
        data_file:             对应的 .sc16 数据文件名（仅文件名，不含目录）。
    """

    # ── 信号格式描述 ───────────────────────────────────────────
    sample_format: str        # 例如 "sc16"
    complex_layout: str       # 例如 "iq_int16_interleaved_le"

    # ── 采集参数 ───────────────────────────────────────────────
    sample_rate_hz: float
    center_freq_hz: float
    duration_s: float
    samples_captured: int     # 实际采集到的样本数（受硬件/系统影响可能略有偏差）
    rx_gain_db: float
    bandwidth_hz: float | None
    antenna: str
    usrp_addr: str

    # ── 信号描述 ───────────────────────────────────────────────
    zero_if: bool             # 是否零中频（v1 固定为 True）
    signal_mode: str          # "spread"（扩频）或 "tone"（单音）
    prn_id: int               # 主目标 PRN，all_prns=True 时仅作兼容保留

    # True 时表示对应 TX 端发射了 PRN 1~32 叠加信号，prn_id 字段此时仅作兼容保留。
    all_prns: bool

    # 多星场景下记录实际叠加的 PRN 编号列表；单星场景下为 None。
    prn_ids: list | None

    # ── 来源追溯 ───────────────────────────────────────────────
    tx_profile_reference: str  # TX 端配置文件路径（相对路径），方便事后对照
    data_file: str             # 对应的 .sc16 文件名（仅 basename）


def build_capture_metadata(config: RxRuntimeConfig, *, samples_captured: int, data_path: Path) -> CaptureMetadata:
    """根据运行时配置和实际采集结果，构造 CaptureMetadata 实例。

    这个函数是 CaptureMetadata 的"工厂方法"，集中处理
    从 config 字段到 metadata 字段的映射逻辑，避免散落在各处。

    参数：
        config:           本次采集使用的运行时配置。
        samples_captured: 实际写入磁盘的样本总数（从 Sc16CaptureSink.samples_written 获取）。
        data_path:        .sc16 数据文件的完整路径，用于提取文件名。

    返回：
        填充完整的 CaptureMetadata 实例，可直接传给 write_metadata_json。

    示例：
        metadata = build_capture_metadata(
            config, samples_captured=sink.samples_written, data_path=sc16_path
        )
    """
    return CaptureMetadata(
        # 固定常量：v1 格式约定
        sample_format="sc16",
        complex_layout="iq_int16_interleaved_le",

        # 从 config 直接映射的采集参数
        sample_rate_hz=config.sample_rate_hz,
        center_freq_hz=config.center_freq_hz,
        duration_s=config.duration_s,
        samples_captured=samples_captured,    # 来自 sink 的实际计数
        rx_gain_db=config.rx_gain_db,
        bandwidth_hz=config.bandwidth_hz,
        antenna=config.antenna,
        usrp_addr=config.usrp_addr,

        # 信号描述
        zero_if=True,                         # v1 只有零中频模式
        signal_mode=config.signal_mode,
        prn_id=config.prn_id,
        all_prns=config.all_prns,

        # all_prns=True 时生成 [1..32] 列表，否则为 None
        prn_ids=list(range(1, 33)) if config.all_prns else None,

        # 来源追溯
        tx_profile_reference=config.tx_profile_reference,
        data_file=str(data_path.name),        # 只取文件名（如 "stem.sc16"），不含目录
    )


def write_metadata_json(path: str | Path, metadata: CaptureMetadata) -> None:
    """将 CaptureMetadata 序列化为 JSON 并写入磁盘。

    生成的 JSON 文件便于人工查阅，也方便 MATLAB / Python 脚本读取。

    参数：
        path:     输出的 .json 文件路径。
        metadata: 要写入的元数据对象。

    输出文件格式（indent=2 美化，sort_keys=True 按字母序排列字段）：
        {
          "all_prns": false,
          "antenna": "RX2",
          "center_freq_hz": 100000000.0,
          ...
        }
    """
    # asdict 将 frozen dataclass 转换为普通 Python 字典
    # json.dumps 将字典序列化为 JSON 字符串，indent=2 让输出更易读
    Path(path).write_text(
        json.dumps(asdict(metadata), indent=2, sort_keys=True),
        encoding="utf-8",
    )


__all__ = ["CaptureMetadata", "build_capture_metadata", "write_metadata_json"]
