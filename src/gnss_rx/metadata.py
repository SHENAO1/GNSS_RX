from __future__ import annotations

from dataclasses import asdict, dataclass
from pathlib import Path
import json

from gnss_rx.runtime import RxRuntimeConfig


@dataclass(frozen=True)
class CaptureMetadata:
    # 这是 v1 刻意保持的最小 MATLAB 交接约定。后续阶段可以在不改变
    # 原始 IQ 文件格式的前提下，逐步扩展到 SigMF、更完整的硬件来源
    # 信息或共享时钟元数据。
    sample_format: str
    complex_layout: str
    sample_rate_hz: float
    center_freq_hz: float
    duration_s: float
    samples_captured: int
    rx_gain_db: float
    bandwidth_hz: float | None
    antenna: str
    usrp_addr: str
    zero_if: bool
    signal_mode: str
    prn_id: int
    # True 时表示对应 TX 端发射了 PRN 1~32 叠加信号，prn_id 字段此时仅作兼容保留。
    all_prns: bool
    # 多星场景下记录实际叠加的 PRN 编号列表；单星场景下为 None。
    prn_ids: list | None
    tx_profile_reference: str
    data_file: str


def build_capture_metadata(config: RxRuntimeConfig, *, samples_captured: int, data_path: Path) -> CaptureMetadata:
    return CaptureMetadata(
        sample_format="sc16",
        complex_layout="iq_int16_interleaved_le",
        sample_rate_hz=config.sample_rate_hz,
        center_freq_hz=config.center_freq_hz,
        duration_s=config.duration_s,
        samples_captured=samples_captured,
        rx_gain_db=config.rx_gain_db,
        bandwidth_hz=config.bandwidth_hz,
        antenna=config.antenna,
        usrp_addr=config.usrp_addr,
        zero_if=True,
        signal_mode=config.signal_mode,
        prn_id=config.prn_id,
        all_prns=config.all_prns,
        prn_ids=list(range(1, 33)) if config.all_prns else None,
        tx_profile_reference=config.tx_profile_reference,
        data_file=str(data_path.name),
    )


def write_metadata_json(path: str | Path, metadata: CaptureMetadata) -> None:
    Path(path).write_text(json.dumps(asdict(metadata), indent=2, sort_keys=True), encoding="utf-8")


__all__ = ["CaptureMetadata", "build_capture_metadata", "write_metadata_json"]
