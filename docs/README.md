# GNSS_RX 文档目录

这里存放设计说明和实验流程文档。文档本身不直接执行代码，但每篇文档都对应
一组可以复现的入口命令。

## 文档索引

- `receiver_overview.md`
  接收机实现说明，适合先理解 Python 包、流图和 MATLAB 分析链的关系。
- `experiment_workflow.md`
  实验操作顺序，适合真正开始跑一遍采集和分析时作为清单使用。
- `system_architecture.drawio`
  系统架构图（DrawIO 格式），可视化配置/采集/落盘/MATLAB/BER 的整体关系。
- `../src/gnss_rx/*.drawio`
  Python 核心模块图，适合按 `runtime / flowgraph / writer / metadata / utils` 逐个看实现。
- `../matlab/architecture.drawio` / `../matlab/ber_loopback.drawio`
  MATLAB 主分析链与 BER 诊断链的专用图。

## 按文档复现的入口命令

先看实现，再做配置自检：

```bash
cd /home/shen/projects/GNSS_RX
PYTHONPATH=src python3 scripts/record_rx.py --dry-run
```

按实验流程做真实采集：

```bash
cd /home/shen/projects/GNSS_RX
PYTHONPATH=src python3 scripts/record_rx.py --config configs/rx_prn1_capture.yaml
```

没有硬件时按同样流程生成合成数据：

```bash
cd /home/shen/projects/GNSS_RX
PYTHONPATH=/home/shen/projects/gnss_tx/src:src \
  python3 scripts/gen_synthetic_capture.py \
  --snr-db 10 \
  --duration 2
```

然后在 MATLAB 中运行：

```matlab
run_capture_analysis
```

## 阅读顺序建议

1. 先看 `receiver_overview.md`，理解有哪些模块和数据格式。
2. 再看 `experiment_workflow.md`，按顺序执行命令并记录结果。
3. 需要更细的目录级说明时，回到各子目录 README。
