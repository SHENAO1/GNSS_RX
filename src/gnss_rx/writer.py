from __future__ import annotations

from pathlib import Path

import numpy as np

try:
    from gnuradio import gr
except ImportError:  # pragma: no cover - 某些开发环境中 GNU Radio 是可选依赖。
    gr = None

HAVE_GNURADIO = gr is not None
_SyncBlockBase = gr.sync_block if HAVE_GNURADIO else object

SC16_SCALE = 32767.0


def complex_to_sc16_interleaved(samples: np.ndarray) -> np.ndarray:
    complex_samples = np.asarray(samples, dtype=np.complex64)
    clipped_i = np.clip(np.real(complex_samples), -1.0, 1.0)
    clipped_q = np.clip(np.imag(complex_samples), -1.0, 1.0)
    interleaved = np.empty(complex_samples.size * 2, dtype=np.int16)
    interleaved[0::2] = np.rint(clipped_i * SC16_SCALE).astype(np.int16)
    interleaved[1::2] = np.rint(clipped_q * SC16_SCALE).astype(np.int16)
    return interleaved


def write_sc16_file(path: str | Path, samples: np.ndarray) -> int:
    output_path = Path(path)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    interleaved = complex_to_sc16_interleaved(samples)
    output_path.write_bytes(interleaved.astype("<i2", copy=False).tobytes())
    return int(samples.size)


class Sc16CaptureSink(_SyncBlockBase):
    # v1 直接写原始 SC16，是因为它与 UHD 风格的数据流很好对应，同时也能
    # 保持采集文件足够紧凑。后续阶段可以在同样的 sink 接口下扩展 fc32、
    # 分段录制或滚动采集等策略。
    def __init__(self, path: str | Path) -> None:
        self.path = Path(path)
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self.handle = self.path.open("wb")
        self.samples_written = 0

        if HAVE_GNURADIO:
            super().__init__(name="sc16_capture_sink", in_sig=[np.complex64], out_sig=None)

    def work(self, input_items, output_items) -> int:
        samples = np.asarray(input_items[0], dtype=np.complex64)
        if samples.size == 0:
            return 0
        interleaved = complex_to_sc16_interleaved(samples)
        self.handle.write(interleaved.astype("<i2", copy=False).tobytes())
        self.samples_written += int(samples.size)
        return len(samples)

    def close(self) -> None:
        if not self.handle.closed:
            self.handle.flush()
            self.handle.close()


__all__ = ["HAVE_GNURADIO", "SC16_SCALE", "Sc16CaptureSink", "complex_to_sc16_interleaved", "write_sc16_file"]
