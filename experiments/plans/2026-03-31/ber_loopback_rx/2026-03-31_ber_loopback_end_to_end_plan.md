# 2026-03-31 闭环 BER 全链路总计划

> 创建时间：2026-03-31
> 对应总手册：`2026-03-31_ber_loopback_end_to_end_joint_runbook.md`
> 适用仓库：`GNSS_RX`

---

## 一、为什么要新增这份计划

到 2026-03-30 为止，闭环 BER 的关键信息分散在三类文档里：

- 裸机新电脑采集手册
- 已有样本的 MATLAB BER 分析手册
- TX/RX 联合执行手册

它们各自都有效，但组合使用时有 4 个实际问题：

- 阅读路径分散，执行时要在多个目录间来回跳
- 主力机 MATLAB 到底应该先跑 `ber` 还是 `run_capture_analysis()` 容易混淆
- `30 s -> 100 s -> 250 s -> 1 h` 的递进逻辑没有在一处完整收拢
- 新电脑、移动硬盘、主力机这三段交接流程分散描述，容易遗漏

因此 3.31 的目标不是改代码，而是把当前已经验证过的流程整理成：

- 一份共享总手册
- 一份总计划入口

---

## 二、旧文档各自保留什么价值

以下旧文档依然有价值，但不再作为首次执行时的主入口。

### 2.1 `2026-03-29_baremetal_capture_runbook.md`

保留价值：

- 新裸机 Ubuntu 的依赖安装顺序
- `--system-site-packages` 环境搭建细节
- B210 枚举、USB 3.x、移动硬盘转移经验

### 2.2 `2026-03-30_existing_capture_ber_analysis_runbook.md`

保留价值：

- `run_ber_loopback.m` 的正式 BER 分析口径
- `CAPTURE_PATH` / `TX_TRUTH_PATH` 的显式指定方式
- `tracked_truth` 与 `open_loop_truth` 的职责分工

### 2.3 `2026-03-28_ber_loopback_joint_runbook.md`

保留价值：

- TX / RX 联机操作顺序
- `30 s -> 250 s -> 1 h` 的递进逻辑
- 长时采集、本地落盘、chunked 的经验

---

## 三、3.31 采用的统一口径

### 3.1 文档布局

3.31 固定产出以下 3 个文件：

- `gnss_tx/experiments/plans/2026-03-31/ber_loopback_tx/2026-03-31_ber_loopback_end_to_end_joint_runbook.md`
- `GNSS_RX/experiments/plans/2026-03-31/ber_loopback_rx/2026-03-31_ber_loopback_end_to_end_joint_runbook.md`
- `GNSS_RX/experiments/plans/2026-03-31/ber_loopback_rx/2026-03-31_ber_loopback_end_to_end_plan.md`

其中：

- 两份 `joint_runbook` 内容必须完全一致
- `GNSS_RX` 侧额外保留本计划文件，作为索引与口径说明

### 3.2 正式 BER 入口

3.31 之后的正式 BER 口径统一为：

- 正式 BER：`ber` / `run_ber_loopback.m`
- 正式模式：`tracked_truth`
- 快速体检：`run_capture_analysis()`

必须明确：

- `ber` 才是正式闭环 BER 结论入口
- `run_capture_analysis()` 只用于加载、总览、捕获和 survey 的快速体检
- 需要正式结论时，默认显式给 `CAPTURE_PATH` + `TX_TRUTH_PATH`

### 3.3 时长递进策略

3.31 固定为：

- `30 s`：离线基线 + 联机复验
- `100 s`：过渡验证，确认“本地落盘 + 采后复制”链路
- `250 s`：正式 BER 验收区间
- `1 h`：长时稳定性验证，默认 `chunked`

### 3.4 长时采集默认方案

`1 h` 默认正式策略固定为：

- RX：`--capture-mode chunked --chunk-duration 30`
- TX：保持当前稳定基线
- `single` 只保留为 dry-run / 备选说明，不作为默认正式方案

### 3.5 平台写法

3.31 共享总手册正文同时覆盖：

- Windows 主力机
- Linux 主力机

其中 Windows 章节必须同时包含：

- 先拷到本地 SSD 再分析
- 直接从移动硬盘分析

但必须清楚标注：

- 本地 SSD 是推荐正式方案
- 移动硬盘直读仅用于临时复盘或空间不足时

---

## 四、标准化后的对外入口

本次只整理文档，不改代码接口；但从文档口径上，以下入口被标准化为唯一正式说法：

- TX 发射入口：`gnss_tx/scripts/run_tx.py`
- RX 采集入口：`GNSS_RX/scripts/record_rx.py`
- RX 裸机配置：`GNSS_RX/configs/rx_baremetal.yaml`
- TX 回环配置：`gnss_tx/configs/tx_b210_cable_loopback.yaml`
- MATLAB 同步入口：`GNSS_RX/scripts/sync_matlab.sh`
- MATLAB 正式 BER 入口：`GNSS_RX/matlab/ber.m`
- MATLAB BER 主脚本：`GNSS_RX/matlab/scripts/run_ber_loopback.m`
- MATLAB 快速体检入口：`GNSS_RX/matlab/scripts/run_capture_analysis.m`

---

## 五、阅读顺序与执行顺序

### 5.1 第一次执行

第一次拿新电脑从零开始时，直接读：

- `2026-03-31_ber_loopback_end_to_end_joint_runbook.md`

不再要求先跳到旧文档。

### 5.2 需要快速理解口径时

先看本计划，再进共享总手册。

### 5.3 需要深挖历史背景时

再回看旧文档：

- 3.29 裸机采集手册
- 3.30 已有样本 BER 分析手册
- 3.28 联合执行手册

---

## 六、正式验收门槛

正式 BER 样本的最小门槛固定为：

- TX 无 underflow
- RX 无 overflow
- MATLAB 日志显示 `TX truth：JSON 模式`
- 正式分析走 `tracked_truth`

当前默认结论是：

- `overflow / underflow` 是 BER 验收的首要闸门
- 不是 `tracked_truth` 主链本身仍然不通

因此如果样本本身已经发生连续性破坏，优先重采，不要先怀疑 truth JSON 或 BER 主链整体失效。

---

## 七、后续维护规则

3.31 之后，若这条链继续演进，默认维护策略如下：

- 优先更新共享总手册
- 不再新增新的“平行 runbook”来重复描述同一主线
- 若只是补背景、补专题、补根因分析，可继续写专题文档
- 但正式执行口径应回收至共享总手册

---

## 八、当前默认假设

- 本轮只新增文档，不改脚本行为
- `GNSS_RX` 侧只新增 1 份 plan
- 新总手册覆盖从新裸机电脑到 MATLAB 正式 BER 的完整链路
- 正式 BER 结论默认使用 `ber` / `run_ber_loopback.m` 的 `tracked_truth`
- `100 s` 保留为 `30 s -> 250 s` 的过渡关卡
- `1 h` 默认正式策略是 RX `chunked`

