"""
flowgraph.py — GNU Radio 采集流图

这个模块构建并管理用于 GNSS 信号采集的 GNU Radio 流图（Flow Graph）。

GNU Radio 流图简介：
  GNU Radio 是一个开源的软件无线电框架。"流图"是数据处理管道的图形化描述，
  由若干"块"（Block）通过"连接"（connect）组成。数据像水流一样从源头（Source）
  流向终点（Sink）：

      USRP Source ──→ Head Block ──→ Sc16CaptureSink
         ↑                ↑                ↑
     硬件采样        限制采样总数       写入文件

  本模块实现的是最简单的单路径流图，后续可以在同一 Source 后面
  分叉出多路（如预览分支、去直流分支）而不影响主路录制。

UHD（USRP Hardware Driver）：
  UHD 是 Ettus USRP 硬件的官方驱动，GNU Radio 通过 uhd.usrp_source 块
  访问 B210 等硬件，实现实时 IQ 采样。
"""

from __future__ import annotations

from pathlib import Path
import subprocess  # 用于调用系统命令 uhd_find_devices

from gnss_rx.runtime import RxRuntimeConfig   # 采集参数配置
from gnss_rx.writer import Sc16CaptureSink    # SC16 格式文件写入 Sink 块

# ── 可选依赖：GNU Radio 在部分开发环境中不安装 ─────────────────
try:
    from gnuradio import blocks, gr, uhd
except ImportError:  # pragma: no cover - optional in some environments
    blocks = None
    gr = None
    uhd = None

# 这两个标志在其他模块中也会被引用，用于在没有硬件的机器上跳过相关代码
HAVE_GNURADIO = gr is not None           # True：GNU Radio Python 绑定可用
HAVE_UHD = HAVE_GNURADIO and uhd is not None  # True：UHD 模块也可用

# 根据是否有 GNU Radio 动态选择基类：
#   - 有 GNU Radio：继承自 gr.top_block（真正的流图顶层块）
#   - 没有 GNU Radio：继承自 object（用于单元测试，无需硬件）
_TopBlockBase = gr.top_block if HAVE_GNURADIO else object


# ──────────────────────────────────────────────────────────────
# UHD 设备探测函数
# ──────────────────────────────────────────────────────────────

def uhd_find_devices_output() -> str:
    """调用系统命令 uhd_find_devices，返回其标准输出+标准错误的合并文本。

    uhd_find_devices 是 UHD 驱动自带的工具，会扫描当前系统上连接的
    所有 USRP 设备并打印设备信息。

    返回：
        合并后的输出文本（已去除首尾空白）；如果命令不存在则返回空字符串。

    示例输出（有设备时）：
        "[INFO] [UHD] Found 1 device(s): type=b200, serial=ABCD1234"
    示例输出（无设备时）：
        "[ERROR] No UHD Devices Found"
    """
    try:
        completed = subprocess.run(
            ["uhd_find_devices"],
            check=False,       # 不因非零返回码抛出异常（设备未找到时也会非零）
            capture_output=True,  # 捕获 stdout 和 stderr
            text=True,         # 以字符串而非字节返回
        )
    except FileNotFoundError:
        # uhd_find_devices 命令不存在（UHD 未安装）
        return ""
    return (completed.stdout + completed.stderr).strip()


def is_uhd_device_available() -> bool:
    """检测当前系统上是否有可用的 USRP 设备。

    通过解析 uhd_find_devices 的输出文本来判断，逻辑：
      - 输出中包含 "no uhd devices found" → 无设备 → 返回 False
      - 输出中包含 "device" 但不包含上面的否定词 → 有设备 → 返回 True

    返回：
        True：检测到至少一台 USRP 设备；
        False：没有设备或 UHD 未安装。

    使用场景：
        在启动采集前调用此函数，可以给出明确的错误提示，
        而不是让用户面对 GNU Radio 的底层崩溃信息。
    """
    output = uhd_find_devices_output()
    lowered = output.lower()  # 统一转小写，避免大小写差异影响判断
    return "no uhd devices found" not in lowered and "device" in lowered


