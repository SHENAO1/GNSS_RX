# Plans Index — GNSS_RX 接收端

本文件是 `GNSS_RX/experiments/plans/` 目录下计划文档的汇总索引，同时记录跨项目关联和当前执行主线。

---

## 进行中

| 文件 | 创建日期 | 描述 | 状态 |
|------|---------|------|------|
| [2026-03-26/tx_rx_improvement/2026-03-26_tx_rx_improvement_plan.md](2026-03-26/tx_rx_improvement/2026-03-26_tx_rx_improvement_plan.md) | 2026-03-26 | TX/RX 综合改进路线图（优先级分级，含短中长期任务） | 持续更新 |
| [2026-03-27/ber_loopback_rx/2026-03-27_ber_loopback_rx_plan.md](2026-03-27/ber_loopback_rx/2026-03-27_ber_loopback_rx_plan.md) | 2026-03-27 | Milestone 1 射频线直连闭环 BER 验证（收端视角，历史主计划） | `[~]` 历史参考 |
| [2026-03-27/ber_loopback_rx/2026-03-27_ber_loopback_impl_stages.md](2026-03-27/ber_loopback_rx/2026-03-27_ber_loopback_impl_stages.md) | 2026-03-27 | BER 三阶段实施方案（阶段思想保留，已被后续实现更新） | `[~]` 历史参考 |
| [2026-03-28/ber_loopback_rx/2026-03-28_ber_loopback_rx_plan.md](2026-03-28/ber_loopback_rx/2026-03-28_ber_loopback_rx_plan.md) | 2026-03-28 | 当前 BER 主计划：truth JSON + tracked BER + 30 s 优先收敛 | `[~]` 当前执行主线 |
| [2026-03-28/ber_loopback_rx/2026-03-28_ber_loopback_debug_playbook.md](2026-03-28/ber_loopback_rx/2026-03-28_ber_loopback_debug_playbook.md) | 2026-03-28 | BER 排障操作手册，含 truth / tracked / chunked 当前流程 | `[~]` 当前排障手册 |
| [2026-03-27/freq_offset_acquisition_stability/2026-03-27_freq_offset_acquisition_stability.md](2026-03-27/freq_offset_acquisition_stability/2026-03-27_freq_offset_acquisition_stability.md) | 2026-03-27 | 人为频偏对 GPS L1 C/A 捕获稳定性的影响研究 | `[ ]` 待执行 |
| [2026-03-27/lo_leakage_acquisition_study/2026-03-27_lo_leakage_acquisition_study.md](2026-03-27/lo_leakage_acquisition_study/2026-03-27_lo_leakage_acquisition_study.md) | 2026-03-27 | 本振泄露对单星捕获影响的研究 | `[ ]` 待执行 |
| [2026-03-27/correlation_length_accumulation_study/2026-03-27_correlation_length_accumulation_study.md](2026-03-27/correlation_length_accumulation_study/2026-03-27_correlation_length_accumulation_study.md) | 2026-03-27 | 相关长度与积累策略对采集性能的影响研究 | `[ ]` 待执行 |

---

## 已完成 / 归档

_暂无_

---

## 跨项目计划

| 计划名称 | 接收端（本项目） | 发射端（gnss_tx） |
|---------|---------------|----------------|
| Milestone 1：BER 闭环验证 | [2026-03-28_ber_loopback_rx_plan.md](2026-03-28/ber_loopback_rx/2026-03-28_ber_loopback_rx_plan.md) | [2026-03-28_ber_loopback_tx_plan.md](../../gnss_tx/experiments/plans/2026-03-28/ber_loopback_tx/2026-03-28_ber_loopback_tx_plan.md) |

> 相对路径假设两个项目同级放置于 `~/projects/` 下。

---

## 更新日志

- **2026-03-28**：BER 文档体系已更新为 truth JSON + tracked BER + chunked capture 的当前代码状态
- **2026-03-27**：BER、频偏研究、LO 泄露研究、相关长度研究统一收纳到 `plans/2026-03-27/<topic>/`
- **2026-03-26**：TX/RX 综合改进路线图收纳到 `plans/2026-03-26/tx_rx_improvement/`
