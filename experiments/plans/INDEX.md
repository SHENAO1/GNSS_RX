# Plans Index — GNSS_RX 接收端

本文件是 `GNSS_RX/experiments/plans/` 目录下所有计划文档的汇总索引，同时记录跨项目计划关联和开发进展日志。

---

## 进行中

| 文件 | 创建日期 | 描述 | 状态 |
|------|---------|------|------|
| [2026-03-26/tx_rx_improvement/2026-03-26_tx_rx_improvement_plan.md](2026-03-26/tx_rx_improvement/2026-03-26_tx_rx_improvement_plan.md) | 2026-03-26 | TX/RX 综合改进路线图（优先级分级，含短中长期任务） | 持续更新 |
| [2026-03-27/ber_loopback_rx/2026-03-27_ber_loopback_rx_plan.md](2026-03-27/ber_loopback_rx/2026-03-27_ber_loopback_rx_plan.md) | 2026-03-27 | Milestone 1 射频线直连闭环 BER 验证（收端视角） | `[ ]` 待执行 |
| [2026-03-27/ber_loopback_rx/2026-03-27_ber_loopback_impl_stages.md](2026-03-27/ber_loopback_rx/2026-03-27_ber_loopback_impl_stages.md) | 2026-03-27 | BER 闭环验证三阶段实施方案（合成数据 → 短时硬件 → 完整测量） | `[ ]` 阶段 0 待执行 |
| [2026-03-27/freq_offset_acquisition_stability/2026-03-27_freq_offset_acquisition_stability.md](2026-03-27/freq_offset_acquisition_stability/2026-03-27_freq_offset_acquisition_stability.md) | 2026-03-27 | 人为频偏对 GPS L1 C/A 捕获稳定性的影响研究 | `[ ]` 待执行 |
| [2026-03-27/lo_leakage_acquisition_study/2026-03-27_lo_leakage_acquisition_study.md](2026-03-27/lo_leakage_acquisition_study/2026-03-27_lo_leakage_acquisition_study.md) | 2026-03-27 | 本振泄露对单星捕获影响的研究 | `[ ]` 待执行 |
| [2026-03-27/correlation_length_accumulation_study/2026-03-27_correlation_length_accumulation_study.md](2026-03-27/correlation_length_accumulation_study/2026-03-27_correlation_length_accumulation_study.md) | 2026-03-27 | 相关长度与积累策略对采集性能的影响研究 | `[ ]` 待执行 |

---

## 已完成 / 归档

_暂无_

---

## 跨项目计划（Cross-project）

以下计划需要 TX 和 RX 两端协作执行，点击可跳转到对应项目文档：

| 计划名称 | 接收端（本项目） | 发射端（gnss_tx） |
|---------|---------------|----------------|
| Milestone 1：BER 闭环验证 | [2026-03-27_ber_loopback_rx_plan.md](2026-03-27/ber_loopback_rx/2026-03-27_ber_loopback_rx_plan.md) | [2026-03-27_ber_loopback_tx_plan.md](../../gnss_tx/experiments/plans/2026-03-27/ber_loopback_tx/2026-03-27_ber_loopback_tx_plan.md) |

> **相对路径说明**：上表中 gnss_tx 路径假设两个项目同级放置于 `~/projects/` 下。

---

## 更新日志

- **2026-03-27**：BER 闭环验证、频偏研究、LO 泄露研究、相关长度研究统一收纳到 `plans/2026-03-27/<topic>/`
- **2026-03-26**：TX/RX 综合改进路线图收纳到 `plans/2026-03-26/tx_rx_improvement/`
