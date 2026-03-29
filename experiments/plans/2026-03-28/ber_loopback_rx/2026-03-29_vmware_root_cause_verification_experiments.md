# VMware 根因验证实验设计

日期：2026-03-29
关联文档：[`2026-03-29_underflow_overflow_root_cause_analysis.md`](2026-03-29_underflow_overflow_root_cause_analysis.md)

---

## 背景

TX underflow 与 RX overflow 时间戳高度吻合（误差 < 500ms），初步判断根因为：

1. **主因**：VMware Hypervisor vCPU 调度周期性冻结 VM
2. **次因**：两块 B210 共享同一 USB Host Controller（Bus 004, xhci_hcd）

本文设计 4 个递进式实验，从无需额外硬件的快速验证到终极裸机对照，逐步确认根因。

---

## 实验 A：CPU Steal Time 监控

**难度**：低，VM 内即可，无需额外硬件
**目的**：获取 VMware vCPU 抢占的直接时间证据

### 原理

VMware 抢占 vCPU 时，Linux 内核将该时间计入 `%st`（steal time）。
若 `%st` 尖峰时刻与 underflow/overflow 报错时刻对齐，即为直接证据。

### 操作步骤

> 若未安装 `ts`，先执行：`sudo apt install moreutils`

**启动前 checklist（按顺序执行，缺一不可）：**

- [ ] 终端 3 已启动 `vmstat` 监控（**必须最先启动，否则缺少对齐数据，需重跑**）
- [ ] 终端 1 TX 已启动
- [ ] 终端 2 RX 已启动

---

**终端 3**（最先启动）：记录每秒 steal time

```bash
vmstat 1 | ts '[%Y-%m-%dT%H:%M:%.S]' > steal_time.log
```

**终端 1**：运行 TX，将输出重定向到日志并加时间戳

```bash
cd ~/projects/gnss_tx
PYTHONPATH=src python3 scripts/run_tx.py --config configs/tx_b210_cable_loopback.yaml --duration 300 2>&1 | ts '[%Y-%m-%dT%H:%M:%.S]' | tee tx_run.log
```

> 注意：**不要激活 venv**。GNU Radio 安装在系统 Python（`/usr/lib/python3/dist-packages/`），激活 venv 会隔离系统包导致 `gnuradio` 不可见。若当前已激活 venv，先执行 `deactivate`。

**终端 2**：运行 RX，同样加时间戳

```bash
cd ~/projects/GNSS_RX
PYTHONPATH=src python3 scripts/record_rx.py --config configs/rx_cable_loopback.yaml --duration 300 2>&1 | ts '[%Y-%m-%dT%H:%M:%.S]' | tee rx_run.log
```

### 采集数据文件清理

实验 A 的 RX 采集会产生约 **2.4 GB** 的 `.sc16` 文件（4.092 Msps × 4 B/sample × 300s）。验证完根因后可删除。

查找今日采集文件：

```bash
ls -lh /mnt/hgfs/GongXiangDocument/GNSS_RX_Data/2026/2026_03_29/
```

在文件管理器中打开该目录：

```bash
xdg-open /mnt/hgfs/GongXiangDocument/GNSS_RX_Data/2026/2026_03_29/
```

确认大小：

```bash
du -sh /mnt/hgfs/GongXiangDocument/GNSS_RX_Data/2026/2026_03_29/*/
```

确认无误后删除（文件名含 `dur300p0s` 的即为本次实验产物）：

```bash
rm -rf /mnt/hgfs/GongXiangDocument/GNSS_RX_Data/2026/2026_03_29/<目录名>/
```

---

### 比对方法

提取 underflow/overflow 发生的时刻：

```bash
grep -E "underflow|overflow" tx_run.log rx_run.log
```

在 steal_time.log 中，vmstat 输出格式为：
```
[时间戳]  r  b   swpd   free   ...  us sy id wa st
```
最后一列 `st` 为 steal time（%）。检查报错前后 1~2 秒内是否有 `st > 0`。

### 判读标准

