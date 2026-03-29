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

## 架构图

- `gnss_rx/architecture.drawio`
  包级依赖图，适合先看整体模块边界和外部入口。
- `gnss_rx/runtime.drawio`
  `runtime.py` 的配置生命周期、命名规则和 chunk 解析。
- `gnss_rx/flowgraph.drawio`
  `flowgraph.py` 的 UHD 探测、USRP Source 配置和 top block 组装。
- `gnss_rx/writer.drawio`
  `writer.py` 的 fc32 → SC16 转换逻辑，以及流式/批量两条写盘路径。
- `gnss_rx/metadata.drawio`
  `metadata.py` 如何把 `RxRuntimeConfig` 与实际采集结果映射成 JSON sidecar。
- `gnss_rx/utils/architecture.drawio`
  `utils/io.py` 的 YAML 读入与结构校验。

## 如何间接运行这些模块

通过 CLI 入口调用整套 Python 包：

```bash
cd /home/shen/projects/GNSS_RX
PYTHONPATH=src python3 scripts/record_rx.py --dry-run
```

`--dry-run` 是**演练模式**：加载配置、打印将要执行的采集参数和输出路径，但**不连接 USRP 硬件、不采集任何数据**，打印完后直接退出。适合在没有硬件时验证配置是否正确，或正式采集前预览参数。

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
