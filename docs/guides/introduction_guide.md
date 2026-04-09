# GNSS_RX 介绍指南

> **文档用途**：向他人介绍接收端及完整系统时的讲解导引，配合 Draw.io 图表按顺序展示。
> 发射端专项介绍见 [`gnss_tx/docs/introduction_guide.md`](../../../gnss_tx/docs/introduction_guide.md)。

---

## 一句话描述（整体系统）

> 本项目是一套基于 **GNU Radio + USRP B210** 的 GPS L1 C/A 软件无线电实验平台：从零生成、发射、接收，并定量分析 GPS 信号，全链路完全可控。

---

## 第三步：接收链与数据存储（8 分钟）

**图表**：[`system_architecture.drawio`](../diagrams/system_architecture.drawio)

讲解接收端的三个关键设计决策：

### 决策 1：GNU Radio 流图保持极简

```
uhd.usrp_source → head block → Sc16CaptureSink → .sc16 文件
```

- **不做任何信号处理**，原始 IQ 全部落盘，保留后处理的完整灵活性
- `head block`：精确门控样本数（`duration_s × sample_rate_hz`），防止存储爆炸

### 决策 2：SC16 量化存储

| 格式 | 字节/样本 | 场景 |
|------|-----------|------|
| fc32（float complex） | 8 | 软件算法计算 |
| sc16（int16 交织） | 4 | UHD 传输 + 磁盘存储 |

量化公式：`clip(I/Q, [−1, 1]) × 32767 → int16`，存储效率提升 50%，4 MB/s 连续写入速率。

### 决策 3：JSON Sidecar 元数据

每个 `.sc16` 文件自动配对一个 `.json`，记录：

| 字段 | 用途 |
|------|------|
| `sample_rate_hz`, `center_freq_hz` | 时间/频率还原基准 |
| `prn_id` / `prn_ids` | 信号源识别 |
| `capture_started_at_iso` | 实验时间戳 |
| `tx_profile_reference` | 对应发端配置文件路径 |
| `usrp_addr`, `rx_gain_db`, `antenna` | 硬件状态快照 |

保证实验**完整可复现**，MATLAB 分析时无需额外输入参数。

**两种采集模式**：
- `single`：一段连续采集，生成单个文件对
- `chunked`：按 `chunk_duration_s` 分块，适合长时间采集，生成带 `capture_group_id` 的文件组

---

## 第四步：数据格式全链路追踪（5 分钟）

**图表**：[`data_format_lifecycle.drawio`](../diagrams/data_format_lifecycle.drawio)

三泳道图展示数据格式在整个系统中的演变：

```
TX 软件层：  int8(±1) → complex64 → complex64（× 0.25 缩放）
                                            ↓
硬件层：     fc32 ──[DAC]── RF 模拟 ──[ADC]── fc32
                                            ↓
RX 软件层：  fc32 → SC16(int16) → .sc16 → MATLAB fc32 → BER
```

**关键转换节点**（逐一标注）：

| 位置 | 转换 | 目的 |
|------|------|------|
| TX 信号生成 | `int8 → complex64` | 从二值扩展到复数采样，适配 GNU Radio |
| UHD 传输 | `fc32 → sc16` | USB 3.0 带宽减半 |
| RX Writer | `clip×32767 → int16` | 4 MB/s 磁盘写入 |
| MATLAB 加载 | `sc16 ÷ 32767 → fc32` | 恢复浮点精度，精度损失极小 |

---

## 第五步：实验工作流（5 分钟）

**图表**：[`experiment_workflow.drawio`](../diagrams/experiment_workflow.drawio)

展示工程师如何使用这套系统进行实验：

```
选配置文件（6种TX / 5种RX）
        ↓
  --dry-run 验证
        ↓
   硬件可用？
   否 ↓          ↓ 是
软件仿真        TX（run_tx.py）
(gen_synthetic   ← 同步 →
_capture.py)    RX（record_rx.py）
        ↓
  .sc16 + .json
        ↓
MATLAB run_capture_analysis.m
  ├─ PRN 捕获（码相位 + 多普勒）
  ├─ DLL/PLL 跟踪
  └─ BER 评估
        ↓
  调整参数 → 迭代
```

**亮点**：软件仿真路径（`gen_synthetic_capture.py`）无需任何硬件即可完整走通整条链路——适合算法开发和 CI/CD 自动化测试。

```bash
# 软件仿真示例（无硬件）
PYTHONPATH=/home/shenao/projects/gnss_tx/src:src \
  python3 scripts/gen_synthetic_capture.py --snr-db 10 --duration 2
```

---

## 第六步：代码结构（按需，面向软件工程师）

**图表**：[`software_module_dependency.drawio`](../diagrams/software_module_dependency.drawio)

两个子项目的分层模块依赖关系：

**gnss_tx（从下到上）**：
```
基础层：  ca/prn_generator.py   nav/nav_bits.py
                    ↓
信号层：  signal/spreader.py → signal/multi_sat_combiner.py
                    ↓
集成层：  gr/top_block.py  +  usrp/b210_sink.py
                    ↓
入口层：  usrp/tx_controller.py → scripts/run_tx.py
```

