# GNSS_RX

`GNSS_RX` 是 `gnss_tx` 发射机工作区的配套接收机项目。它通过兼容 UHD 的 USRP 采集单通道零中频 IQ 数据，以 `SC16` 格式存储，并附带 JSON 元数据，供 MATLAB 离线执行 GPS L1 C/A PRN1 捕获。

## 功能概述

- 单通道 USRP/UHD 零中频采集（GNU Radio 驱动）
- 自动生成带时间戳和参数标签的文件名
- `.sc16`（交织 int16 IQ）+ `.json`（元数据）文件对输出
- 无硬件合成信号生成，用于算法验证
- MATLAB 离线分析链：加载、绘图、PRN1 捕获、多星搜索、结果归档

当前发射端 / 接收端约定：

```
center_freq_hz = 100e6
sample_rate_hz = 4.092e6
signal_mode    = spread
prn_id         = 1
```

---

## 目录结构

```
GNSS_RX/
├── configs/            接收端 YAML 配置文件
├── docs/               技术文档
├── experiments/        实验记录
├── matlab/             宿主机 MATLAB 离线分析工作区
│   ├── functions/      加载、绘图、捕获、归档函数
│   └── scripts/        入口脚本 run_capture_analysis.m
├── results/            采集输出目录（本地预览用）
├── scripts/            Python CLI 脚本
├── src/gnss_rx/        核心 Python 包
│   ├── flowgraph.py    GNU Radio 流图组装
│   ├── metadata.py     JSON sidecar 生成
│   ├── runtime.py      运行时配置与路径管理
│   └── writer.py       SC16 写文件模块
└── tests/              单元测试与集成测试
```

各目录的细化说明和运行方法见对应 README：

- [`configs/README.md`](configs/README.md)：如何选择和切换接收配置
- [`docs/README.md`](docs/README.md)：文档索引，以及按文档复现实验的入口命令
- [`experiments/README.md`](experiments/README.md)：实验记录怎么写，如何复现实验
- [`matlab/README.md`](matlab/README.md)：MATLAB 离线分析的运行方法
- [`results/README.md`](results/README.md)：采集结果和分析结果的目录说明
- [`scripts/README.md`](scripts/README.md)：各 CLI 脚本的直接运行方式
- [`src/README.md`](src/README.md)：Python 包结构与调用关系
- [`tests/README.md`](tests/README.md)：测试命令和验证范围

---

## 环境依赖

- Ubuntu 22.04 或更高版本
- Python 3.10+
- `numpy`、`pyyaml`（必须）
- GNU Radio 3.10+ 及 UHD 驱动（采集硬件时必须；合成数据无需）
- USRP B210 或兼容 UHD 的 SDR 设备
- 与 `gnss_tx` 项目同级放置（合成数据生成时需要）

---

## 安装与配置

### 1. 安装 Python 依赖

```bash
cd /home/shen/projects/GNSS_RX
pip install numpy pyyaml
```

或以可编辑模式安装包本体：

```bash
pip install -e .
```

### 2. 安装 GNU Radio 与 UHD（实采时必须）

```bash
sudo apt update
sudo apt install -y gnuradio python3-gnuradio uhd-host libuhd-dev
```

下载 USRP FPGA 固件：

```bash
sudo uhd_images_downloader
```

验证设备识别：

```bash
uhd_find_devices
```

预期输出（示例）：

```
[INFO] [UHD] linux; GNU C++ version 11.4.0; Boost_107400; UHD_4.3.0.0
--------------------------------------------------
-- UHD Device 0
--------------------------------------------------
Device Address:
    serial: 8003272
    name: MyB210
    product: B210
    type: b200
```

### 3. 配置数据输出目录

**方法 A：环境变量（推荐用于临时测试）**

```bash
export GNSS_RX_DATA_DIR=/home/shen/gnss_data
```

将此行加入 `~/.bashrc` 可永久生效：

```bash
echo 'export GNSS_RX_DATA_DIR=/home/shen/gnss_data' >> ~/.bashrc
source ~/.bashrc
```

**方法 B：修改配置文件**

```bash
# 编辑 configs/rx_prn1_capture.yaml
nano configs/rx_prn1_capture.yaml
# 将 output_base_dir 改为实际路径
```

**方法 C：VMware 共享目录（默认配置）**

```bash
# 默认输出到 /mnt/hgfs/GongXiangDocument/GNSS_RX_Data
# 确认共享目录已挂载：
ls /mnt/hgfs/GongXiangDocument/
```

### 4. 配置 MATLAB 路径（MATLAB 在宿主机时）

```bash
# 复制路径模板
cp matlab/gnss_rx_user_paths.m.example matlab/gnss_rx_user_paths.m

# 填写实际数据目录（Windows 路径示例）
# GNSS_RX_DATA_DIR = 'C:\VMwareVirtualMachines\GongXiangDocument\GNSS_RX_Data';
nano matlab/gnss_rx_user_paths.m
```

### 5. 同步 MATLAB 代码到共享目录（仅 MATLAB 在宿主机时需要）

```bash
./scripts/sync_matlab.sh /mnt/hgfs/GongXiangDocument/GNSS_RX_matlab
```

