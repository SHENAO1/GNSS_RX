"""GNU Radio 采集流图测试。

GNU Radio 是一个开源的软件无线电框架，用"流图"（flowgraph）描述信号处理管道：
  - 数据源（Source）产生或接收 IQ 样本
  - 各种处理块（Block）对信号进行变换
  - 数据汇（Sink）将结果写入文件或设备

这里测试的是 ZeroIfCaptureTopBlock：
  - 真实使用时，Source 是 USRP SDR 硬件
  - 测试时，用 vector_source_c（向量数据源）代替硬件，注入已知样本，
    验证流图能正确地把这些样本写入 SC16 文件

如果当前环境没有安装 GNU Radio，该测试文件中的所有测试会被自动跳过。
"""

import tempfile       # 临时目录，测试后自动清理
import unittest       # Python 内置单元测试框架
from pathlib import Path  # 文件路径工具

import numpy as np    # 数值计算，处理 IQ 样本数组

# 尝试导入 GNU Radio 的 blocks 模块；若未安装则设为 None
try:
    from gnuradio import blocks
except ImportError:  # pragma: no cover - optional in some environments
    blocks = None

# 导入被测模块
from gnss_rx.flowgraph import HAVE_GNURADIO, ZeroIfCaptureTopBlock
from gnss_rx.runtime import RxRuntimeConfig


# @unittest.skipUnless(condition, reason)：条件不满足时跳过整个测试类
# 这里若 GNU Radio 未安装（HAVE_GNURADIO=False），则跳过所有流图测试
@unittest.skipUnless(HAVE_GNURADIO, "流图测试需要 GNU Radio。")
class TestCaptureFlowgraph(unittest.TestCase):
    """测试 GNU Radio 流图能否正确采集并保存 IQ 数据。"""

    def test_top_block_can_capture_from_vector_source(self) -> None:
        """验证流图可以从向量数据源读取样本并写入 SC16 文件。

        测试步骤：
          1. 准备 3 个已知的 complex64 采样点（替代真实 SDR 硬件输入）
          2. 创建最小化的运行时配置（采样率 3 Hz，采集 1 秒 → 3 个样本）
          3. 构建流图：向量数据源 → ZeroIfCaptureTopBlock → SC16 文件
          4. 运行流图（tb.run() 会阻塞直到所有样本处理完）
          5. 关闭写入器，确保缓冲区完全刷写到磁盘
          6. 用 numpy 读回二进制文件，验证内容正确

        SC16 格式每个采样点占 2 个 int16 值（I 和 Q 各一个），
        所以 3 个采样点 → raw 数组大小为 6。
        """
        # 3 个测试用的复数采样点（complex64 = 32位浮点实部 + 32位浮点虚部）
        samples = np.array([0.25 + 0.0j, -0.25 + 0.5j, 0.0 - 0.5j], dtype=np.complex64)

        # 最小化配置：采样率 3 Hz，带宽 3 Hz，采集 1 秒（即 3 个样本）
        config = RxRuntimeConfig(
            sample_rate_hz=3.0,
            bandwidth_hz=3.0,
            duration_s=1.0,
            output_stem="results/captures/test_capture",
        )

        with tempfile.TemporaryDirectory() as tmpdir:
            output_path = Path(tmpdir) / "capture.sc16"

            # vector_source_c 是 GNU Radio 内置的测试数据源：
            #   参数1: 数据列表（把 numpy 数组转为 Python 列表）
            #   参数2: False = 不循环重复，播放完就停止
            #   参数3: 1 = 向量长度（每次输出 1 个样本）
            #   参数4: [] = 无附加标签
            source = blocks.vector_source_c(samples.tolist(), False, 1, [])

            # 构建流图：传入配置、输出路径和数据源
            tb = ZeroIfCaptureTopBlock(config=config, output_path=output_path, source_block=source)

            # 运行流图直到数据源耗尽（3 个样本全部处理完）
            tb.run()

            # 关闭写入器，确保所有缓冲数据写入磁盘
            tb.writer_sink.close()

            # 以小端 int16 格式读取原始二进制文件内容
            raw = np.fromfile(output_path, dtype="<i2")

        # 写入器应记录写入了 3 个采样点
        self.assertEqual(tb.writer_sink.samples_written, 3)

        # SC16 格式：每个复数采样 = 2 个 int16，所以 3 个采样 → 6 个 int16 值
        self.assertEqual(raw.size, 6)


if __name__ == "__main__":
    unittest.main()
