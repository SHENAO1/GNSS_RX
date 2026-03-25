from __future__ import annotations

from pathlib import Path
import subprocess

from gnss_rx.runtime import RxRuntimeConfig
from gnss_rx.writer import Sc16CaptureSink

try:
    from gnuradio import blocks, gr, uhd
except ImportError:  # pragma: no cover - optional in some environments
    blocks = None
    gr = None
    uhd = None

HAVE_GNURADIO = gr is not None
HAVE_UHD = HAVE_GNURADIO and uhd is not None
_TopBlockBase = gr.top_block if HAVE_GNURADIO else object


def uhd_find_devices_output() -> str:
    try:
        completed = subprocess.run(
            ["uhd_find_devices"],
            check=False,
            capture_output=True,
            text=True,
        )
    except FileNotFoundError:
        return ""
    return (completed.stdout + completed.stderr).strip()


def is_uhd_device_available() -> bool:
    output = uhd_find_devices_output()
    lowered = output.lower()
    return "no uhd devices found" not in lowered and "device" in lowered


def create_usrp_source(config: RxRuntimeConfig):
    if not HAVE_UHD:
        raise RuntimeError("当前 Python 环境中没有可用的 GNU Radio UHD 绑定。")

    source = uhd.usrp_source(
        ",".join(part for part in [config.usrp_addr] if part),
        uhd.stream_args(cpu_format="fc32", otw_format="sc16", channels=[0]),
    )
    source.set_samp_rate(float(config.sample_rate_hz))
    source.set_center_freq(float(config.center_freq_hz), 0)
    source.set_gain(float(config.rx_gain_db), 0)
    source.set_antenna(str(config.antenna), 0)
    if config.bandwidth_hz is not None:
        source.set_bandwidth(float(config.bandwidth_hz), 0)
    if hasattr(source, "set_clock_source"):
        try:
            source.set_clock_source(str(config.clock_source), 0)
        except TypeError:
            source.set_clock_source(str(config.clock_source))
    if hasattr(source, "set_time_source"):
        try:
            source.set_time_source(str(config.time_source), 0)
        except TypeError:
            source.set_time_source(str(config.time_source))
    return source


class ZeroIfCaptureTopBlock(_TopBlockBase):
    def __init__(self, *, config: RxRuntimeConfig, output_path: str | Path, source_block=None, writer_sink=None) -> None:
        if not HAVE_GNURADIO:
            raise RuntimeError("当前 Python 环境中无法使用 GNU Radio。")

        super().__init__("gnss_rx_zero_if_capture")
        self.config = config
        self.source = source_block if source_block is not None else create_usrp_source(config)
        self.head = blocks.head(gr.sizeof_gr_complex, config.capture_samples)
        # 保持主分支原始不变，便于离线分析结果可复现。未来若增加预览、
        # 去直流、抽 decimation 或实时捕获分支，应从同一信源分叉，
        # 而不是直接修改 v1 的录制路径。
        self.writer_sink = writer_sink if writer_sink is not None else Sc16CaptureSink(output_path)

        self.connect(self.source, self.head, self.writer_sink)


def build_capture_top_block(*, config: RxRuntimeConfig, output_path: str | Path, source_block=None):
    sink = Sc16CaptureSink(output_path)
    tb = ZeroIfCaptureTopBlock(config=config, output_path=output_path, source_block=source_block, writer_sink=sink)
    return tb, sink


__all__ = [
    "HAVE_GNURADIO",
    "HAVE_UHD",
    "ZeroIfCaptureTopBlock",
    "build_capture_top_block",
    "create_usrp_source",
    "is_uhd_device_available",
    "uhd_find_devices_output",
]
