# GNSS_RX 结果目录

这个目录用于存放便于仓库内查看的结果样例；真实采集默认输出路径通常由
配置文件或 `GNSS_RX_DATA_DIR` 决定，常见位置是 VMware 共享目录
`/mnt/hgfs/GongXiangDocument/GNSS_RX_Data`。

## 结果如何生成

生成接收采集：

```bash
cd /home/shen/projects/GNSS_RX
PYTHONPATH=src python3 scripts/record_rx.py
```

生成无硬件合成采集：

```bash
cd /home/shen/projects/GNSS_RX
PYTHONPATH=/home/shen/projects/gnss_tx/src:src \
  python3 scripts/gen_synthetic_capture.py \
  --snr-db 10 \
  --duration 2
```

对采集结果做 MATLAB 分析：

```matlab
run_capture_analysis
```

## 结果目录结构

采集原始文件：

```text
<output_base_dir>/<YYYY>/<YYYY_MM_DD>/<stem>/
├── <stem>.sc16
└── <stem>.json
```

MATLAB 分析产物：

```text
<output_base_dir>/<YYYY>/<YYYY_MM_DD>/analysis/<stem>/
├── overview_time.png
├── overview_spectrum.png
├── iq_scatter.png
├── prn1_acquisition.png
├── multi_prn_survey.png
├── analysis_summary.json
└── analysis_summary.mat
```

## 查看建议

- 想看“原始采集怎么来的”，从 [`../scripts/README.md`](../scripts/README.md) 开始
- 想看“MATLAB 如何读这些结果”，看 [`../matlab/README.md`](../matlab/README.md)
