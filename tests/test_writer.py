"""SC16 转换与文件写入测试。"""

import tempfile
import unittest
from pathlib import Path

import numpy as np

from gnss_rx.writer import complex_to_sc16_interleaved, write_sc16_file


class TestSc16Writer(unittest.TestCase):
    def test_complex_to_sc16_interleaved_preserves_iq_order_and_clips(self) -> None:
        samples = np.array([0.5 + 0.25j, -1.0 + 1.5j], dtype=np.complex64)
        interleaved = complex_to_sc16_interleaved(samples)
        expected = np.array([16384, 8192, -32767, 32767], dtype=np.int16)
        np.testing.assert_array_equal(interleaved, expected)

    def test_write_sc16_file_writes_little_endian_interleaved_int16(self) -> None:
        samples = np.array([0.25 - 0.5j, -0.25 + 0.5j], dtype=np.complex64)

        with tempfile.TemporaryDirectory() as tmpdir:
            path = Path(tmpdir) / "capture.sc16"
            count = write_sc16_file(path, samples)
            raw = np.fromfile(path, dtype="<i2")

        self.assertEqual(count, 2)
        expected = complex_to_sc16_interleaved(samples).astype("<i2", copy=False)
        np.testing.assert_array_equal(raw, expected)


if __name__ == "__main__":
    unittest.main()