每次修改 `matlab/` 下的代码后重新运行此命令。

---

## 快速开始

### 采集前验证（dry-run）

在不连接 USRP 的情况下，打印生效后的采集计划：

```bash
cd /home/shen/projects/GNSS_RX
PYTHONPATH=src python3 scripts/record_rx.py --dry-run
```

示例输出：

```
============================================================
GNSS_RX 采集配置
============================================================
usrp_addr=type=b200
center_freq_hz=100000000.0
sample_rate_hz=4092000.0
...
============================================================
MATLAB 交接摘要
============================================================
sample_format=sc16
sample_rate_hz=4092000.0
center_freq_hz=100000000.0
...
[信息] 已请求 dry-run，未启动采集。
```

### 标准采集

使用默认配置录制 2 秒：

```bash
PYTHONPATH=src python3 scripts/record_rx.py
```

指定配置文件：

```bash
PYTHONPATH=src python3 scripts/record_rx.py \
  --config configs/rx_prn1_capture.yaml
```

覆盖关键参数（命令行参数优先级高于 YAML）：

```bash
PYTHONPATH=src python3 scripts/record_rx.py \
  --duration 5 \
  --rx-gain 30
```

指定固定设备（双 USRP 环境避免随机选错）：

```bash
PYTHONPATH=src python3 scripts/record_rx.py \
  --config configs/rx_prn1_sn193982.yaml
```

---

## CLI 参数完整参考

```
usage: record_rx.py [-h] [--config CONFIG]
                    [--center-freq CENTER_FREQ_HZ]
                    [--sample-rate SAMPLE_RATE_HZ]
                    [--rx-gain RX_GAIN_DB]
                    [--bandwidth BANDWIDTH_HZ]
                    [--duration DURATION_S]
                    [--output-base-dir OUTPUT_BASE_DIR]
                    [--output-stem OUTPUT_STEM]
                    [--dry-run]
```

| 参数 | 说明 | 示例 |
|------|------|------|
| `--config` | YAML 配置文件路径 | `--config configs/rx_prn1_capture.yaml` |
| `--center-freq` | 中心频率（Hz） | `--center-freq 150e6` |
| `--sample-rate` | 采样率（Hz） | `--sample-rate 4092000` |
| `--rx-gain` | 接收增益（dB） | `--rx-gain 35` |
| `--bandwidth` | RF 带宽（Hz） | `--bandwidth 4092000` |
| `--duration` | 录制时长（秒） | `--duration 10` |
| `--output-base-dir` | 输出根目录 | `--output-base-dir /tmp/gnss_data` |
| `--output-stem` | 手动指定文件 stem | `--output-stem /tmp/gnss_data/test_capture` |
| `--dry-run` | 仅打印计划，不采集 | `--dry-run` |

### 常用示例

**录制 10 秒并输出到临时目录：**

```bash
PYTHONPATH=src python3 scripts/record_rx.py \
  --duration 10 \
  --output-base-dir /tmp/gnss_rx_test \
  --dry-run
```

**OTA 空收（提高增益，换频点）：**

```bash
PYTHONPATH=src python3 scripts/record_rx.py \
  --config configs/rx_prn1_sn193982.yaml \
  --center-freq 150000000 \
  --rx-gain 35 \
  --duration 5
```

**手动指定文件 stem（固定文件名，便于脚本读取）：**

```bash
PYTHONPATH=src python3 scripts/record_rx.py \
  --output-stem /tmp/gnss_rx_test/my_capture
# 输出：/tmp/gnss_rx_test/my_capture.sc16
#        /tmp/gnss_rx_test/my_capture.json
```

---

## 软件回环验证（无需硬件）

在天线或线缆回环到位之前，可以用合成信号验证捕获算法是否正确工作。

### 生成合成 PRN1 采集文件

```bash
cd /home/shen/projects/GNSS_RX
PYTHONPATH=/home/shen/projects/gnss_tx/src:src \
  python3 scripts/gen_synthetic_capture.py \
    --config configs/rx_prn1_sn193982.yaml \
    --snr-db 10 \
    --duration 2
```

输出文件 stem 末尾带 `_synthetic` 标签，格式与真实采集完全一致。

**gen_synthetic_capture.py 参数：**

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `--config` | `configs/rx_prn1_sn193982.yaml` | 复用采样率、中心频率等参数 |
| `--snr-db` | `10` | 信噪比（dB），降到 0 可测算法鲁棒性 |
| `--duration` | `2.0` | 信号时长（秒） |
| `--amplitude` | `1.0` | BPSK 幅度 |
| `--output-base-dir` | 配置文件中读取 | 覆盖输出根目录 |

**输出到临时目录：**

```bash
PYTHONPATH=/home/shen/projects/gnss_tx/src:src \
  python3 scripts/gen_synthetic_capture.py \
    --snr-db 20 \
    --duration 5 \
    --output-base-dir /tmp/gnss_synthetic
```

### MATLAB 离线分析

在 MATLAB 中运行（自动分析共享目录下最新文件）：

```matlab
result = run_capture_analysis();
```

分析指定文件（Linux VM 路径）：