**GNSS_RX（从下到上）**：
```
基础层：  utils/io.py
              ↓
核心层：  runtime.py  writer.py  metadata.py
              ↓
顶层：    flowgraph.py（GNU Radio 集成）
              ↓
入口层：  scripts/record_rx.py
```

**跨项目依赖**（虚线）：`gen_synthetic_capture.py` 直接 import gnss_tx 的 `GpsL1CaBpskGenerator` 和 `build_multi_sat_replay_samples`。

---

## 系统技术亮点（汇总）

### 完全可控的闭环实验链
- 发端参数（PRN、导航数据、功率）全部已知 → 与接收端做精确 BER 对比
- 两种链路模式：有线回环（隔离变量）/ OTA（真实空口）

### 多星仿真能力
- 单台 USRP B210 同时模拟最多 32 颗 GPS 卫星信号
- √N 归一化：利用 C/A 码伪正交性合理控制峰均比

### 软硬件解耦设计
- `gen_synthetic_capture.py`：无硬件完整链路仿真
- YAML + CLI：任意参数调整无需改代码
- `--dry-run`：无硬件验证配置合法性

### 数据格式工程
- fc32（算法层）↔ sc16（传输/存储层）有意识分离
- JSON Sidecar 确保实验完整可复现
- 4 MB/s 存储率，长时间连续采集可行

---

## 常用命令

```bash
cd ~/projects/GNSS_RX
source .venv/bin/activate

# 环境自检
PYTHONPATH=src python3 scripts/quick_check.py

# 验证配置（无硬件）
PYTHONPATH=src python3 scripts/record_rx.py --dry-run

# 真实硬件采集
PYTHONPATH=src python3 scripts/record_rx.py \
    --config configs/rx_prn1_capture.yaml

# 软件仿真（无硬件，SNR = 10 dB，2 秒）
PYTHONPATH=/home/shenao/projects/gnss_tx/src:src \
    python3 scripts/gen_synthetic_capture.py --snr-db 10 --duration 2
```

```matlab
% MATLAB 离线分析
addpath(genpath('./matlab'))
run_capture_analysis()
```

---

## 常见问题

**Q：和真实 GPS 接收机有什么区别？**
A：真实 GPS 信号还需处理卫星运动（多普勒 ±4 kHz）、大气延迟、弱信号（约 −130 dBm）等复杂因素。本平台专注验证扩频、同步、解调等核心算法的正确性，信道模型可按需叠加。

**Q：为什么 RX 不做实时解调，非要离线 MATLAB？**
A：采集（Python + GNU Radio）和分析（MATLAB）分离是有意为之：原始 IQ 落盘后，算法可以反复迭代而不需要重复硬件实验；MATLAB 丰富的信号处理工具箱和可视化也更适合算法开发阶段。

**Q：系统能用于什么研究？**
A：可研究 GPS 接收机算法（捕获、跟踪、定位）、抗干扰技术、多路径效应、弱信号处理，也可作为 GNSS 教学实验平台。

---

## 图表文件索引

| 图表 | 文件 | 展示重点 |
|------|------|---------|
| 系统总架构 | [`gnss_tx/docs/system_architecture.drawio`](../../../gnss_tx/docs/system_architecture.drawio) | 全局4泳道，开场首选 |
| TX 信号链 | [`gnss_tx/docs/gnss_tx_signal_chain.drawio`](../../../gnss_tx/docs/gnss_tx_signal_chain.drawio) | C/A码→扩频→GNU Radio |
| 端到端信号链 | [`tx_rx_end_to_end_signal_chain.drawio`](../diagrams/tx_rx_end_to_end_signal_chain.drawio) | 跨两项目完整链路 |
| RX 系统架构 | [`system_architecture.drawio`](../diagrams/system_architecture.drawio) | 接收/落盘/MATLAB |
| 数据格式演变 | [`data_format_lifecycle.drawio`](../diagrams/data_format_lifecycle.drawio) | int8→fc32→sc16→fc32 |
| 软件模块依赖 | [`software_module_dependency.drawio`](../diagrams/software_module_dependency.drawio) | 两项目代码层次结构 |
| 实验工作流 | [`experiment_workflow.drawio`](../diagrams/experiment_workflow.drawio) | 操作步骤与决策分支 |

---

## 深入阅读

| 文档 | 内容 |
|------|------|
| [`README.md`](../README.md) | 完整技术参考，含信号处理公式和数据格式规范 |
| [`receiver_overview.md`](../reference/receiver_overview.md) | Python 包结构与数据流设计 |
| [`experiment_workflow.md`](experiment_workflow.md) | 逐步操作手册 |
| [`capture_data_format.md`](../reference/capture_data_format.md) | SC16/fc32 格式详解 |
| [`gnss_tx/docs/introduction_guide.md`](../../../gnss_tx/docs/introduction_guide.md) | 发射端专项介绍 |
