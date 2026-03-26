# GNSS_RX

`GNSS_RX` 是 `gnss_tx` 发射机工程的配套接收机项目。通过兼容 UHD 的 USRP 采集单通道零中频 IQ 数据，以 SC16 格式存储，附带 JSON 元数据，供 MATLAB 离线执行 GPS L1 C/A 捕获与多星对比分析。

支持两种工作模式：
- **单星模式**：采集并记录指定 PRN（1~32）的信号，元数据标记目标 PRN
- **多星模式**（`all_prns: true`）：采集全部 32 颗 PRN 的叠加信号，元数据标记所有 PRN

---

## 功能概述

- 单通道 USRP/UHD 零中频采集（GNU Radio 驱动）
- 自动生成带时间戳和参数标签的文件名与目录结构
- `.sc16`（交织 int16 IQ）+ `.json`（元数据）文件对输出
- 无硬件合成信号生成，用于算法验证（支持单星和多星合成）
- MATLAB 离线分析链：加载、绘图、指定 PRN 捕获（1~32）、多星扫描、结果归档

---

## 目录结构

```
GNSS_RX/
├── configs/            接收端 YAML 配置文件（详见 configs/README.md）
├── docs/               技术文档（详见 docs/README.md）
├── experiments/        实验记录（详见 experiments/README.md）
├── matlab/             MATLAB 离线分析工作区（详见 matlab/README.md）
│   ├── functions/      加载、绘图、捕获、归档函数
│   └── scripts/        入口脚本 run_capture_analysis.m
├── results/            采集输出目录（本地预览用，详见 results/README.md）
├── scripts/            Python CLI 脚本（详见 scripts/README.md）
├── src/gnss_rx/        核心 Python 包（详见 src/README.md）
│   ├── flowgraph.py    GNU Radio 流图组装
│   ├── metadata.py     JSON sidecar 生成（含 all_prns/prn_ids 字段）
│   ├── runtime.py      运行时配置与路径管理
│   └── writer.py       SC16 写文件模块
└── tests/              单元测试（详见 tests/README.md）
```

---

## 子目录文档索引

| 目录 | README | 说明 |
|------|--------|------|
| `scripts/` | [scripts/README.md](scripts/README.md) | 采集、合成数据生成、MATLAB 同步命令 |
| `configs/` | [configs/README.md](configs/README.md) | 配置文件说明，含 rx_all32prn.yaml |
| `matlab/` | [matlab/README.md](matlab/README.md) | MATLAB 分析链运行方法与同步到宿主机命令 |
| `tests/` | [tests/README.md](tests/README.md) | 单元测试运行命令 |
| `src/` | [src/README.md](src/README.md) | Python 包结构与模块说明 |
| `results/` | [results/README.md](results/README.md) | 输出目录结构说明 |
| `docs/` | [docs/README.md](docs/README.md) | 技术文档索引 |

---

## 环境依赖

```bash
# 必须
pip install numpy pyyaml

# 采集硬件时必须（合成数据无需）
sudo apt install -y gnuradio python3-gnuradio uhd-host libuhd-dev
sudo uhd_images_downloader
uhd_find_devices
```

与 `gnss_tx` 项目同级放置（合成数据生成时需要）：

```
projects/
├── gnss_tx/
└── GNSS_RX/
```

---

## 快速开始

> 详细参数和更多示例见各子目录 README。

```bash
cd /home/shen/projects/GNSS_RX

# 干运行（验证配置，不启动采集）
PYTHONPATH=src python3 scripts/record_rx.py --dry-run

# 标准采集（连接 USRP 后）
PYTHONPATH=src python3 scripts/record_rx.py \
    --config configs/rx_prn1_capture.yaml

# 生成合成采集文件（无需硬件，用于验证 MATLAB 分析链）
PYTHONPATH=/home/shen/projects/gnss_tx/src:src \
    python3 scripts/gen_synthetic_capture.py --snr-db 10

# 同步 MATLAB 代码到宿主机共享目录
rsync -av --delete matlab/ /mnt/hgfs/GongXiangDocument/GNSS_RX_matlab/
```

然后在 MATLAB 中运行：

```matlab
run_capture_analysis
```

---

## 输出文件格式

### 路径结构

```
<output_base_dir>/<YYYY>/<YYYY_MM_DD>/<stem>/<stem>.sc16
                                            <stem>.json
```

### stem 命名格式

单星：`<时间戳>_rawiq_sc16_zeroif_prn<id>_spread_sr<rate>_cf<freq>_dur<dur>s`

多星：`<时间戳>_rawiq_sc16_zeroif_prn_all32_spread_sr<rate>_cf<freq>_dur<dur>s`

### `.json` sidecar 字段

| 字段 | 说明 |
|------|------|
| `sample_format` | `"sc16"` |
| `sample_rate_hz` | 采样率（Hz） |
| `center_freq_hz` | 中心频率（Hz） |
| `prn_id` | 目标 PRN（单星模式） |
| `all_prns` | `true` = 多星叠加模式 |
| `prn_ids` | 多星模式时为 `[1, 2, ..., 32]`，单星时为 `null` |
| `signal_mode` | `"spread"` |
| `complex_layout` | `"iq_int16_interleaved_le"` |

---

## 单元测试

```bash
cd /home/shen/projects/GNSS_RX
PYTHONPATH=src python3 -m unittest discover -s tests -v
```
