# GNSS_RX Python 包目录

这个目录是 `gnss_rx` Python 包本体。这里的模块通常不直接单独运行，而是由
`scripts/record_rx.py` 和 `scripts/gen_synthetic_capture.py` 调用。

## 模块结构

- `gnss_rx/runtime.py`
  配置加载、参数覆盖、输出路径解析、采集报告格式化。
  `RxRuntimeConfig` 支持 `all_prns: bool`（多星模式）和 `prn_id: int`（单星目标）。
- `gnss_rx/flowgraph.py`
  GNU Radio + UHD 采集流图
- `gnss_rx/writer.py`
  复数样本到 SC16 交织文件的写盘逻辑
- `gnss_rx/metadata.py`
  JSON sidecar 元数据生成。
  `CaptureMetadata` 包含 `all_prns: bool` 和 `prn_ids: list | None` 字段，
  多星模式时 `prn_ids = [1, 2, ..., 32]`。
- `gnss_rx/utils/io.py`
  YAML 等基础 I/O 工具

## 如何间接运行这些模块

通过 CLI 入口调用整套 Python 包：

```bash
cd /home/shen/projects/GNSS_RX
PYTHONPATH=src python3 scripts/record_rx.py --dry-run
```

或生成合成采集文件：

```bash
cd /home/shen/projects/GNSS_RX
PYTHONPATH=/home/shen/projects/gnss_tx/src:src \
  python3 scripts/gen_synthetic_capture.py --snr-db 10 --duration 2
```

## 开发时的快速验证

如果你修改了 `src/gnss_rx/` 下的代码，建议先跑测试：

```bash
cd /home/shen/projects/GNSS_RX
PYTHONPATH=src python3 -m unittest discover -s tests -v
```
