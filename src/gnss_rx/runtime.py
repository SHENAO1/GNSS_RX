from __future__ import annotations

import os
from datetime import datetime
from dataclasses import asdict, dataclass, replace
from pathlib import Path
from typing import Any

from gnss_rx.utils.io import load_yaml_file

DEFAULT_OUTPUT_BASE_DIR = os.environ.get(
    "GNSS_RX_DATA_DIR",
    "/mnt/hgfs/GongXiangDocument/GNSS_RX_Data",
)
TIMESTAMP_FORMAT = "%Y%m%d_%H%M%S"
DATE_DIRECTORY_FORMAT = "%Y_%m_%d"


@dataclass(frozen=True)
class RxRuntimeConfig:
    usrp_addr: str = "type=b200"
    center_freq_hz: float = 100e6
    sample_rate_hz: float = 4.092e6
    rx_gain_db: float = 20.0
    bandwidth_hz: float | None = None
    antenna: str = "RX2"
    duration_s: float = 2.0
    output_base_dir: str = DEFAULT_OUTPUT_BASE_DIR
    use_timestamped_stem: bool = True
    output_stem: str | None = None
    clock_source: str = "internal"
    time_source: str = "internal"
    signal_mode: str = "spread"
    prn_id: int = 1
    tx_profile_reference: str = "../gnss_tx/configs/tx_b210_visible_spectrum.yaml"

    def validate(self) -> "RxRuntimeConfig":
        if self.center_freq_hz <= 0:
            raise ValueError("center_freq_hz 必须大于 0。")
        if self.sample_rate_hz <= 0:
            raise ValueError("sample_rate_hz 必须大于 0。")
        if self.duration_s <= 0:
            raise ValueError("duration_s 必须大于 0。")
        if self.rx_gain_db < 0:
            raise ValueError("rx_gain_db 必须大于等于 0。")
        if self.bandwidth_hz is not None and self.bandwidth_hz <= 0:
            raise ValueError("bandwidth_hz 在提供时必须大于 0。")
        if not self.antenna:
            raise ValueError("antenna 不能为空。")
        if self.signal_mode not in {"spread", "tone"}:
            raise ValueError("signal_mode 必须是以下之一：spread、tone。")
        if self.prn_id != 1:
            raise NotImplementedError("v1 目前只支持 PRN1 的采集元数据。")
        if not self.output_base_dir:
            raise ValueError("output_base_dir 不能为空。")
        if self.output_stem is not None and not self.output_stem:
            raise ValueError("output_stem 在提供时不能为空。")
        if not self.use_timestamped_stem and self.output_stem is None:
            raise ValueError("当 use_timestamped_stem 为 false 时，必须提供 output_stem。")
        return self

    @property
    def capture_samples(self) -> int:
        return int(round(self.sample_rate_hz * self.duration_s))


def load_rx_runtime_config(path: str | Path) -> RxRuntimeConfig:
    raw = load_yaml_file(path)
    if "bandwidth_hz" not in raw and "sample_rate_hz" in raw:
        raw["bandwidth_hz"] = float(raw["sample_rate_hz"])
    return RxRuntimeConfig(**raw).validate()


def apply_overrides(config: RxRuntimeConfig, **overrides: Any) -> RxRuntimeConfig:
    effective: dict[str, Any] = {}
    for key, value in overrides.items():
        if value is not None:
            effective[key] = value

    candidate = replace(config, **effective)
    if "bandwidth_hz" not in effective and "sample_rate_hz" in effective:
        candidate = replace(candidate, bandwidth_hz=candidate.sample_rate_hz)
    return candidate.validate()


def format_capture_tag(value: float, *, keep_decimal: bool = False) -> str:
    if float(value).is_integer() and not keep_decimal:
        return str(int(round(float(value))))

    text = format(float(value), "f")
    if "." in text:
        text = text.rstrip("0").rstrip(".")
    if keep_decimal and "." not in text:
        text = f"{text}.0"
    return text.replace("-", "m").replace(".", "p")


def build_timestamped_capture_stem(config: RxRuntimeConfig, when: datetime) -> str:
    timestamp = when.strftime(TIMESTAMP_FORMAT)
    return "_".join(
        [
            timestamp,
            "rawiq",
            "sc16",
            "zeroif",
            f"prn{config.prn_id}",
            config.signal_mode,
            f"sr{format_capture_tag(config.sample_rate_hz)}",
            f"cf{format_capture_tag(config.center_freq_hz)}",
            f"dur{format_capture_tag(config.duration_s, keep_decimal=True)}s",
        ]
    )


def resolve_output_stem_path(project_root: Path, config: RxRuntimeConfig, when: datetime | None = None) -> Path:
    if config.output_stem is not None:
        stem_path = Path(config.output_stem)
        if not stem_path.is_absolute():
            stem_path = project_root / stem_path
        return stem_path

    capture_time = when if when is not None else datetime.now()
    base_dir = Path(config.output_base_dir)
    if not base_dir.is_absolute():
        base_dir = project_root / base_dir

    dated_dir = base_dir / capture_time.strftime("%Y") / capture_time.strftime(DATE_DIRECTORY_FORMAT)
    stem = build_timestamped_capture_stem(config, capture_time)
    return dated_dir / stem / stem


def resolve_capture_paths(project_root: Path, config: RxRuntimeConfig, when: datetime | None = None) -> tuple[Path, Path]:
    stem_path = resolve_output_stem_path(project_root, config, when=when)
    return stem_path.with_suffix(".sc16"), stem_path.with_suffix(".json")


def format_capture_report(config: RxRuntimeConfig, *, data_path: Path, metadata_path: Path) -> str:
    lines = [
        "=" * 60,
        "GNSS_RX 采集配置",
        "=" * 60,
    ]
    for key, value in asdict(config).items():
        lines.append(f"{key}={value}")
    lines.extend(
        [
            f"capture_samples={config.capture_samples}",
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
    return "\n".join(
        [
            "=" * 60,
            "MATLAB 交接摘要",
            "=" * 60,
            f"sample_format=sc16",
            f"complex_layout=iq_int16_interleaved_le",
            f"sample_rate_hz={config.sample_rate_hz}",
            f"center_freq_hz={config.center_freq_hz}",
            f"duration_s={config.duration_s}",
            f"expected_prn={config.prn_id}",
            f"data_file={data_path}",
            f"metadata_file={metadata_path}",
        ]
    )


__all__ = [
    "DEFAULT_OUTPUT_BASE_DIR",
    "RxRuntimeConfig",
    "apply_overrides",
    "build_timestamped_capture_stem",
    "format_capture_tag",
    "format_capture_report",
    "format_matlab_handoff",
    "load_rx_runtime_config",
    "resolve_capture_paths",
    "resolve_output_stem_path",
]
