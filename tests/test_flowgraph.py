"""GNU Radio 采集流图测试。"""

import tempfile
import unittest
from pathlib import Path

import numpy as np
try:
    from gnuradio import blocks
except ImportError:  # pragma: no cover - optional in some environments
    blocks = None

from gnss_rx.flowgraph import HAVE_GNURADIO, ZeroIfCaptureTopBlock
from gnss_rx.runtime import RxRuntimeConfig


@unittest.skipUnless(HAVE_GNURADIO, "流图测试需要 GNU Radio。")
class TestCaptureFlowgraph(unittest.TestCase):
    def test_top_block_can_capture_from_vector_source(self) -> None:
        samples = np.array([0.25 + 0.0j, -0.25 + 0.5j, 0.0 - 0.5j], dtype=np.complex64)
        config = RxRuntimeConfig(
            sample_rate_hz=3.0,
            bandwidth_hz=3.0,
            duration_s=1.0,
            output_stem="results/captures/test_capture",
        )

        with tempfile.TemporaryDirectory() as tmpdir:
            output_path = Path(tmpdir) / "capture.sc16"
            source = blocks.vector_source_c(samples.tolist(), False, 1, [])
            tb = ZeroIfCaptureTopBlock(config=config, output_path=output_path, source_block=source)
            tb.run()
            tb.writer_sink.close()
            raw = np.fromfile(output_path, dtype="<i2")

        self.assertEqual(tb.writer_sink.samples_written, 3)
        self.assertEqual(raw.size, 6)


if __name__ == "__main__":
    unittest.main()