| 观察结果 | 结论 |
|---|---|
| 每次报错前后 st 均有尖峰 | VMware vCPU 抢占确认为根因 |
| st 始终为 0，但报错仍存在 | VMware 调度不是直接原因，需查 USB 或其他 |
| st 偶有尖峰但与报错不对齐 | 相关性弱，VMware 可能只是次因 |

---

## 实验 B：人为加压（受控因果验证）

**难度**：低，VM 内即可
**目的**：通过主动调控 VM 负载，验证 underflow 频率与 vCPU 压力的因果关系

### 原理

增大 VM 内 CPU 负载 → Host 侧 vCPU 争用加剧 → steal time 增加 → 调度抖动更频繁 → underflow/overflow 更密集。
因果方向明确，结果可重复。

### 操作步骤

安装压力工具（若未安装）：

```bash
sudo apt install stress-ng
```

**阶段 1 - 基线**：正常运行 TX/RX，记录 10 分钟内 underflow/overflow 次数

**阶段 2 - 加压**：在额外终端运行，同时记录 TX/RX 日志：

```bash
stress-ng --cpu $(nproc) --timeout 300
```

**阶段 3 - 恢复**：停止 stress-ng，再记录 10 分钟，观察频率是否回落

### 判读标准

| 阶段对比 | 结论 |
|---|---|
| 加压后频率明显升高，恢复后回落 | 因果确认，VMware 调度是根因 |
| 加压后无明显变化 | VMware 调度不是主因，需调查其他因素 |

---

## 实验 C：USB Controller 分离

**难度**：中，需要换插 USB 接口
**目的**：验证两块 B210 共享 USB Controller 是主因还是次因

### 当前拓扑

```
Bus 004  xhci_hcd
 ├── Port 001: Dev 004 (B210 TX)  @ 5000M
 └── Port 002: Dev 005 (B210 RX)  @ 5000M
```

两块设备在同一 Controller 下，共享 DMA 通道和中断线。

### 操作步骤

1. 将其中一块 B210 拔出，换插到**物理上不同的 USB 接口**（查看机箱背板，找可能属于不同 Controller 的接口）

2. 运行 `lsusb -t`，确认两块 B210 分属不同 Bus：

   ```
   目标状态：
   Bus 003: ... B210 #1
   Bus 004: ... B210 #2
   ```

3. 若仍在同一 Bus，尝试其他接口，直到分离成功

4. 分离后以相同参数运行 TX/RX，记录 underflow/overflow 频率

### 判读标准

| 观察结果 | 结论 |
|---|---|
| 分离后 underflow/overflow 消失 | USB Controller 共享是主因 |
| 分离后减少但仍存在 | USB 竞争是次因，VMware 仍是主因 |
| 分离后无变化 | USB Controller 不是根因 |

---

## 实验 D：裸机对照（终极验证）

**难度**：高，需要物理机
**目的**：完全消除 Hypervisor，获得终极对照数据

### 原理

裸机无 Hypervisor 层，vCPU 抢占不存在，实时调度抖动来源只剩 OS 本身。
若 underflow/overflow 在相同配置下消失，完全确认 VMware 是根因。

### 操作步骤

1. 在物理机上安装 UHD + 相同 Python 依赖
2. 连接相同的两块 B210，运行完全相同的 TX/RX 脚本
3. 使用相同采样率（4.092 Msps），相同运行时长
4. 记录 underflow/overflow 频率

### 判读标准

| 观察结果 | 结论 |
|---|---|
| 裸机完全无报错 | VMware 是根因，结论成立 |
| 裸机仍有偶发报错但频率低得多 | VMware 是主要放大因素，系统本身也有轻微抖动 |
| 裸机与 VM 表现相同 | VMware 不是根因，需重新调查 |

---

## 推荐执行顺序

```
实验 A（steal time 监控）
    ↓ 若 st 尖峰对齐 → 根因确认，可选做 B 验证因果
    ↓ 若 st 始终为 0 → 做实验 C（USB 分离）
实验 B（人为加压）
    ↓ 进一步量化因果关系
实验 C（USB 分离）
    ↓ 确认次因贡献
实验 D（裸机对照）
    ↓ 终极确认
```

**最低投入验证**：仅做实验 A + B，VM 内即可完成，无需任何额外硬件或配置变更。
