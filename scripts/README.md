# GNSS_RX 脚本目录

本目录包含项目的直接入口脚本。所有命令须在 `/home/shen/projects/GNSS_RX` 目录下执行。

---

## 脚本一览

| 脚本 | 说明 |
|------|------|
| `record_rx.py` | 真实 USRP 采集入口，输出 `.sc16 + .json` |
| `gen_synthetic_capture.py` | 无硬件合成采集文件（支持单星和 32 星叠加） |
| `sync_matlab.sh` | 将 `matlab/` 同步到共享目录，供宿主机 MATLAB 使用 |

---

## record_rx.py — 真实 USRP 采集

```bash
cd /home/shen/projects/GNSS_RX

# 干运行（验证配置，不启动采集）
PYTHONPATH=src python3 scripts/record_rx.py --dry-run

# 标准采集（使用配置文件）
PYTHONPATH=src python3 scripts/record_rx.py \
    --config configs/rx_prn1_capture.yaml

# 临时切换目标 PRN（不改配置文件）
PYTHONPATH=src python3 scripts/record_rx.py \
    --config configs/rx_prn1_capture.yaml --prn-id 7

# 32星叠加采集
PYTHONPATH=src python3 scripts/record_rx.py \
    --config configs/rx_all32prn.yaml

# OTA 空收（固定设备序列号）
PYTHONPATH=src python3 scripts/record_rx.py \
    --config configs/rx_prn1_sn193982.yaml

# CLI 参数覆盖（优先级高于 YAML）
PYTHONPATH=src python3 scripts/record_rx.py \
    --duration 5 --rx-gain 30 --output-base-dir /tmp/gnss_test

# 指定固定文件 stem（便于脚本读取）
PYTHONPATH=src python3 scripts/record_rx.py \
    --output-stem /tmp/gnss_test/my_capture
# 输出：/tmp/gnss_test/my_capture.sc16
#        /tmp/gnss_test/my_capture.json
```

### CLI 参数完整参考

| 参数 | 说明 | 示例 |
|------|------|------|
| `--config` | YAML 配置文件路径 | `--config configs/rx_prn1_capture.yaml` |
| `--prn-id` | 覆盖目标 PRN（1~32，单星模式） | `--prn-id 7` |
| `--center-freq` | 中心频率（Hz） | `--center-freq 150e6` |
| `--sample-rate` | 采样率（Hz） | `--sample-rate 4092000` |
| `--rx-gain` | 接收增益（dB） | `--rx-gain 35` |
| `--bandwidth` | RF 带宽（Hz） | `--bandwidth 4092000` |
| `--duration` | 录制时长（秒） | `--duration 10` |
| `--output-base-dir` | 输出根目录 | `--output-base-dir /tmp/gnss_data` |
| `--output-stem` | 手动指定文件 stem | `--output-stem /tmp/capture` |
| `--dry-run` | 仅打印计划，不采集 | `--dry-run` |

---

## gen_synthetic_capture.py — 无硬件合成数据生成

无需连接 USRP，生成仿真 IQ 数据用于验证 MATLAB 分析链。

```bash
cd /home/shen/projects/GNSS_RX

# 单星 PRN1 合成（默认）
PYTHONPATH=/home/shen/projects/gnss_tx/src:src \
    python3 scripts/gen_synthetic_capture.py --snr-db 10

# 指定 PRN 合成
PYTHONPATH=/home/shen/projects/gnss_tx/src:src \
    python3 scripts/gen_synthetic_capture.py \
    --prn-id 7 --snr-db 10 --duration 2

# 32星叠加合成（对应 all_prns 采集场景）
PYTHONPATH=/home/shen/projects/gnss_tx/src:src \
    python3 scripts/gen_synthetic_capture.py \
    --config configs/rx_all32prn.yaml --all-prns --snr-db 10

# 输出到临时目录
PYTHONPATH=/home/shen/projects/gnss_tx/src:src \
    python3 scripts/gen_synthetic_capture.py \
    --snr-db 10 --output-base-dir /tmp/gnss_synthetic
```

输出文件 stem 末尾带 `_synthetic` 标签，格式与真实采集完全一致，MATLAB 可直接读取。

### CLI 参数参考

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `--config` | `configs/rx_prn1_sn193982.yaml` | 复用采样率、中心频率等参数 |
| `--prn-id` | `1` | 目标 PRN（单星模式，1~32） |
| `--all-prns` | 无（flag） | 生成 PRN 1~32 叠加合成信号（需 gnss_tx 在 PYTHONPATH 中） |
| `--snr-db` | `10` | 信噪比（dB），降低到 0 可测算法鲁棒性 |
| `--duration` | `2.0` | 信号时长（秒） |
| `--amplitude` | `1.0` | BPSK 幅度 |
| `--output-base-dir` | 配置文件中读取 | 覆盖输出根目录 |

---

## sync_matlab.sh — MATLAB 代码同步

将仓库中的 `matlab/` 目录和根目录入口脚本 `matlab/ber.m` 同步到 VMware 宿主机共享目录，供 Windows 上的 MATLAB 使用。
`/mnt/hgfs/GongXiangDocument/GNSS_RX_matlab` 应视为部署镜像，源码真相源是仓库中的 `GNSS_RX/matlab/`。
脚本会镜像 `functions/` 与 `scripts/`，并同步根目录受管文件，同时保留 `tx_truth.json` 这类运行期产物。
同步命令及数据目录配置说明见 [matlab/README.md](../matlab/README.md)。

```bash
cd /home/shen/projects/GNSS_RX

# 推荐：使用脚本同步整个 MATLAB 工作区镜像
./scripts/sync_matlab.sh /mnt/hgfs/GongXiangDocument/GNSS_RX_matlab
```

---

## 常用组合流程

从合成数据到 MATLAB 分析（无需硬件）：

```bash
cd /home/shen/projects/GNSS_RX

# 1. 生成合成数据
PYTHONPATH=/home/shen/projects/gnss_tx/src:src \
    python3 scripts/gen_synthetic_capture.py --snr-db 10 --duration 2

# 2. 同步 MATLAB 代码到共享目录
./scripts/sync_matlab.sh /mnt/hgfs/GongXiangDocument/GNSS_RX_matlab
```

然后在 MATLAB（Windows 宿主机或 Linux 本机）中运行：

```matlab
run_capture_analysis
```

从真实采集到 MATLAB 分析：

```bash
cd /home/shen/projects/GNSS_RX

# 1. 采集
PYTHONPATH=src python3 scripts/record_rx.py \
    --config configs/rx_prn1_capture.yaml

# 2. 同步 MATLAB 代码
./scripts/sync_matlab.sh /mnt/hgfs/GongXiangDocument/GNSS_RX_matlab
```
