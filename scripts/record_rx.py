from __future__ import annotations

# argparse：Python 内置的命令行参数解析库，让脚本能接受 --xxx 形式的参数
import argparse
# Path：比字符串更安全的文件路径工具，自动处理 / 和 \ 的差异
from pathlib import Path
# sys：访问 Python 解释器底层功能，这里用来修改模块搜索路径和退出程序
import sys

# ── 把项目的 src 目录加入 Python 模块搜索路径 ──────────────────────────────────
# __file__ 是当前脚本自身的路径，parents[1] 向上跳两级到项目根目录
PROJECT_ROOT = Path(__file__).resolve().parents[1]
SRC_PATH = PROJECT_ROOT / "src"
# 如果 src 还不在搜索路径里，就插到最前面，这样 import gnss_rx.xxx 才能找到
if str(SRC_PATH) not in sys.path:
    sys.path.insert(0, str(SRC_PATH))

# ── 导入项目内部模块 ────────────────────────────────────────────────────────────
# flowgraph：负责搭建 GNU Radio 信号流图，完成实际的硬件采集
from gnss_rx.flowgraph import HAVE_UHD, build_capture_top_block, is_uhd_device_available, uhd_find_devices_output
# metadata：把采集参数（频率、采样率等）写成 JSON 文件，方便事后回溯
from gnss_rx.metadata import build_capture_metadata, write_metadata_json
# runtime：加载 YAML 配置、合并命令行覆盖参数、格式化打印报告
from gnss_rx.runtime import (
    apply_overrides,
    format_capture_report,
    format_matlab_handoff,
    load_rx_runtime_config,
    resolve_chunk_capture_paths,
    resolve_capture_paths,
)


def build_parser() -> argparse.ArgumentParser:
    """
    定义命令行参数。
    运行示例：
        python record_rx.py --prn-id 1 --duration 10 --dry-run
    """
    parser = argparse.ArgumentParser(
        description="录制一段 GNSS_RX 零中频采集数据，用于离线单星 PRN 捕获与多星对比分析。"
    )
    # --config：指定 YAML 配置文件路径，不填则用默认值
    parser.add_argument("--config", default="configs/rx_prn1_capture.yaml")
    # --prn-id：GPS 卫星编号（PRN），范围 1~32
    parser.add_argument("--prn-id", type=int)
    # --center-freq：接收机调谐中心频率，单位 Hz（例如 GPS L1 = 1575420000）
    parser.add_argument("--center-freq", type=float, dest="center_freq_hz")
    # --sample-rate：ADC 采样率，单位 Hz（越高越宽带，文件也越大）
    parser.add_argument("--sample-rate", type=float, dest="sample_rate_hz")
    # --rx-gain：接收增益，单位 dB（增益太低信号淹没在噪声里，太高会饱和失真）
    parser.add_argument("--rx-gain", type=float, dest="rx_gain_db")
    # --bandwidth：模拟滤波器带宽，单位 Hz（一般略大于采样率）
    parser.add_argument("--bandwidth", type=float, dest="bandwidth_hz")
    # --duration：录制时长，单位秒
    parser.add_argument("--duration", type=float, dest="duration_s")
    parser.add_argument("--capture-mode", choices=["single", "chunked"], dest="capture_mode")
    parser.add_argument("--chunk-duration", type=float, dest="chunk_duration_s")
    # --output-base-dir / --output-stem：自定义输出文件夹和文件名前缀
    parser.add_argument("--output-base-dir")
    parser.add_argument("--output-stem")
    # --dry-run：只打印采集计划，不真正开启硬件，用于参数调试
    parser.add_argument("--dry-run", action="store_true", help="打印生效后的采集计划，但不启动 USRP。")
    return parser