# ──────────────────────────────────────────────────────────────
# USRP Source 块工厂函数
# ──────────────────────────────────────────────────────────────

def create_usrp_source(config: RxRuntimeConfig):
    """根据配置创建并初始化一个 GNU Radio UHD USRP Source 块。

    USRP Source 块是整个采集流图的数据源头，它持续从硬件读取
    IQ 样本并注入 GNU Radio 数据流。

    参数：
        config: 包含 USRP 地址、中心频率、采样率、增益等参数的配置对象。

    返回：
        已配置好的 uhd.usrp_source 块，可直接插入流图。

    异常：
        RuntimeError: 当前环境没有 GNU Radio UHD 绑定时抛出。

    配置项说明：
        usrp_addr:      设备选择字符串，如 "type=b200" 或 "serial=ABCDEF"
        cpu_format=fc32: GNU Radio 内部使用 complex64（float complex 32-bit）
        otw_format=sc16: Over-the-wire 格式：USB 传输时使用 SC16 节省带宽
        channels=[0]:   使用 0 号通道（B210 有 2 个通道，这里只用第 0 个）
    """
    if not HAVE_UHD:
        raise RuntimeError("当前 Python 环境中没有可用的 GNU Radio UHD 绑定。")

    # 创建 USRP Source 并指定设备地址及数据流参数
    # 增大 USB 接收缓冲区以减少 overflow：
    #   recv_frame_size=4104  — 每帧样本数（默认 ~1024）
    #   num_recv_frames=512   — 缓冲帧数（默认 ~32）
    #   recv_buff_size=33554432 — OS 级 socket 接收缓冲区 32 MB（默认 ~4 MB）
    #     作用：CPU 调度抖动期间（≤数十 ms）能暂存更多数据，减少 overflow 概率
    device_addr = ",".join(
        part for part in [
            config.usrp_addr,
            "recv_frame_size=4104",
            "num_recv_frames=512",
            "recv_buff_size=33554432",
        ] if part
    )
    source = uhd.usrp_source(
        device_addr,
        uhd.stream_args(
            cpu_format="fc32",   # 主机侧（Python/NumPy）使用 float complex32
            otw_format="sc16",   # 硬件→主机 USB 传输使用 SC16（节省带宽）
            channels=[0],        # 只使用通道 0
        ),
    )

    # 逐一应用配置参数，通道号均为 0
    source.set_samp_rate(float(config.sample_rate_hz))         # 采样率
    source.set_center_freq(float(config.center_freq_hz), 0)    # 中心频率，通道 0
    source.set_gain(float(config.rx_gain_db), 0)               # 接收增益，通道 0
    source.set_antenna(str(config.antenna), 0)                 # 天线端口，通道 0

    # 带宽是可选参数，为 None 时不设置（使用硬件默认值）
    if config.bandwidth_hz is not None:
        source.set_bandwidth(float(config.bandwidth_hz), 0)

    # 时钟源：不同版本的 UHD 绑定 API 略有差异，尝试两种调用方式
    if hasattr(source, "set_clock_source"):
        try:
            source.set_clock_source(str(config.clock_source), 0)  # 新版 API（带通道号）
        except TypeError:
            source.set_clock_source(str(config.clock_source))      # 旧版 API（不带通道号）

    # 时间源：同上
    if hasattr(source, "set_time_source"):
        try:
            source.set_time_source(str(config.time_source), 0)
        except TypeError:
            source.set_time_source(str(config.time_source))

    return source


# ──────────────────────────────────────────────────────────────
# 采集流图顶层块
# ──────────────────────────────────────────────────────────────

