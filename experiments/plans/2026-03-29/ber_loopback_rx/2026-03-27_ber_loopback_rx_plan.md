# 接收端实验计划：闭环 BER 验证（收端视角）

> 创建时间：2026-03-27
> 对应发射端计划：`/home/shen/projects/gnss_tx/experiments/plans/2026-03-27/ber_loopback_tx/2026-03-27_ber_loopback_tx_plan.md`
> 状态：`[~]` 历史主计划；基础能力已落地，当前执行以 2026-03-28 重构版为准
> 里程碑目标：Milestone 1 — 射频线直连闭环 BER 验证

---

## 当前文档定位

本文件保留 2026-03-27 当天的原始主计划语境，用于追溯最初的 BER 工作拆解。

截至 2026-03-28，以下事项已经发生变化：

- `recover_nav_bits.m` 与 `run_ber_loopback.m` 已不再是“待新建”
- RX 侧已新增 truth JSON 加载能力
- RX 侧已新增 `tracked_truth` 主链
- 采集端已支持 `single/chunked` 双模式

当前执行应优先参考：

- `/home/shen/projects/GNSS_RX/experiments/plans/2026-03-28/ber_loopback_rx/2026-03-28_ber_loopback_rx_plan.md`
- `/home/shen/projects/GNSS_RX/experiments/plans/2026-03-28/ber_loopback_rx/2026-03-28_ber_loopback_debug_playbook.md`

---

## 历史计划中的关键结论

这份计划中最有价值、至今仍然成立的判断有两点：

1. BER 工作应先把采集、捕获、比特恢复和统计拆开验证。
2. 必须先在短时样本上收敛，再扩展到长时间正式测量。

这些原则今天仍然适用，只是当前实现已经从“先补基础文件”推进到了“让 tracked BER 主链真正收敛”。

---

## 当前代码状态（对原计划的更新）

| 功能模块 | 当前状态 | 文件 |
|----------|----------|------|
| USRP B210 IQ 采集 | ✅ 已实现 | `scripts/record_rx.py` + `src/gnss_rx/flowgraph.py` |
| SC16 文件写入 + JSON 元数据 | ✅ 已实现 | `src/gnss_rx/metadata.py` |
| MATLAB 数据加载 | ✅ 已实现 | `matlab/functions/load_gnss_rx_capture.m` |
| MATLAB GPS L1 C/A 捕获 | ✅ 已实现 | `matlab/functions/run_prn_acquisition.m` |
| MATLAB open-loop BER 基线 | ✅ 已实现 | `matlab/functions/recover_nav_bits.m` |
| MATLAB tracked BER 主链 | ✅ 已实现 | `matlab/functions/track_nav_bits.m` |
| MATLAB BER 主脚本 | ✅ 已实现 | `matlab/scripts/run_ber_loopback.m` |

**结论：本页原先“需要新建 MATLAB 文件”的任务已经完成，当前重点是 30 s tracked BER 收敛。**
