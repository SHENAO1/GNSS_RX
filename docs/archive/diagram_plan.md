# GNSS TX/RX 项目 Draw.io 图表规划方案

## 项目简介

本项目是一个完整的 **GPS L1 C/A 信号软件无线电（SDR）收发平台**，包含：
- **gnss_tx**：GPS 信号发射机（Python + GNU Radio + USRP B210）
- **GNSS_RX**：GPS 信号接收机 + MATLAB 离线分析

---

## 已有 Draw.io 图（无需重复绘制）

| 文件 | 内容 |
|------|------|
| `gnss_tx/docs/system_architecture.drawio` | 系统总架构泳道图（TX/RF/RX/MATLAB 四泳道） |
| `gnss_tx/docs/gnss_tx_signal_chain.drawio` | 发射机信号处理链（配置→信号生成→GNU Radio→USRP） |
| `GNSS_RX/docs/system_architecture.drawio` | 接收机系统架构（配置/采集/落盘/MATLAB分析/BER） |
| `GNSS_RX/docs/tx_rx_end_to_end_signal_chain.drawio` | 端到端信号链完整流程 |

---

## 新增 Draw.io 图（本次创建）

### 图4：软件模块依赖图（Software Module Architecture）
**文件**：`GNSS_RX/docs/software_module_dependency.drawio`

**目的**：展示两个子项目的代码层次结构和 import 依赖关系，帮助软件工程师快速理解代码组织方式。

**内容**：
- 左栏：gnss_tx 模块树（ca → nav → signal → gr → usrp 的分层依赖）
- 右栏：gnss_rx 模块树（utils → runtime/metadata/writer → flowgraph）
- 跨项目依赖：`gen_synthetic_capture.py` → gnss_tx 模块

---

### 图5：数据格式演变图（Data Format Lifecycle）
**文件**：`GNSS_RX/docs/data_format_lifecycle.drawio`

**目的**：清晰展示信号数据在整个处理链中的格式转换，对理解量化、存储效率很有帮助。

**三条泳道**：
1. TX 软件层：`int8(±1)` → `complex64` → 幅度缩放
2. 硬件层：`fc32` → DAC → RF → ADC → `fc32`
3. RX 软件层：`complex64` → `SC16(int16)` → `.sc16文件` → MATLAB `fc32`

**关键参数**：SC16_SCALE=32767，采样率=4.092 MHz，4 MB/s 存储速率

---

### 图6：实验工作流（Experiment Workflow）
**文件**：`GNSS_RX/docs/experiment_workflow.drawio`

**目的**：展示工程师如何使用整个系统进行实验，包含决策分支和迭代循环。

**内容**：
- 选择配置文件（6种TX + 5种RX）
- --dry-run 验证 → 配置检查
- 硬件是否可用的分支（有硬件 vs gen_synthetic_capture.py 软件仿真）
- TX/RX 同步采集
- MATLAB 分析（PRN捕获 → DLL/PLL跟踪 → BER评估）
- 参数调整迭代循环

---

## 所有图的配色规范

| 颜色 | 含义 |
|------|------|
| 黄色 `#FFF2CC` / `#D6B656` | 配置文件 / YAML |
| 蓝色 `#DAE8FC` / `#6C8EBF` | Python 软件模块 |
| 绿色 `#D5E8D4` / `#82B366` | 文件/数据存储 |
| 紫色 `#E1D5E7` / `#9673A6` | MATLAB 分析 |
| 橙色 `#FFE6CC` / `#D79B00` | USRP 硬件 |
| 红色 `#F8CECC` / `#B85450` | 硬件层 / RF |

---

## 建议介绍顺序

向他人介绍时，建议按以下顺序展示：

1. `system_architecture.drawio`（gnss_tx/docs/）→ 建立全局认知（30秒）
2. `gnss_tx_signal_chain.drawio` → 深入 TX 信号处理
3. `system_architecture.drawio`（GNSS_RX/docs/）→ 深入 RX 采集流程
4. `data_format_lifecycle.drawio` → 数据格式转换细节
5. `software_module_dependency.drawio` → 代码结构（给软件工程师）
6. `experiment_workflow.drawio` → 演示如何使用系统
