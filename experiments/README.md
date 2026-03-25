# GNSS_RX 实验记录

这个目录用于存放属于 `GNSS_RX` 项目的接收端采集日志、MATLAB 捕获笔记
以及重复性记录。

## 建议内容

每篇实验记录建议至少包含：

- 实验日期、目标和环境说明
- 使用的 TX/RX 配置文件
- 采集命令或合成数据生成命令
- MATLAB 分析命令
- 关键观察结果、截图路径和下一步结论

## 推荐命名

建议文件名使用：

```text
YYYY-MM-DD_<topic>.md
```

例如：

```text
2026-03-25_portability_refactor.md
```

## 复现实验的常用命令

真实采集：

```bash
cd /home/shen/projects/GNSS_RX
PYTHONPATH=src python3 scripts/record_rx.py --config configs/rx_prn1_capture.yaml
```

固定序列号设备的 OTA 采集：

```bash
cd /home/shen/projects/GNSS_RX
PYTHONPATH=src python3 scripts/record_rx.py --config configs/rx_prn1_sn193982.yaml
```

无硬件复现：

```bash
cd /home/shen/projects/GNSS_RX
PYTHONPATH=/home/shen/projects/gnss_tx/src:src \
  python3 scripts/gen_synthetic_capture.py \
  --config configs/rx_prn1_sn193982.yaml \
  --snr-db 10 \
  --duration 2
```

MATLAB 分析：

```matlab
run_capture_analysis
```

如果需要分析指定采集：

```matlab
run_capture_analysis('C:\VMwareVirtualMachines\GongXiangDocument\GNSS_RX_Data\<YYYY>\<YYYY_MM_DD>\<stem>\<stem>.json')
```

## 写实验记录前先看

- 根流程说明见 [`../README.md`](../README.md)
- MATLAB 操作细节见 [`../matlab/README.md`](../matlab/README.md)
- 具体实验步骤模板见 [`../docs/experiment_workflow.md`](../docs/experiment_workflow.md)
