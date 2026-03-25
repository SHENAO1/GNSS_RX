from __future__ import annotations

import argparse
from pathlib import Path
import sys

PROJECT_ROOT = Path(__file__).resolve().parents[1]
SRC_PATH = PROJECT_ROOT / "src"
if str(SRC_PATH) not in sys.path:
    sys.path.insert(0, str(SRC_PATH))

from gnss_rx.flowgraph import HAVE_UHD, build_capture_top_block, is_uhd_device_available, uhd_find_devices_output
from gnss_rx.metadata import build_capture_metadata, write_metadata_json
from gnss_rx.runtime import (
    apply_overrides,
    format_capture_report,
    format_matlab_handoff,
    load_rx_runtime_config,
    resolve_capture_paths,
)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="录制一段 GNSS_RX 零中频采集数据，用于离线单星 PRN 捕获与多星对比分析。"
    )
    parser.add_argument("--config", default="configs/rx_prn1_capture.yaml")
    parser.add_argument("--prn-id", type=int)
    parser.add_argument("--center-freq", type=float, dest="center_freq_hz")
    parser.add_argument("--sample-rate", type=float, dest="sample_rate_hz")
    parser.add_argument("--rx-gain", type=float, dest="rx_gain_db")
    parser.add_argument("--bandwidth", type=float, dest="bandwidth_hz")
    parser.add_argument("--duration", type=float, dest="duration_s")
    parser.add_argument("--output-base-dir")
    parser.add_argument("--output-stem")
    parser.add_argument("--dry-run", action="store_true", help="打印生效后的采集计划，但不启动 USRP。")
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    config = load_rx_runtime_config(Path(args.config))
    config = apply_overrides(
        config,
        center_freq_hz=args.center_freq_hz,
        prn_id=args.prn_id,
        sample_rate_hz=args.sample_rate_hz,
        rx_gain_db=args.rx_gain_db,
        bandwidth_hz=args.bandwidth_hz,
        duration_s=args.duration_s,
        output_base_dir=args.output_base_dir,
        output_stem=args.output_stem,
    )

    data_path, metadata_path = resolve_capture_paths(PROJECT_ROOT, config)
    print(format_capture_report(config, data_path=data_path, metadata_path=metadata_path))
    print("")
    device_report = uhd_find_devices_output()
    print("UHD 设备发现输出：")
    print(device_report if device_report else "（无输出）")
    print("")
    print(format_matlab_handoff(config, data_path=data_path, metadata_path=metadata_path))

    if args.dry_run:
        print("")
        print("[信息] 已请求 dry-run，未启动采集。")
        return 0

    if not HAVE_UHD or not is_uhd_device_available():
        print("")
        print("[错误] 未检测到 UHD 接收设备，拒绝启动采集。")
        return 1

    data_path.parent.mkdir(parents=True, exist_ok=True)
    # 保持 v1 录制路径尽可能原始，这样 MATLAB 看到的就是硬件直接输出的
    # 零中频观测。后续若需要预览或 DSP 分支，应从同一信源旁路分出，
    # 而不是修改首版录制路径。
    tb, sink = build_capture_top_block(config=config, output_path=data_path)
    print("")
    print("[信息] 开始零中频采集。请在整个录制窗口内保持接收机设置不变。")
    tb.run()
    sink.close()

    metadata = build_capture_metadata(config=config, samples_captured=sink.samples_written, data_path=data_path)
    write_metadata_json(metadata_path, metadata)

    print(f"[成功] 采集已正常结束：{data_path}")
    print(f"[成功] 元数据已写入：{metadata_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
