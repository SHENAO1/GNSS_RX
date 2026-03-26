"""SC16 转换与文件写入测试。

SC16 是一种常见的 IQ 采样数据格式：
  - I（同相分量）和 Q（正交分量）交替存储
  - 每个分量用 16 位有符号整数（int16）表示
  - 浮点复数（-1.0 ~ +1.0）被缩放映射到 int16 范围（-32767 ~ +32767）
"""

import tempfile       # 用于创建临时目录，测试完自动删除，不留垃圾文件
import unittest       # Python 内置的单元测试框架
from pathlib import Path  # 跨平台的文件路径操作工具

import numpy as np    # 数值计算库，处理采样数组

# 从项目模块导入被测函数
from gnss_rx.writer import complex_to_sc16_interleaved, write_sc16_file


class TestSc16Writer(unittest.TestCase):
    """测试 SC16 格式转换和文件写入的正确性。"""

    def test_complex_to_sc16_interleaved_preserves_iq_order_and_clips(self) -> None:
        """验证浮点复数转 SC16 时：IQ 顺序正确，超出范围的值会被截断（clip）。

        输入两个复数采样：
          - 0.5 + 0.25j：I=0.5, Q=0.25，均在 [-1, 1] 范围内，正常缩放
          - -1.0 + 1.5j：I=-1.0 正常缩放，Q=1.5 超出范围，应被截断为最大值 32767

        缩放公式：int16_value = float_value × 32767（结果取整并限幅）
          0.5  × 32767 = 16383.5 → 16384（四舍五入或 floor，取决于实现）
          0.25 × 32767 = 8191.75 → 8192
          -1.0 × 32767 = -32767
          1.5  超出范围  → 32767（截断到最大值）

        输出数组为 I0, Q0, I1, Q1 的顺序交替排列。
        """
        samples = np.array([0.5 + 0.25j, -1.0 + 1.5j], dtype=np.complex64)
        interleaved = complex_to_sc16_interleaved(samples)

        # 期望输出：[I0=16384, Q0=8192, I1=-32767, Q1=32767（截断）]
        expected = np.array([16384, 8192, -32767, 32767], dtype=np.int16)
        np.testing.assert_array_equal(interleaved, expected)

    def test_write_sc16_file_writes_little_endian_interleaved_int16(self) -> None:
        """验证写入磁盘的二进制文件是小端字节序的交替 int16 格式。

        小端（little-endian）是 x86 PC 的原生字节序，也是 SC16 格式的标准要求。
        np.fromfile(path, dtype="<i2") 中的 "<i2" 表示：
          "<" = 小端字节序
          "i2" = 2字节有符号整数（即 int16）

        步骤：
          1. 创建两个复数采样
          2. 写入临时文件
          3. 用 numpy 直接读回二进制内容
          4. 比较读回的值与预期是否一致
        """
        samples = np.array([0.25 - 0.5j, -0.25 + 0.5j], dtype=np.complex64)

        # tempfile.TemporaryDirectory() 创建临时文件夹，with 块结束时自动删除
        with tempfile.TemporaryDirectory() as tmpdir:
            path = Path(tmpdir) / "capture.sc16"
            count = write_sc16_file(path, samples)          # 写入文件，返回写入的采样数
            raw = np.fromfile(path, dtype="<i2")            # 直接读取二进制内容

        # 写入了 2 个采样
        self.assertEqual(count, 2)

        # 期望文件内容与手动转换结果一致
        expected = complex_to_sc16_interleaved(samples).astype("<i2", copy=False)
        np.testing.assert_array_equal(raw, expected)


if __name__ == "__main__":
    unittest.main()