```matlab
result = run_capture_analysis( ...
  '/mnt/hgfs/GongXiangDocument/GNSS_RX_Data/2026/2026_03_25/<stem>/<stem>');
```

分析指定文件（Windows 宿主机路径）：

```matlab
result = run_capture_analysis( ...
  'C:\VMwareVirtualMachines\GongXiangDocument\GNSS_RX_Data\2026\2026_03_25\<stem>\<stem>');
```

**预期结果：**

- `detected = true`，控制台打印 `捕获结果：成功`
- `multi_prn_survey.png`：PRN1 柱子明显高于红色阈值线（次峰比 ≥ 2.5），PRN2~32 接近噪底

---

## 运行测试

```bash
cd /home/shen/projects/GNSS_RX
PYTHONPATH=src python3 -m unittest discover -s tests -v
```

运行单个测试文件：

```bash
PYTHONPATH=src python3 -m unittest tests.test_writer -v
PYTHONPATH=src python3 -m unittest tests.test_runtime -v
PYTHONPATH=src python3 -m unittest tests.test_metadata -v
PYTHONPATH=src python3 -m unittest tests.test_record_rx -v
PYTHONPATH=src python3 -m unittest tests.test_flowgraph -v
```

---

## 输出文件说明

### 文件路径结构

```
<output_base_dir>/<YYYY>/<YYYY_MM_DD>/<stem>/<stem>.sc16
                                             <stem>.json
```

### stem 命名格式

```
<YYYYMMDD_HHMMSS>_rawiq_sc16_zeroif_prn<id>_<mode>_sr<rate>_cf<freq>_dur<dur>s
```

示例：

```
20260325_143000_rawiq_sc16_zeroif_prn1_spread_sr4092000_cf100000000_dur2p0s
```

| 片段 | 含义 |
|------|------|
| `20260325_143000` | 录制开始时间戳 |
| `rawiq` | 原始 IQ 数据标识 |
| `sc16` | 样本格式 |
| `zeroif` | 零中频模式 |
| `prn1` | PRN 编号 |
| `spread` | 信号模式 |
| `sr4092000` | 采样率 4.092 MHz |
| `cf100000000` | 中心频率 100 MHz |
| `dur2p0s` | 时长 2.0 秒（小数点替换为 `p`） |

### `.sc16` 文件格式

- 纯二进制，无文件头
- Little-endian signed int16，交织排列：`I0, Q0, I1, Q1, ...`
- 量化范围 `[-32767, 32767]` 对应归一化 `[-1.0, 1.0]`
- 文件大小 = `samples_captured × 4` 字节

### `.json` sidecar 示例

```json
{
  "antenna": "RX2",
  "bandwidth_hz": 4092000.0,
  "center_freq_hz": 100000000.0,
  "complex_layout": "iq_int16_interleaved_le",
  "data_file": "20260325_143000_rawiq_sc16_zeroif_prn1_spread_sr4092000_cf100000000_dur2p0s.sc16",
  "duration_s": 2.0,
  "prn_id": 1,
  "rx_gain_db": 20.0,
  "sample_format": "sc16",
  "sample_rate_hz": 4092000.0,
  "samples_captured": 8184000,
  "signal_mode": "spread",
  "tx_profile_reference": "../gnss_tx/configs/tx_b210_visible_spectrum.yaml",
  "usrp_addr": "type=b200",
  "zero_if": true
}
```

---

## 目录布局约定

`gnss_tx` 和 `GNSS_RX` 应为兄弟目录：

```
projects/
├── gnss_tx/
└── GNSS_RX/
```

`tx_profile_reference` 使用相对路径 `../gnss_tx/` 引用 TX 配置。

---

## 首次配置检查清单

```bash
# 1. 检查 UHD 设备
uhd_find_devices

# 2. 确认数据目录可写
export GNSS_RX_DATA_DIR=/home/shen/gnss_data
mkdir -p $GNSS_RX_DATA_DIR

# 3. dry-run 验证配置无误
PYTHONPATH=src python3 scripts/record_rx.py --dry-run

# 4. 运行测试套件
PYTHONPATH=src python3 -m unittest discover -s tests -v

# 5. 生成合成数据（无需硬件）
PYTHONPATH=/home/shen/projects/gnss_tx/src:src \
  python3 scripts/gen_synthetic_capture.py \
    --output-base-dir /tmp/gnss_synthetic

# 6. 正式采集（需连接 USRP）
PYTHONPATH=src python3 scripts/record_rx.py
```

---

## 实验流程参考

| 阶段 | 操作 |
|------|------|
| Tone bring-up | 发射单音，录制 2 秒，用 FFT 确认窄峰 |
| Spread capture | 切回 spread 模式，录制 2 秒 |
| MATLAB acquisition | 运行 `run_capture_analysis()`，检查 PRN1 捕获峰值 |
| 硬件回环验证 | TX→30~50 dB 衰减器→RX2，预期与软件回环结果一致 |

详细说明见 [docs/experiment_workflow.md](docs/experiment_workflow.md)。

技术实现细节见 [docs/receiver_overview.md](docs/receiver_overview.md)。
