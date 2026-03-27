# experiments 目录说明

本目录用于记录 `GPS L1 C/A` 接收端采集与分析实验，不作为临时文档堆放区。

## 文件类型说明

- `YYYY-MM-DD_*checkpoint*.md`
  - 阶段性实验检查点，记录"某个配置或能力已被验证通过"的事实。
- `YYYY-MM-DD_*draft*.md`
  - 当天实验草稿，记录计划、待测组合和待回填字段。
- `YYYY-MM-DD_*archive*.md`
  - 当天任务归档，记录做了什么、结论是什么、后续待办是什么。
- `*_checklist.md`
  - 现场执行清单，避免漏步骤和漏记录。
- `plans/INDEX.md`
  - 本目录所有计划文件的汇总索引（开发日志式，含状态和跨项目引用）。
- `plans/YYYY-MM-DD/`
  - 按日期分组的详细实验计划文档。

## 推荐实验流程

1. 先运行接收端 dry-run，确认配置和设备发现输出是否合理
2. 发射端确认信号后，执行真实采集或生成合成数据
3. MATLAB 离线捕获与分析
4. 实验结束后回填记录：
   - 把已验证能力写入 checkpoint
   - 把当天过程和结论写入 archive

## 命名约定

- 日期前缀文件表示阶段性实验记录，例如 `2026-03-26_*`。
- `checkpoint` 表示"已经确认的事实"。
- `draft` 表示"正在执行或待回填的实验草稿"。
- `archive` 表示"当天工作的归档总结"。

## 当前文件列表

| 文件 | 类型 | 描述 |
|------|------|------|
| `2026-03-25_portability_refactor.md` | archive | 路径可移植性改造记录（5 处硬编码路径修复，11 个测试通过） |
| `2026-03-26_prn_subset_snr_debug.md` | archive | 多星子集（PRN1,5,10,15）捕获失败分析，成功配置存档（tx_gain=35） |
| `plans/INDEX.md` | index | 所有计划文件的汇总索引与开发日志 |
| `plans/2026-03-26_tx_rx_improvement_plan.md` | plan | TX/RX 综合改进计划，含优先级分级路线图 |
| `plans/2026-03-27/2026-03-27_ber_loopback_rx_plan.md` | plan | 接收端闭环 BER 验证计划（对应发端计划见 gnss_tx） |
| `plans/2026-03-27/2026-03-27_freq_offset_acquisition_stability.md` | plan | 人为频偏对捕获稳定性的影响研究计划 |
| `plans/2026-03-27/2026-03-27_lo_leakage_acquisition_study.md` | plan | 本振泄露对单星捕获影响的研究计划 |
| `plans/2026-03-27/2026-03-27_correlation_length_accumulation_study.md` | plan | 相关长度与积累策略对采集性能的影响研究计划 |

## Ubuntu 命令行快速入口

以下命令可直接在 Ubuntu 终端执行，建议都在项目根目录下运行：

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
