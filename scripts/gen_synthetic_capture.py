"""
生成合成 GNSS 扩频捕获文件（sc16 + JSON），用于在无硬件条件下验证 MATLAB 捕获算法。

支持单星（指定 PRN 1~32）和多星（--all-prns，PRN 1~32 叠加）两种模式。
复用 gnss_tx 信号生成器和 gnss_rx 文件基础设施，输出格式与真实 USRP 采集完全一致。

运行示例：
    cd /home/shen/projects/GNSS_RX

    # 单星（指定 PRN 7）
    PYTHONPATH=/home/shen/projects/gnss_tx/src:src \\
        python3 scripts/gen_synthetic_capture.py --prn-id 7 --snr-db 10

    # 32星叠加
    PYTHONPATH=/home/shen/projects/gnss_tx/src:src \\
        python3 scripts/gen_synthetic_capture.py --all-prns --snr-db 10 --duration 2
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
from gnss_rx.runtime import load_rx_runtime_config, normalize_capture_time, resolve_capture_paths
from gnss_rx.writer import write_sc16_file

try:
    from gnss_tx.signal.spreader import GpsL1CaBpskGenerator
    from gnss_tx.signal.multi_sat_combiner import build_multi_sat_replay_samples
    HAVE_GNSS_TX = True
except ImportError:
    HAVE_GNSS_TX = False

_GNSS_TX_IMPORT_MSG = (
    "无法导入 gnss_tx，请在 PYTHONPATH 中加入 gnss_tx/src 路径：\n"
    "  PYTHONPATH=/home/shen/projects/gnss_tx/src:src python3 scripts/gen_synthetic_capture.py"
)


def _generate_single_prn_bpsk(num_samples: int, samples_per_chip: int, amplitude: float, prn_id: int) -> np.ndarray:
    """使用 gnss_tx 信号生成器生成指定 PRN 的 BPSK 基带信号（仅 I 支路，Q 恒为 0）。"""
    if not HAVE_GNSS_TX:
        raise ImportError(_GNSS_TX_IMPORT_MSG)
    gen = GpsL1CaBpskGenerator(
        prn_id=prn_id,
        samples_per_chip=samples_per_chip,
        amplitude=amplitude,
    )
    return gen.generate_samples(num_samples)


def _generate_all_prns_combined(num_samples: int, samples_per_chip: int, amplitude: float) -> np.ndarray:
    """生成 PRN 1~32 叠加的合并基带信号（复用 gnss_tx multi_sat_combiner）。"""
    if not HAVE_GNSS_TX:
        raise ImportError(_GNSS_TX_IMPORT_MSG)
    # 生成一个完整 nav pattern 周期的缓冲区，再循环平铺到目标长度
    one_period = build_multi_sat_replay_samples(samples_per_chip=samples_per_chip)
    repeats = (num_samples + len(one_period) - 1) // len(one_period)
    tiled = np.tile(one_period, repeats)[:num_samples]
    return (tiled * amplitude).astype(np.complex64)


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
        description="生成合成 GNSS 扩频捕获文件，用于无硬件条件下验证 MATLAB 捕获算法。"
    )
    parser.add_argument(
        "--config",
        default="configs/rx_prn1_sn193982.yaml",
        help="RX 配置文件路径，用于复用采样率、中心频率等参数（默认：configs/rx_prn1_sn193982.yaml）",
    )
    parser.add_argument(
        "--prn-id",
        type=int,
        default=None,
        metavar="PRN",
        help="目标 PRN 编号（1~32，默认从配置文件读取）；--all-prns 时忽略此参数",
    )
    parser.add_argument(
        "--all-prns",
        action="store_true",
        help="生成 PRN 1~32 叠加合并信号（覆盖 --prn-id）",
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
    config = replace(config, duration_s=args.duration_s)

    # 确定信号模式：--all-prns 优先，否则用 --prn-id 覆盖配置中的 prn_id
    all_prns = args.all_prns
    if all_prns:
        config = replace(config, all_prns=True)
        prn_id = config.prn_id  # 保留兼容字段，不影响信号生成
    elif args.prn_id is not None:
        config = replace(config, prn_id=args.prn_id)
        prn_id = args.prn_id
    else:
        prn_id = config.prn_id

    sample_rate = config.sample_rate_hz
    samples_per_chip = round(sample_rate / 1.023e6)
    num_samples = int(round(sample_rate * args.duration_s))

    mode_label = "PRN 1~32 叠加" if all_prns else f"PRN {prn_id}"
    print("=" * 60)
    print(f"合成捕获文件生成器（{mode_label}）")
    print("=" * 60)
    print(f"信号模式      : {mode_label}")
    print(f"采样率        : {sample_rate / 1e6:.3f} MHz")
    print(f"中心频率      : {config.center_freq_hz / 1e6:.3f} MHz")
    print(f"每 chip 采样数: {samples_per_chip}")
    print(f"总采样点数    : {num_samples:,}")
    print(f"时长          : {args.duration_s:.1f} s")
    print(f"SNR           : {args.snr_db:.1f} dB")
    print(f"BPSK 幅度     : {args.amplitude:.2f}")
    print()

    print(f"[1/3] 生成 {mode_label} 扩频信号...")
    if all_prns:
        clean_signal = _generate_all_prns_combined(
            num_samples=num_samples,
            samples_per_chip=samples_per_chip,
            amplitude=args.amplitude,
        )
    else:
        clean_signal = _generate_single_prn_bpsk(
            num_samples=num_samples,
            samples_per_chip=samples_per_chip,
            amplitude=args.amplitude,
            prn_id=prn_id,
        )

    print(f"[2/3] 叠加 AWGN 噪声（SNR = {args.snr_db:.1f} dB）...")
    noisy_signal = _add_awgn(clean_signal, snr_db=args.snr_db)

    # 文件路径：在 stem 末尾加 _synthetic 标签，与真实采集区分
    # 合成数据也写入与真实采集一致的开始时间语义，方便 MATLAB / 文档示例统一。
    capture_time = normalize_capture_time(datetime.now().astimezone())
    sc16_path, json_path = resolve_capture_paths(PROJECT_ROOT, config, when=capture_time)
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
        capture_started_at_iso=capture_time.isoformat(timespec="seconds"),
        samples_captured=samples_written,
        rx_gain_db=config.rx_gain_db,
        bandwidth_hz=config.bandwidth_hz,
        antenna="synthetic",
        usrp_addr="synthetic",
        zero_if=True,
        signal_mode="spread",
        prn_id=prn_id,
        all_prns=all_prns,
        prn_ids=list(range(1, 33)) if all_prns else None,
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
