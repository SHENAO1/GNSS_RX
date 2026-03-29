# USRP TX Underflow / RX Overflow 同步现象根因分析

日期：2026-03-29
关联实验：BER Loopback 闭环验证

---

## 现象

### TX 端（usrp_sink underflow）

```
[INFO] Python TX runtime actual sample rate: 4092000.026 Sps (4.092000 Msps)
Uusrp_sink :error: In the last 70042 ms, 1 underflows occurred.
UUUUUUUUUusrp_sink :error: In the last 41447 ms, 7 underflows occurred.
UUUUUUUUUUUUUUUUUusrp_sink :error: In the last 36322 ms, 18 underflows occurred.
UUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUusrp_sink :error: In the last 31494 ms, 25 underflows occurred.
Uusrp_sink :error: In the last 25833 ms, 17 underflows occurred.
UUUusrp_sink :error: In the last 5626 ms, 3 underflows occurred.
UUUUUUUUusrp_sink :error: In the last 5802 ms, 2 underflows occurred.
UUUUUUUUusrp_sink :error: In the last 52221 ms, 7 underflows occurred.
UUusrp_sink :error: In the last 21809 ms, 8 underflows occurred.
[SUCCESS] Transmission finished cleanly.
```

### RX 端（usrp_source overflow）

```
Ousrp_source :error: In the last 32491 ms, 1 overflows occurred.
Ousrp_source :error: In the last 41534 ms, 1 overflows occurred.
Ousrp_source :error: In the last 36488 ms, 1 overflows occurred.
Ousrp_source :error: In the last 31192 ms, 1 overflows occurred.
Ousrp_source :error: In the last 25862 ms, 1 overflows occurred.
Ousrp_source :error: In the last 11395 ms, 1 overflows occurred.
Ousrp_source :error: In the last 52179 ms, 1 overflows occurred.
```

### 关键观察：两端时间间隔高度吻合

| TX underflow 间隔 (ms) | RX overflow 间隔 (ms) | 差值 (ms) |
|---|---|---|
| 41447 | 41534 | +87 |
| 36322 | 36488 | +166 |
| 31494 | 31192 | -302 |
| 25833 | 25862 | +29 |
| 52221 | 52179 | -42 |

误差均在几百毫秒以内，远小于事件间隔（25~52 秒），两端异常**由同一触发事件引起**。

---

## 硬件拓扑

`lsusb -t` 输出（关键部分）：

```
/:  Bus 004.Port 001: Dev 001, Class=root_hub, Driver=xhci_hcd/4p, 20000M/x2
    |__ Port 001: Dev 004, If 0-4, Class=Vendor Specific Class, Driver=[none], 5000M
    |__ Port 002: Dev 005, If 0-4, Class=Vendor Specific Class, Driver=[none], 5000M
```

- **Dev 004**（Port 001）= B210 TX
- **Dev 005**（Port 002）= B210 RX
- 两块设备均在 **Bus 004，同一 xhci_hcd controller** 下
- 各自以 5000M（USB 3.0 Gen 1）连接

---

## 根因分析

### 根因一：主机运行在 VMware 虚拟机（首要原因）

主机名明确标识为虚拟机：

```
shen@shen-VMware-Virtual-Platform
```

VMware Hypervisor 会周期性调度 vCPU，将虚拟机短暂暂停（vCPU preemption），在此期间：

- TX 进程无法向 USRP 喂样本 → TX buffer 饿空 → **underflow**
- RX 进程无法消费 USRP 样本 → RX buffer 撑满 → **overflow**

两件事在同一次 vCPU 冻结中同时发生，这是两端时间戳精确对齐的唯一合理解释。普通进程调度抖动或 Python GIL 不会产生如此精确的跨进程同步。

### 根因二：两块 B210 共享同一 USB Host Controller

两块 B210 均挂在 Bus 004（xhci_hcd）下，共享：

- 同一组 DMA 通道
- 同一组 USB 中断线
- 同一条 PCIe lane 的带宽（controller 到 CPU 侧）

当 controller 资源出现争用时，TX 和 RX 传输互相干扰，加剧抖动。

### 带宽估算（排除带宽瓶颈）

| 方向 | 计算 | 带宽 |
|---|---|---|
| TX（主机 → B210） | 4.092 Msps × 8 B/sample | ~32.7 MB/s |
| RX（B210 → 主机） | 4.092 Msps × 8 B/sample | ~32.7 MB/s |
| 合计 | | ~65.4 MB/s |

USB 3.0 实际有效吞吐 ~300 MB/s，远高于 65.4 MB/s。**带宽本身不是瓶颈**，问题在于 VMware vCPU 调度造成的实时性破坏。

---

## 排查步骤

1. 确认主机类型：

   ```bash
   hostnamectl | grep -i virtual
   systemd-detect-virt
   ```

2. 确认两块 B210 的 USB 拓扑：

   ```bash
   lsusb -t
   ```

   检查是否在同一 Bus 下。

3. 监控 VM 的 CPU steal time（如在 VM 内运行 `vmstat 1` 或 `top`，观察 `st` 列）。

4. 对比实验：在裸机上运行同一 TX/RX 脚本，观察 underflow/overflow 是否消失。

---

## 缓解与根本解法

| 方案 | 效果 | 可操作性 |
|---|---|---|
| **裸机运行**（推荐） | 彻底消除 Hypervisor 抢占 | 需要物理机 |
| USB Controller 分离（两块 B210 接不同 controller） | 减少双向竞争 | 受限于主机接口布局 |
| VMware CPU 独占绑定 + 禁用 CPU 热插拔 | 减少抢占频率 | 配置复杂，无法完全消除 |
| 增大 UHD TX/RX buffer size | 容忍更大的单次抖动 | 立即可用，治标 |
| 降低采样率 | 降低实时压力 | 影响实验条件 |

---

## 与已有文档的关系

| 文档 | 侧重点 |
|---|---|
| 本文 | 分析**为什么**发生 underflow/overflow（根因：VMware + 共享 USB controller） |
| [`2026-03-28_overflow_handling_notes.md`](../../../gnss_tx/experiments/plans/2026-03-28/ber_loopback_tx/2026-03-28_overflow_handling_notes.md) | 分析**发生后**如何处理及对 BER 测量结果的污染影响 |

两份文档互为补充，建议一起参考。
