# experiments 目录说明

本目录用于记录 `GPS L1 C/A` 接收端采集与分析实验，并统一按“类别 / 日期 / 主题”归档。

## 目录结构

- `records/YYYY-MM-DD/<topic>/`
  - 已验证事实、问题定位记录、阶段性归档。
- `plans/YYYY-MM-DD/<topic>/`
  - 研究计划、里程碑计划、跨项目协作路线图。
- `special/<topic>/`
  - 跨日期的专项分析、长期维护的判读口径、源码级专题研究。

## 当前目录索引

| 路径 | 类型 | 描述 |
|------|------|------|
| `records/2026-03-25/portability_refactor/2026-03-25_portability_refactor.md` | archive | 路径可移植性改造记录 |
| `records/2026-03-26/prn_subset_snr_debug/2026-03-26_prn_subset_snr_debug.md` | archive | 多星子集捕获失败分析与成功配置存档 |
| `plans/2026-03-26/tx_rx_improvement/2026-03-26_tx_rx_improvement_plan.md` | plan | TX/RX 综合改进路线图 |
| `plans/2026-03-27/ber_loopback_rx/2026-03-27_ber_loopback_rx_plan.md` | plan | 接收端闭环 BER 验证计划 |
| `plans/2026-03-27/freq_offset_acquisition_stability/2026-03-27_freq_offset_acquisition_stability.md` | plan | 人为频偏对捕获稳定性的影响研究 |
| `plans/2026-03-27/lo_leakage_acquisition_study/2026-03-27_lo_leakage_acquisition_study.md` | plan | 本振泄露对单星捕获影响研究 |
| `plans/2026-03-27/correlation_length_accumulation_study/2026-03-27_correlation_length_accumulation_study.md` | plan | 相关长度与积累策略研究 |
| `special/README.md` | special-index | 专项实验目录索引 |
| `special/rx_ber_judgement_logic/README.md` | special-study | 接收端 BER 判断逻辑专项分析 |
| `plans/INDEX.md` | index | 所有计划文件的汇总索引与跨项目入口 |

## 推荐实验流程

1. 先运行接收端 dry-run，确认配置和设备发现输出合理。
2. 发射端确认信号后，执行真实采集或生成合成数据。
3. MATLAB 离线捕获与分析。
4. 实验结束后回填：
   - 已验证事实写入 `records/`
   - 待执行与路线图写入 `plans/`
   - 跨多日复用的专题分析写入 `special/`

## Ubuntu 命令行快速入口

```bash
cd ~/projects/GNSS_RX
source .venv/bin/activate

# 1) 检查接收端配置（dry-run，不开 RF）
PYTHONPATH=src python3 scripts/record_rx.py --dry-run

# 2) 真实采集（需 TX 端同时运行）
PYTHONPATH=src python3 scripts/record_rx.py --config configs/rx_prn1_capture.yaml

# 3) 无硬件：生成合成数据
PYTHONPATH=/home/shen/projects/gnss_tx/src:src \
  python3 scripts/gen_synthetic_capture.py \
  --config configs/rx_prn1_sn193982.yaml \
  --snr-db 10 \
  --duration 2
```

MATLAB 分析：

```matlab
run_capture_analysis
```

## 写实验记录前先看

- 根流程说明见 [`../README.md`](../README.md)
- MATLAB 操作细节见 [`../matlab/README.md`](../matlab/README.md)
- 具体实验步骤模板见 [`../docs/experiment_workflow.md`](../docs/experiment_workflow.md)
- 跨项目计划列表见 [`plans/INDEX.md`](plans/INDEX.md)