def main(argv: list[str] | None = None) -> int:
    """
    主流程：
      1. 解析命令行参数
      2. 加载 YAML 配置，并把命令行参数覆盖进去
      3. 打印采集计划（方便核对）
      4. 检查硬件是否可用
      5. 启动 GNU Radio 流图，录制 IQ 数据
      6. 写入元数据 JSON，方便 MATLAB 后处理
    返回值：0 表示成功，1 表示失败（Linux/Python 惯例）
    """
    # ── 第一步：解析参数 ────────────────────────────────────────────────────────
    args = build_parser().parse_args(argv)

    # ── 第二步：加载配置文件，再把命令行参数覆盖进去 ────────────────────────────
    # load_rx_runtime_config 读取 YAML，返回一个配置对象
    config = load_rx_runtime_config(Path(args.config))
    # apply_overrides 把非 None 的命令行参数逐一写入 config，None 表示"未指定，保留 YAML 值"
    config = apply_overrides(
        config,
        center_freq_hz=args.center_freq_hz,
        prn_id=args.prn_id,
        sample_rate_hz=args.sample_rate_hz,
        rx_gain_db=args.rx_gain_db,
        bandwidth_hz=args.bandwidth_hz,
        duration_s=args.duration_s,
        capture_mode=args.capture_mode,
        chunk_duration_s=args.chunk_duration_s,
        output_base_dir=args.output_base_dir,
        output_stem=args.output_stem,
    )

    # ── 第三步：确定输出文件路径，并打印采集计划 ────────────────────────────────
    chunk_specs = resolve_chunk_capture_paths(PROJECT_ROOT, config)
    data_path, metadata_path, first_chunk_duration_s, _, _, group_id = chunk_specs[0]
    print(format_capture_report(config, data_path=data_path, metadata_path=metadata_path))
    print("")

    # 查询当前连接的 UHD 设备列表（USRP 系列软件无线电）
    device_report = uhd_find_devices_output()
    print("UHD 设备发现输出：")
    print(device_report if device_report else "（无输出）")
    print("")

    # 打印 MATLAB 可直接复制粘贴的参数交接信息
    print(format_matlab_handoff(config, data_path=data_path, metadata_path=metadata_path))
    if config.capture_mode == "chunked":
        print("")
        print(f"chunked 模式：共 {len(chunk_specs)} 段，首段时长 {first_chunk_duration_s:.1f} s，capture_group_id={group_id}")

    # ── 第四步：dry-run 检查 ──────────────────────────────────────────────────
    # 如果用户只想预览采集计划，到这里就可以退出了
    if args.dry_run:
        print("")
        print("[信息] 已请求 dry-run，未启动采集。")
        return 0

    # ── 第五步：硬件检查 ──────────────────────────────────────────────────────
    # HAVE_UHD：编译/安装时是否有 UHD 驱动库
    # is_uhd_device_available()：运行时能否实际找到并打开一台 USRP
    if not HAVE_UHD or not is_uhd_device_available():
        print("")
        print("[错误] 未检测到 UHD 接收设备，拒绝启动采集。")
        return 1

    # ── 第六步：创建输出目录，启动采集 ───────────────────────────────────────
    # parents=True：自动创建多级目录；exist_ok=True：目录已存在也不报错
    print("")
    print("[信息] 开始零中频采集。请在整个录制窗口内保持接收机设置不变。")

    if config.capture_mode == "single":
        run_single_capture(config, data_path, metadata_path)
        print(f"[成功] 采集已正常结束：{data_path}")
        print(f"[成功] 元数据已写入：{metadata_path}")
    else:
        total_samples_written = 0
        for chunk_data_path, chunk_metadata_path, chunk_duration_s, chunk_index, chunk_count, capture_group_id in chunk_specs:
            print(f"[信息] chunk {chunk_index}/{chunk_count}：duration={chunk_duration_s:.1f}s")
            chunk_config = apply_overrides(
                config,
                duration_s=chunk_duration_s,
                output_stem=str(chunk_data_path.with_suffix("")),
            )
            chunk_samples_written = run_single_capture(
                chunk_config,
                chunk_data_path,
                chunk_metadata_path,
                capture_mode="chunked",
                chunk_index=chunk_index,
                chunk_count=chunk_count,
                chunk_duration_s=chunk_duration_s,
                capture_group_id=capture_group_id,
            )
            total_samples_written += chunk_samples_written

        print(f"[成功] chunked 采集已正常结束：共 {len(chunk_specs)} 段，累计样本数 {total_samples_written}")
    return 0


def run_single_capture(
    config,
    data_path,
    metadata_path,
    *,
    capture_mode: str | None = None,
    chunk_index: int | None = None,
    chunk_count: int | None = None,
    chunk_duration_s: float | None = None,
    capture_group_id: str | None = None,
) -> int:
    data_path.parent.mkdir(parents=True, exist_ok=True)

    tb, sink = build_capture_top_block(config=config, output_path=data_path)
    tb.run()
    sink.close()

    metadata = build_capture_metadata(
        config=config,
        samples_captured=sink.samples_written,
        data_path=data_path,
        capture_mode=capture_mode,
        chunk_index=chunk_index,
        chunk_count=chunk_count,
        chunk_duration_s=chunk_duration_s,
        capture_group_id=capture_group_id,
    )
    write_metadata_json(metadata_path, metadata)
    return sink.samples_written


if __name__ == "__main__":
    # 当脚本被直接执行（而非被 import）时进入这里
    # sys.exit() 把 main() 的返回值（0 或 1）传递给操作系统，
    # 这样 shell 脚本可以用 $? 判断是否成功
    sys.exit(main())
