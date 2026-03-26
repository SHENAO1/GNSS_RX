# 发端/收端开发改进计划

> 创建时间：2026-03-26 （初始化）
> 维护规则：每天实验结束后更新"进行中"和"已完成"状态，新计划条目追加到对应优先级分区
> 配套文档：[gnss_tx/experiments/2026-03-26_tx_rx_improvement_plan.md](/home/shen/projects/gnss_tx/experiments/2026-03-26_tx_rx_improvement_plan.md)

---

## 状态说明

| 标记 | 含义 |
|------|------|
| `[ ]` | 待开始 |
| `[~]` | 进行中 |
| `[x]` | 已完成 |
| `[!]` | 阻塞/问题待解决 |

---

## 当前已验证基线（截至 2026-03-26）

- [x] TX PRN1 单星可见谱（tx_gain=20dB, amplitude=1.0）
- [x] TX PRN 1,5,10,15 四星子集发射（tx_gain=35dB, amplitude=0.5）
- [x] RX 单星 PRN1 捕获（次峰比 3.2，积分 20ms）
- [x] RX 四星子集同时捕获（tx_gain=35dB，次峰比 5.1~8.9，积分 10ms）
- [x] RX MATLAB 路径可移植性改造（环境变量 GNSS_RX_DATA_DIR）
- [x] 合成数据端到端验证（gen_synthetic_capture.py）

---

## 优先级 1：短期（本周内）

### 收端（GNSS_RX）

- [ ] **MATLAB 捕获热图可视化**
  - 问题：捕获只输出文字次峰比，无法直观观察旁瓣分布和多星干扰情况
  - 方案：生成代码延迟（横轴，chip）vs Doppler（纵轴，Hz）的 2D 相关能量热图，每颗 PRN 一张子图
  - 涉及文件：[matlab/run_capture_analysis.m](../matlab/run_capture_analysis.m)

- [ ] **CN0 估计**
  - 问题：次峰比依赖积分时间，不同实验横向对比困难
  - 方案：实现 Narrow-Wideband Power 法估计 CN0（dB-Hz），与真实 GPS 接收机指标对比更直观
  - 涉及文件：[matlab/](../matlab/)

### 发端（gnss_tx）

- [ ] **TX 启动时序同步**
  - 问题：GNU Radio 流图冷启动需 2~3 秒才出流，RX 采集窗口可能完全错过有效信号
  - 方案：在 `TxRuntimeConfig` 增加 `startup_silence_s` 参数，或 `run_tx.py` 在流图稳定后打印"TX READY"供 RX 对齐
  - 涉及文件：[../gnss_tx/src/gnss_tx/usrp/tx_controller.py](/home/shen/projects/gnss_tx/src/gnss_tx/usrp/tx_controller.py)

- [ ] **日志框架**
  - 问题：`utils/logging.py` 是空占位文件，当前全部用 `print` 输出
  - 方案：封装 Python 标准 `logging`，统一格式，支持 `--verbose` 开关
  - 涉及文件：[../gnss_tx/src/gnss_tx/utils/logging.py](/home/shen/projects/gnss_tx/src/gnss_tx/utils/logging.py)

---

## 优先级 2：中期（2~4 周）

### 收端（GNSS_RX）

- [ ] **DLL 码跟踪环（MATLAB）**
  - 方案：早-即-晚（E-P-L）相关器 + 归一化超前减滞后鉴别器 + 二阶环路滤波器
  - 前置：捕获热图（便于选取初始码相位）

- [ ] **PLL/FLL 载波跟踪环（MATLAB）**
  - 方案：FLL 辅助 PLL 结构，捕获阶段 FLL 牵引，稳定后切 PLL 精跟踪

- [ ] **导航比特同步**
  - 方案：检测 20ms 比特边界（积分翻转点），实现比特定时同步
  - 前置：DLL + PLL 跟踪稳定

### 发端（gnss_tx）

- [ ] **Timebase 管理（GPS 时间基准）**
  - 方案：实现 GPS Week + Time-of-Week 计数器
  - 涉及文件：[../gnss_tx/src/gnss_tx/utils/timebase.py](/home/shen/projects/gnss_tx/src/gnss_tx/utils/timebase.py)

- [ ] **真实 GPS 导航子帧（subframe_builder.py）**
  - 方案：实现 subframe 1（卫星时钟）+ subframe 2/3（轨道星历），静态固定参数版本
  - 前置：Timebase 管理
  - 涉及文件：[../gnss_tx/src/gnss_tx/nav/subframe_builder.py](/home/shen/projects/gnss_tx/src/gnss_tx/nav/subframe_builder.py)

- [ ] **每颗 PRN 独立幅度控制**
  - 方案：`per_prn_amplitude: {1: 0.8, 5: 0.6, ...}` YAML 配置支持
  - 涉及文件：[../gnss_tx/src/gnss_tx/signal/multi_sat_combiner.py](/home/shen/projects/gnss_tx/src/gnss_tx/signal/multi_sat_combiner.py)

- [ ] **GRC 流图多星支持**
  - 方案：更新 GRC 或新建多星流图，支持 GUI 快速 bring-up
  - 涉及文件：[../gnss_tx/flowgraphs/gnss_tx_main.grc](/home/shen/projects/gnss_tx/flowgraphs/gnss_tx_main.grc)

---

## 优先级 3：长期（1 个月以上）

### 收端（GNSS_RX）

- [ ] **导航电文解码（MATLAB）**
  - 方案：解析 subframe 1~3，提取时钟参数和星历
  - 前置：TX 真实子帧 + RX 比特同步

- [ ] **伪距测量**
  - 方案：从跟踪结果提取码相位，计算到各卫星的伪距

- [ ] **Python 实时捕获**
  - 方案：NumPy/SciPy 实现捕获算法，采集同时实时显示结果

- [ ] **定位解算（概念验证）**
  - 前提：≥4 颗 PRN 同时成功捕获 + 伪距测量
  - 方案：最小二乘定位解算

### 发端（gnss_tx）

- [ ] **Doppler 频移模拟**
  - 方案：`GpsL1CaBpskGenerator` 增加可配置 Doppler 偏移（±5 kHz）

- [ ] **伪距注入（码相位偏移）**
  - 方案：每颗 PRN 可配置码相位偏移，模拟传播延迟差异

- [ ] **多路 USRP 同步**
  - 方案：两台 B210 + OctoClock 同步发射

---

## 每日更新日志

### 2026-03-26 18:00

**今日总结**：
- 完成四星子集（PRN 1,5,10,15）端到端捕获实验，tx_gain=35dB 可实现 4/4 捕获（次峰比 5.1~8.9）
- 验证积分时间从 20ms 缩短到 10ms 仍可成功捕获（约 10× 速度提升）
- 完成 MATLAB 路径可移植性改造（环境变量 GNSS_RX_DATA_DIR）
- 初始化本计划文档

**关键发现**：
- TX 冷启动 2~3 秒延迟是主要捕获失败原因之一
- 多星叠加时每颗星有效幅度为 `amplitude / √N`，需提高增益补偿（35dB 可用）

**下一步**（明日优先）：
- MATLAB 捕获热图可视化
- TX 启动时序同步方案

---

<!-- 每日更新追加格式：

### YYYY-MM-DD HH:MM

**今日总结**：
- ...

**遇到的问题**：
- ...

**下一步**：
- ...

-->