class ZeroIfCaptureTopBlock(_TopBlockBase):
    """零中频 IQ 采集流图。

    这是整个采集系统的"大脑"，管理从硬件采样到文件写入的完整数据流。

    流图结构：
        source（USRP Source）
            ↓  fc32 复数样本
        head（blocks.head）      ← 采集满 capture_samples 个样本后停止
            ↓  fc32 复数样本
        writer_sink（Sc16CaptureSink）  ← 转换格式并写入 .sc16 文件

    使用方式：
        tb = ZeroIfCaptureTopBlock(config=cfg, output_path="capture.sc16")
        tb.start()   # 启动流图（后台线程开始运行）
        tb.wait()    # 等待流图自然结束（head 计满后自动停止）
        tb.writer_sink.close()  # 关闭文件句柄，确保数据落盘

    参数：
        config:       采集参数配置。
        output_path:  输出 .sc16 文件路径。
        source_block: 可选的自定义 Source 块（测试时用假 Source 替代真实硬件）。
        writer_sink:  可选的自定义 Sink 块（测试时使用）。
    """

    def __init__(
        self,
        *,
        config: RxRuntimeConfig,
        output_path: str | Path,
        source_block=None,   # None → 自动创建 USRP Source
        writer_sink=None,    # None → 自动创建 Sc16CaptureSink
    ) -> None:
        if not HAVE_GNURADIO:
            raise RuntimeError("当前 Python 环境中无法使用 GNU Radio。")

        # 调用 gr.top_block.__init__，向框架注册流图名称
        super().__init__("gnss_rx_zero_if_capture")

        self.config = config

        # Source 块：如果调用者没有传入自定义 Source（如用于测试的模拟源），
        # 则自动创建真实的 USRP Source
        self.source = source_block if source_block is not None else create_usrp_source(config)

        # Head 块：当流过的样本数达到 capture_samples 时，向下游发送"流结束"信号，
        # 整个流图随之停止。这是控制采集时长的关键。
        # gr.sizeof_gr_complex = 8（每个 complex64 样本占 8 字节）
        self.head = blocks.head(gr.sizeof_gr_complex, config.capture_samples)

        # Sink 块：将样本转换为 SC16 格式并写入文件
        # 保持主分支原始不变，便于离线分析结果可复现。未来若增加预览、
        # 去直流、抽 decimation 或实时捕获分支，应从同一信源分叉，
        # 而不是直接修改 v1 的录制路径。
        self.writer_sink = writer_sink if writer_sink is not None else Sc16CaptureSink(output_path)

        # 将三个块串联起来：source → head → writer_sink
        # GNU Radio 中 connect() 建立数据流连接
        self.connect(self.source, self.head, self.writer_sink)


# ──────────────────────────────────────────────────────────────
# 便捷工厂函数
# ──────────────────────────────────────────────────────────────

def build_capture_top_block(*, config: RxRuntimeConfig, output_path: str | Path, source_block=None):
    """创建采集流图并返回 (top_block, sink) 元组。

    这是对 ZeroIfCaptureTopBlock 的简单封装，同时把 Sink 对象单独返回，
    方便调用者在流图结束后读取 sink.samples_written 等状态。

    参数：
        config:       采集参数配置。
        output_path:  输出 .sc16 文件路径。
        source_block: 可选的自定义 Source（测试用）。

    返回：
        (tb, sink) 元组：
            tb:   ZeroIfCaptureTopBlock 实例，可调用 tb.start() / tb.wait()。
            sink: Sc16CaptureSink 实例，采集结束后读取 sink.samples_written。

    示例：
        tb, sink = build_capture_top_block(config=cfg, output_path="capture.sc16")
        tb.start()
        tb.wait()
        sink.close()
        print(f"共采集 {sink.samples_written} 个样本")
    """
    sink = Sc16CaptureSink(output_path)
    tb = ZeroIfCaptureTopBlock(
        config=config,
        output_path=output_path,
        source_block=source_block,
        writer_sink=sink,
    )
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
