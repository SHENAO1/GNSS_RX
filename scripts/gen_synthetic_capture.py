"""
生成合成 PRN1 BPSK 扩频捕获文件（sc16 + JSON），用于在无硬件条件下验证 MATLAB 捕获算法。

复用 gnss_tx 信号生成器和 gnss_rx 文件基础设施，输出格式与真实 USRP 采集完全一致。

运行示例：
    cd /home/shen/projects/GNSS_RX
    PYTHONPATH=/home/shen/projects/gnss_tx/src:src \\
        python3 scripts/gen_synthetic_capture.py \\
        --config configs/rx_prn1_sn193982.yaml \\
        --snr-db 10 \\
        --duration 2
"""
from __future__ import annotations

import argparse
from dataclasses import replace
from datetime import datetime
from pathlib import Path
import sys

import numpy as np

PROJECT_ROOT = Path(__file__).resolve().parents[1]
SRC_PATH = PROJECT_ROOT / "src"
if str(SRC_PATH) not in sys.path:
    sys.path.insert(0, str(SRC_PATH))

from gnss_rx.metadata import CaptureMetadata, write_metadata_json
from gnss_rx.runtime import load_rx_runtime_config, resolve_capture_paths
from gnss_rx.writer import write_sc16_file

try:
    from gnss_tx.signal.spreader import GpsL1CaBpskGenerator
    HAVE_GNSS_TX = True
except ImportError:
    HAVE_GNSS_TX = False


def _generate_prn1_bpsk(num_samples: int, samples_per_chip: int, amplitude: float) -> np.ndarray:
    """使用 gnss_tx 信号生成器生成 PRN1 BPSK 基带信号（仅 I 支路，Q 恒为 0）。"""
    if not HAVE_GNSS_TX:
        raise ImportError(
            "无法导入 gnss_tx，请在 PYTHONPATH 中加入 gnss_tx/src 路径：\n"
            "  PYTHONPATH=/home/shen/projects/gnss_tx/src:src python3 scripts/gen_synthetic_capture.py"
        )
    gen = GpsL1CaBpskGenerator(
        prn_id=1,
        samples_per_chip=samples_per_chip,
        amplitude=amplitude,
    )
    return gen.generate_samples(num_samples)


def _add_awgn(signal: np.ndarray, snr_db: float) -> np.ndarray:
    """在 signal 上叠加 AWGN 白噪声，SNR 以 dB 为单位（相对于信号功率）。"""
    signal_power = float(np.mean(np.abs(signal) ** 2))
    snr_linear = 10.0 ** (snr_db / 10.0)
    noise_power = signal_power / snr_linear
    # 复数 AWGN：实部和虚部各为 N(0, noise_power/2)
    rng = np.random.default_rng()
    noise = rng.standard_normal(signal.size) + 1j * rng.standard_normal(signal.size)
    noise = noise * np.sqrt(noise_power / 2.0)
    return (signal + noise.astype(np.complex64)).astype(np.complex64)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="生成合成 PRN1 扩频捕获文件，用于无硬件条件下验证 MATLAB 捕获算法。"
    )
    parser.add_argument(
        "--config",
        default="configs/rx_prn1_sn193982.yaml",
        help="RX 配置文件路径，用于复用采样率、中心频率等参数（默认：configs/rx_prn1_sn193982.yaml）",
    )
    parser.add_argument(
        "--snr-db",
        type=float,
        default=10.0,
        metavar="SNR",
        help="信噪比 dB（相对于信号功率，默认：10 dB）",
    )
    parser.add_argument(
        "--duration",
        type=float,
        default=2.0,
        dest="duration_s",
        metavar="SEC",
        help="合成信号时长（秒，默认：2 s）",
    )
    parser.add_argument(
        "--amplitude",
        type=float,
        default=1.0,
        help="BPSK 幅度（默认：1.0，即满幅）",
    )
    parser.add_argument(
        "--output-base-dir",
        default=None,
        help="输出目录根路径（默认：从配置文件读取）",
    )
    return parser


def main() -> int:
    args = build_parser().parse_args()

    config = load_rx_runtime_config(Path(args.config))
    if args.output_base_dir is not None:
        config = replace(config, output_base_dir=args.output_base_dir)
    # 覆盖时长
    config = replace(config, duration_s=args.duration_s)

    sample_rate = config.sample_rate_hz
    samples_per_chip = round(sample_rate / 1.023e6)
    num_samples = int(round(sample_rate * args.duration_s))

    print("=" * 60)
    print("合成 PRN1 捕获文件生成器")
    print("=" * 60)
    print(f"采样率        : {sample_rate / 1e6:.3f} MHz")
    print(f"中心频率      : {config.center_freq_hz / 1e6:.3f} MHz")
    print(f"每 chip 采样数: {samples_per_chip}")
    print(f"总采样点数    : {num_samples:,}")
    print(f"时长          : {args.duration_s:.1f} s")
    print(f"SNR           : {args.snr_db:.1f} dB")
    print(f"BPSK 幅度     : {args.amplitude:.2f}")
    print()

    print("[1/3] 生成 PRN1 BPSK 扩频信号...")
    clean_signal = _generate_prn1_bpsk(
        num_samples=num_samples,
        samples_per_chip=samples_per_chip,
        amplitude=args.amplitude,
    )

    print(f"[2/3] 叠加 AWGN 噪声（SNR = {args.snr_db:.1f} dB）...")
    noisy_signal = _add_awgn(clean_signal, snr_db=args.snr_db)

    # 文件路径：在 stem 末尾加 _synthetic 标签，与真实采集区分
    capture_time = datetime.now()
    sc16_path, json_path = resolve_capture_paths(PROJECT_ROOT, config, when=capture_time)
    # 在 stem 上追加 _synthetic 标签
    sc16_path = sc16_path.with_name(sc16_path.stem + "_synthetic" + sc16_path.suffix)
    json_path = json_path.with_name(json_path.stem + "_synthetic" + json_path.suffix)

    print(f"[3/3] 写入文件...")
    sc16_path.parent.mkdir(parents=True, exist_ok=True)
    samples_written = write_sc16_file(sc16_path, noisy_signal)

    metadata = CaptureMetadata(
        sample_format="sc16",
        complex_layout="iq_int16_interleaved_le",
        sample_rate_hz=sample_rate,
        center_freq_hz=config.center_freq_hz,
        duration_s=args.duration_s,
        samples_captured=samples_written,
        rx_gain_db=config.rx_gain_db,
        bandwidth_hz=config.bandwidth_hz,
        antenna="synthetic",
        usrp_addr="synthetic",
        zero_if=True,
        signal_mode="spread",
        prn_id=1,
        tx_profile_reference="synthetic",
        data_file=sc16_path.name,
    )
    write_metadata_json(json_path, metadata)

    print()
    print("[成功] 合成捕获文件已生成：")
    print(f"  数据文件  : {sc16_path}")
    print(f"  元数据文件: {json_path}")
    print()
    print("MATLAB 分析命令：")
    print(f"  result = run_capture_analysis('{sc16_path.stem}');")
    print("  % 或直接分析最新文件：")
    print("  result = run_capture_analysis();")
    return 0


if __name__ == "__main__":
    sys.exit(main())
