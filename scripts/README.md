# GNSS_RX 脚本目录

这个目录包含项目的直接入口脚本。日常运行 `GNSS_RX` 时，通常从这里开始。

## 脚本一览

- `record_rx.py`
  真实 USRP 采集入口，输出 `.sc16 + .json`
- `gen_synthetic_capture.py`
  无硬件合成 PRN1 捕获文件
- `sync_matlab.sh`
  将 `matlab/` 同步到共享目录，供宿主机 MATLAB 使用

## 直接运行方法

真实采集前先 dry-run：

```bash
cd /home/shen/projects/GNSS_RX
PYTHONPATH=src python3 scripts/record_rx.py --dry-run
```

正式采集：

```bash
cd /home/shen/projects/GNSS_RX
PYTHONPATH=src python3 scripts/record_rx.py --config configs/rx_prn1_capture.yaml
```

指定参数覆盖 YAML：

```bash
cd /home/shen/projects/GNSS_RX
PYTHONPATH=src python3 scripts/record_rx.py \
  --config configs/rx_prn1_capture.yaml \
  --prn-id 7 \
  --duration 5 \
  --rx-gain 30
```

生成合成数据：

```bash
cd /home/shen/projects/GNSS_RX
PYTHONPATH=/home/shen/projects/gnss_tx/src:src \
  python3 scripts/gen_synthetic_capture.py \
  --config configs/rx_prn1_sn193982.yaml \
  --snr-db 10 \
  --duration 2
```

同步 MATLAB 工作区：

```bash
cd /home/shen/projects/GNSS_RX
./scripts/sync_matlab.sh /mnt/hgfs/GongXiangDocument/GNSS_RX_matlab
```

## 常见组合流程

从采集到分析：

```bash
cd /home/shen/projects/GNSS_RX
PYTHONPATH=src python3 scripts/record_rx.py
./scripts/sync_matlab.sh /mnt/hgfs/GongXiangDocument/GNSS_RX_matlab
```

然后在 MATLAB 中运行：

```matlab
run_capture_analysis
```

说明：
- `record_rx.py` 现在支持 `--prn-id` 覆盖，影响采集 metadata、文件命名和 MATLAB 交接摘要。
- `gen_synthetic_capture.py` 目前仍固定生成 PRN1 合成信号，用于验证 MATLAB 现有的 PRN1 详细捕获链。
