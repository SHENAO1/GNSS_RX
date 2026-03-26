"""
writer.py — SC16 格式 IQ 数据写入器

这个模块负责将 GNU Radio 流图中的复数浮点样本（fc32）转换并写入到
SC16 格式的二进制文件中。

背景知识：
  • fc32（Float Complex 32-bit）：GNU Radio 内部使用的复数格式，
    每个样本为两个 float32（I、Q 各 4 字节），共 8 字节/样本。
  • SC16（Signed Complex 16-bit）：UHD 和 MATLAB 常用的紧凑格式，
    每个样本为两个 int16（I、Q 各 2 字节），共 4 字节/样本，
    存储空间只有 fc32 的一半。
  • 交错存储（interleaved）：I 和 Q 交替排列在同一数组中：
    [I0, Q0, I1, Q1, I2, Q2, ...]
  • 小端序（little-endian, LE）：x86/x86_64 平台的默认字节序，
    MATLAB 读取时也以小端序解释 int16。

GNU Radio Sync Block 简介：
  GNU Radio 的信号处理模块分两大类：
    - Source Block：产生数据（如 USRP 接收机）
    - Sink Block：消费数据（如本模块的 Sc16CaptureSink）
  Sync Block 是同步块的基类，意味着输入和输出的样本数量是 1:1 对应的
  （这里 out_sig=None 表示没有输出，只有输入）。
  GNU Radio 框架会反复调用 work() 方法，每次传入一批新样本。
"""

from __future__ import annotations

from pathlib import Path

import numpy as np  # NumPy：高性能数值计算库，用于向量化的格式转换

try:
    from gnuradio import gr  # GNU Radio Python 绑定
except ImportError:  # pragma: no cover - 某些开发环境中 GNU Radio 是可选依赖。
    gr = None

HAVE_GNURADIO = gr is not None  # 标记当前环境是否有 GNU Radio，影响类的基类

# 如果有 GNU Radio，Sc16CaptureSink 继承自真正的 gr.sync_block；
# 否则继承自普通的 object（用于单元测试，不需要完整的 GNU Radio 环境）。
_SyncBlockBase = gr.sync_block if HAVE_GNURADIO else object

# SC16 格式的量化比例因子：将 [-1.0, 1.0] 的浮点数映射到 [-32767, 32767]。
# 注意：这里用 32767 而不是 32768，是为了保证正负对称，
# 同时也是 UHD 默认使用的约定（避免整型溢出）。
SC16_SCALE = 32767.0


# ──────────────────────────────────────────────────────────────
# 纯函数：格式转换（可独立使用，无需 GNU Radio）
# ──────────────────────────────────────────────────────────────

def complex_to_sc16_interleaved(samples: np.ndarray) -> np.ndarray:
    """将复数浮点样本数组（fc32）转换为 SC16 交错整数数组。

    转换步骤：
      1. 确保输入类型为 complex64（fc32）
      2. 分别提取 I（实部）和 Q（虚部）
      3. 将 I/Q 各自截幅到 [-1.0, 1.0]，防止乘以 SC16_SCALE 后溢出
      4. 乘以 32767 并四舍五入，转换为 int16
      5. 按 [I0, Q0, I1, Q1, ...] 顺序交错排列

    参数：
        samples: 复数样本数组，dtype 应为 complex64，形状 (N,)。

    返回：
        int16 交错数组，形状 (2N,)，顺序为 [I0, Q0, I1, Q1, ...]。

    示例：
        samples = np.array([0.5 + 0.3j, -0.1 + 0.9j], dtype=np.complex64)
        sc16 = complex_to_sc16_interleaved(samples)
        # sc16 ≈ [16383, 9830, -3276, 29491]
    """
    complex_samples = np.asarray(samples, dtype=np.complex64)

    # np.clip 将数组元素限制在 [min, max] 范围内，超出部分截断到边界值
    clipped_i = np.clip(np.real(complex_samples), -1.0, 1.0)  # 提取并截幅实部
    clipped_q = np.clip(np.imag(complex_samples), -1.0, 1.0)  # 提取并截幅虚部

    # 预分配交错数组：大小为样本数的两倍，类型为 int16
    interleaved = np.empty(complex_samples.size * 2, dtype=np.int16)

    # 偶数索引（0, 2, 4, ...）存放 I 分量
    interleaved[0::2] = np.rint(clipped_i * SC16_SCALE).astype(np.int16)
    # 奇数索引（1, 3, 5, ...）存放 Q 分量
    interleaved[1::2] = np.rint(clipped_q * SC16_SCALE).astype(np.int16)

    return interleaved


