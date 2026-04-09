# 采集数据源格式说明

> 适用版本：BER 闭环分析流程（2026-03-31 口径）
> 入口脚本：`matlab/ber.m` → `matlab/scripts/run_ber_loopback.m`

---

## 概述

每次 BER 闭环采集产生**三个文件**，它们共用同一个 stem 名称，放在同一个 `<capture_dir>/` 下：

```
<capture_dir>/
  <stem>.sc16            ← 原始 IQ 采集数据（二进制）
  <stem>.json            ← 采集元数据（文本 JSON）
  <stem>_tx_truth.json   ← TX 发射真值契约（文本 JSON）
```

这三个文件由以下两端分别生成：

- **TX 端**：`gnss_tx/scripts/run_tx.py --export-truth-json` 导出 `_tx_truth.json`
- **RX 端**：`GNSS_RX/scripts/record_rx.py` 写入 `.sc16` 和 `.json`

MATLAB 侧的读取入口：
- `.sc16` + `.json` → `matlab/functions/load_gnss_rx_capture.m`
- `_tx_truth.json` → `matlab/functions/load_tx_truth_json.m`

---

## 1. `<stem>.sc16` — 原始 IQ 数据

| 属性 | 值 |
|------|-----|
| 格式 | SC16（Signed Complex 16-bit） |
| 编码 | 每个复数样本 = 2 × int16，I 在前 Q 在后，**交织存储** |
| 字节序 | Little-endian |
| 归一化 | MATLAB 读入后除以 32767，范围归一化到 `[-1, 1]` |
| 典型采样率 | 4.092 Msps（`sample_rate = 4092000`） |

读入后组合为复数基带列向量：

```
samples = I_samples + j·Q_samples
```

文件大小参考（`4.092 Msps` 口径）：

| 时长 | 文件大小（十进制） | 文件大小（二进制） |
|------|-------------------|-------------------|
| 30 s | 约 0.49 GB | 约 0.46 GiB |
| 100 s | 约 1.64 GB | 约 1.52 GiB |
| 250 s | 约 4.09 GB | 约 3.81 GiB |
| 30 min | 约 29.46 GB | 约 27.44 GiB |
| 45 min | 约 44.19 GB | 约 41.16 GiB |
| 60 min | 约 58.92 GB | 约 54.88 GiB |

长时采集（≥ 30 min）推荐使用 `--capture-mode chunked --chunk-duration 30`，避免单文件读入 OOM。

---

## 2. `<stem>.json` — 采集元数据

由 `record_rx.py` 写入，格式为普通 JSON 对象。MATLAB 侧由 `load_gnss_rx_capture.m` 用 `jsondecode` 解析为结构体 `meta`。

关键字段：

| 字段 | 含义 |
|------|------|
| `samples_captured` | 文件内实际复数样本数（MATLAB 会与读取值交叉验证） |
| `sample_rate_hz` | IQ 采样率（Hz），基线为 `4092000` |
| `capture_started_at_iso` | 精确采集开始时间（ISO 8601），亚秒精度；文件名中的时间戳仅精确到秒 |

其余字段（中心频率、增益等）由 `configs/rx_baremetal.yaml` 写入，供诊断用。

---

## 3. `<stem>_tx_truth.json` — TX 真值契约

由 TX 侧 `run_tx.py --export-truth-json <path>` 在**正式采集前**导出（推荐与 capture 同目录，以 `_tx_truth.json` 结尾）。它是 BER 计算的"标准答案"，记录了 TX 发射时使用的导航比特序列和起始状态。

MATLAB 侧由 `load_tx_truth_json.m` 解析，缺少任何必需字段都会报错退出。

必需字段：

| 字段 | 类型 | 含义 |
|------|------|------|
| `nav_bits_pattern_pm1` | 数组 | 导航比特序列，+1/−1 表示 |
| `nav_bits_pattern_01` | 数组 | 同上，0/1 表示 |
| `initial_code_phase` | 数值 | 采集起点对应的初始码相位（以采样点数为单位） |
| `initial_nav_epoch` | 数值 | 采集起点对应的初始导航 epoch（以 1 ms 计） |
| `initial_nav_bit_index` | 数值 | 采集起点对应的导航比特索引（循环计数） |
| `samples_per_chip` | 数值 | 每个 C/A 码片的采样数，基线为 `4` |
| `sample_rate` | 数值 | IQ 采样率，基线为 `4092000` |
| `epochs_per_bit` | 数值 | 每个导航比特包含的 epoch 数，GPS L1 C/A 为 `20` |
| `prn_id` | 数值 | 对应卫星 PRN 编号，基线为 `1` |

---

## 4. 文件名规范

当前推荐的 stem 命名格式（runbook §11.1 口径）：

```
{RUN_TS}_{label}_prn{n}_spread_sr4p092e6_cf100e6_d{dur}s
```

示例（250 s 采集）：

```
20260331_190530_ber250s_prn1_spread_sr4p092e6_cf100e6_d250s
```

- `RUN_TS`：秒级时间戳，用于将 capture 与 sidecar truth 绑定
- 精确开始时间写入 `.json` 的 `capture_started_at_iso` 字段
- chunked 模式下各 chunk 会自动在 stem 后追加序号后缀

---

## 5. Truth 文件发现优先级

`run_ber_loopback.m` 在 Step 2.5 按以下顺序查找 truth，找到即停：

1. `{stem}_tx_truth.json`（sidecar，**最高优先**，推荐）
2. `{stem}.truth.json`
3. `{capture_dir}/tx_truth.json`
4. `{capture_dir}/ber_truth.json`
5. MATLAB workspace 根目录 fallback `tx_truth.json`
6. `build_fallback_tx_truth()`（内置默认 8-bit pattern，仅排障）

推荐始终使用第 1 种（sidecar），通过 `--export-truth-json "$TRUTH_PATH"` 在正式采集前导出到同目录。

---

## 6. 三件套完整性验证（MATLAB）

```matlab
exist([CAPTURE_STEM '.sc16'],          'file')   % 期望返回 2
exist([CAPTURE_STEM '.json'],          'file')   % 期望返回 2
exist([CAPTURE_STEM '_tx_truth.json'], 'file')   % 期望返回 2

truth = load_tx_truth_json([CAPTURE_STEM '_tx_truth.json']);
disp(truth.prn_id)       % 期望输出 1（当前基线）
disp(truth.sample_rate)  % 期望输出 4092000（当前基线）
```

以上均通过后，再运行正式 `ber`。

---

## 参考

- 采集入口：`GNSS_RX/scripts/record_rx.py`
- TX truth 导出：`gnss_tx/scripts/run_tx.py --export-truth-json`
- MATLAB 读取：`matlab/functions/load_gnss_rx_capture.m`、`matlab/functions/load_tx_truth_json.m`
- 完整执行流程：`experiments/plans/2026-03-31/ber_loopback_rx/2026-03-31_ber_loopback_end_to_end_joint_runbook.md`