def write_sc16_file(path: str | Path, samples: np.ndarray) -> int:
    """将复数样本数组以 SC16 格式写入二进制文件（离线批量写入版本）。

    与 Sc16CaptureSink 不同，这个函数一次性处理整个样本数组，
    适合在 GNU Radio 流图之外（如后处理脚本或测试代码）使用。

    参数：
        path:    输出文件路径（.sc16 扩展名），如果父目录不存在会自动创建。
        samples: 要写入的复数样本，dtype 应为 complex64。

    返回：
        成功写入的样本数（即 samples.size）。

    文件格式：
        小端序 int16 交错二进制，字节布局：
        [I0_lo, I0_hi, Q0_lo, Q0_hi, I1_lo, I1_hi, Q1_lo, Q1_hi, ...]
    """
    output_path = Path(path)
    output_path.parent.mkdir(parents=True, exist_ok=True)  # 递归创建目录

    interleaved = complex_to_sc16_interleaved(samples)

    # "<i2"：< 表示小端序，i 表示有符号整数，2 表示 2 字节（即 int16）
    # copy=False：如果类型已经匹配则不复制，节省内存
    output_path.write_bytes(interleaved.astype("<i2", copy=False).tobytes())

    return int(samples.size)


# ──────────────────────────────────────────────────────────────
# GNU Radio Sink Block：流式写入
# ──────────────────────────────────────────────────────────────

class Sc16CaptureSink(_SyncBlockBase):
    """GNU Radio 同步 Sink 块：将输入的复数样本实时写入 SC16 文件。

    这个类是整个采集流图的终点。GNU Radio 框架会在后台线程中反复
    调用 work() 方法，每次传入一小批新到达的样本，直到上游的
    blocks.head 触发流图停止信号。

    流图连接示意：
        USRP Source (fc32) → blocks.head (限制总样本数) → Sc16CaptureSink (写文件)

    设计说明：
        v1 直接写原始 SC16，是因为它与 UHD 风格的数据流很好对应，同时也能
        保持采集文件足够紧凑。后续阶段可以在同样的 sink 接口下扩展 fc32、
        分段录制或滚动采集等策略。

    属性：
        path:            输出文件路径（Path 对象）。
        handle:          已打开的二进制文件句柄（wb 模式）。
        samples_written: 迄今已写入的样本总数，可在采集结束后读取。
    """

    def __init__(self, path: str | Path) -> None:
        """初始化文件写入器，打开目标文件准备写入。

        参数：
            path: 输出文件的路径（.sc16），父目录不存在时自动创建。
        """
        self.path = Path(path)
        self.path.parent.mkdir(parents=True, exist_ok=True)  # 确保目录存在

        # 以二进制写入模式（"wb"）打开文件，文件句柄保持打开直到 close() 被调用
        self.handle = self.path.open("wb")
        self.samples_written = 0  # 已写入样本计数器，初始为 0

        if HAVE_GNURADIO:
            # 向 GNU Radio 框架注册此块的名称和 I/O 信号类型：
            #   in_sig=[np.complex64]  → 接受一路 complex64 输入流
            #   out_sig=None           → 没有输出流（这是一个 Sink）
            super().__init__(name="sc16_capture_sink", in_sig=[np.complex64], out_sig=None)

    def work(self, input_items, output_items) -> int:
        """GNU Radio 框架回调：处理一批新到达的样本。

        这个方法由 GNU Radio 调度器自动调用，不应在用户代码中手动调用。
        每次调用时，input_items[0] 包含新到达的若干复数样本。

        参数：
            input_items:  列表，input_items[0] 是当前批次的 complex64 样本数组。
            output_items: 列表，此 Sink 块没有输出，故此参数为空列表。

        返回：
            成功处理的样本数，告知框架消费了多少输入。
            返回 0 表示本次没有消费（通常用于流量控制，这里不应发生）。
        """
        samples = np.asarray(input_items[0], dtype=np.complex64)

        # 防御性检查：如果框架传入空数组（极少发生）则跳过
        if samples.size == 0:
            return 0

        # 将 fc32 转换为 SC16 交错格式并追加写入文件
        interleaved = complex_to_sc16_interleaved(samples)
        self.handle.write(interleaved.astype("<i2", copy=False).tobytes())

        # 更新已写入样本计数（注意：这里累加的是复数样本数，不是 int16 个数）
        self.samples_written += int(samples.size)

        # 告知 GNU Radio 框架已消费了 len(samples) 个输入样本
        return len(samples)

    def close(self) -> None:
        """刷新并关闭文件句柄，确保所有数据写入磁盘。

        流图停止后应显式调用此方法。如果文件已经关闭则什么都不做
        （防止重复关闭导致错误）。
        """
        if not self.handle.closed:
            self.handle.flush()  # 将内核缓冲区中的数据强制写入磁盘
            self.handle.close()


__all__ = ["HAVE_GNURADIO", "SC16_SCALE", "Sc16CaptureSink", "complex_to_sc16_interleaved", "write_sc16_file"]
