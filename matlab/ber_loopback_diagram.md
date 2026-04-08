# ber_loopback.drawio 说明文档

> 对应流程图文件：`ber_loopback.drawio`（diagram id: `ber-loopback`）  
> 描述入口脚本：`run_ber_loopback.m`（由 `ber.m` 调用）  
> 信号链：GPS L1 C/A IQ 采集 → 捕获 → 解调 → 误码统计（BER）

---

## 整体结构

流程图共分 **8 个主步骤** + **1 条并行 truth 发现链**，其中 Step 3（open-loop）和 Step 4（tracked）是两条并行的比特恢复链路，最终汇聚到 Step 5 进行模式选择。

```
入口
 ├─→ Step 1: 加载采集数据
 │       ↓ samples（IQ 复数列）
 ├─→ Step 2: 捕获（前 100ms）
 │       ↓ acq_result（Doppler + 码相位）
 │
 ├──────────────────────────────────────────────────┐
 │  Step 3: Open-loop 诊断基线         Step 4: Tracked 主链
 │  recover_nav_bits                    track_nav_bits
 │  ① 1ms 复相关                        ① DLL 码跟踪
 │  ② 平方相位法估粗频偏                ② FLL-assisted PLL
 │  ③ 联合枚举搜索                      ③ 初始比特对齐
 │  ④ 多维评分函数                      ④ 比特时序稳定性检查
 │  ⑤ 最优候选输出                      ⑤ 20ms 积分 + BPSK 判决
 │                                       ⑥ BER 与滑动窗统计
 └──────────────────────────────────────────────────┘
          ↓ open_loop_result          ↓ tracked_result
         Step 5: truth 一致性判决（BER_MODE 选择）
                     ↓ selected_result
              Step 6: BER 统计
                     ↓
              Step 7: 可视化（plot_ber_loopback）
                     ↓
              Step 8: 可选保存 .mat
```

另有一条 **TX truth 发现链**（Step 2.5）在捕获完成后并行执行，向 Step 3-③ 和 Step 4-③ 分别注入 `truth_pattern`。

---

## 节点详解

### 入口
- 调用路径：`ber.m` → `run_ber_loopback.m`
- 关键输入变量：`CAPTURE_PATH`、`BER_MODE`、`ACCEL_OPTIONS`、`TRACKING_OPTIONS`
- 执行：`clearvars`、`addpath`、解析加速配置

### Step 1：加载采集数据
- 函数：`load_gnss_rx_capture(CAPTURE_PATH, precision)`
- 输出：`samples`（IQ 复数列）、`meta`（`fs`、`prn_id` 等）

### Step 2：GPS L1 C/A 捕获
- 函数：`run_prn_acquisition`，只使用前 100ms（`ACQ_DURATION_S=0.1`）
- 方法：2D 相关搜索（Doppler 频率 × 码相位）
- 输出：`best_doppler_hz`、`best_code_phase`、`detected`、`second_peak_ratio`

### Step 2.5：TX truth 发现链
按如下优先级依次查找，取第一个命中的：

| 优先级 | 路径 | 说明 |
|--------|------|------|
| ① | `{stem}_tx_truth.json` | 与采集文件同名的 sidecar（最高优先） |
| ② | `{stem}.truth.json` | sidecar 备选格式 |
| ③ | `{capture_dir}/tx_truth.json` | 目录级 truth 文件 |
| ④ | `{capture_dir}/ber_truth.json` | 目录级 BER truth |
| ⑤ | workspace `tx_truth.json` | 工作空间 fallback |
| ⑥ | `build_fallback_tx_truth()` | 内置默认 8-bit pattern，**仅供链路排障** |

输出 `truth_pattern`，分别注入 open-loop（Step 3-③）和 tracked（Step 4-③）。

---

### Step 3：Open-loop 诊断基线（`recover_nav_bits.m`）

| 子步骤 | 内容 |
|--------|------|
| ① 1ms 复相关 | `compute_ms_correlations`：逐毫秒计算 `corr_ms[k] = Σ{(samples−μ)·PRN·e^{−j2πf_d·t/fs}}`，幅度=相关强度，相位=残余载波 |
| ② 粗频偏估计 | 平方相位法：`Δf_pre = median(Δφ)/(4π×1ms)`，并对 `corr_ms` 做统一频补 |
| ③ 联合枚举搜索 | `joint_search_with_truth`：遍历 `bit_offset∈[0..19ms]` × `pattern_offset∈[0..N-1]` × `polarity∈{+1,−1}`，每候选 20ms 积分，估细频偏，旋转到实轴，BPSK 判决 |
| ④ 多维评分 | `score = 1e6×match_rate + 1e3×projection_margin + 10×bpsk_cluster_strength + 1e-3×mean_bit_energy`；`ambiguity_flag`：top1/top2 score 差 < 2e4 或 match_rate 差 < 1% |
| ⑤ 最优候选输出 | `open_loop_result`：`bit_offset_ms`、`pattern_offset`、`polarity`、`rx_bits`、`ref_bits`、`match_rate`、`ambiguity_flag`、`score_components`、`diagnostics` |

---

### Step 4：Tracked 主链（`track_nav_bits.m`）

| 子步骤 | 内容 |
|--------|------|
| ① DLL 码跟踪 | `track_code_phase_ms`（逐 1ms）：Prompt/Early(+1chip)/Late(−1chip) 三路相关；锁定度 = \|P\|/(\|E\|+\|L\|)；失锁或每 100ms 触发局部重搜 |
| ② FLL-assisted PLL | `track_carrier_from_prompt`：FLL 平滑窗 50ms，PLL 增益 0.08；输出 `prompt_pll`、`fll_freq_hz`、`pll_phase_deg` |
| ③ 初始比特对齐 | `estimate_initial_bit_alignment`：在前 2000ms 训练段上做联合搜索（方式同 open-loop，但基于已跟踪的 prompt） |
| ④ 时序稳定性 | `check_bit_timing_stability`：每 1000ms 检查一次（观测窗 2000ms），边界漂移则重对齐 |
| ⑤ BPSK 判决 | `integrate_bits_from_prompt`：`bit_corr[i]=Σ_{20ms} prompt_pll`；`φ=angle(Σ bit_corr²)/2`（BPSK 翻转无关）；`rx_bits=sign(real(bit_corr·e^{−jφ}))` |
| ⑥ BER 统计 | `ber=mean(rx_bits≠ref_bits)`；滑动 100bit 窗 + `bit_lock_quality` 掩码过滤失锁段 |

---

### Step 5：truth 一致性判决
- `BER_MODE=tracked_truth`（默认）→ `selected = tracked_result`
- `BER_MODE=open_loop_truth` → `selected = open_loop_result`
- 若 `match_rate < 55%`：发出 truth mismatch / bit timing 歧义警告

### Step 6：BER 统计
```matlab
errors    = sum(sign(rx_bits) ~= sign(ref_bits))
ber       = errors / total_bits
```
输出：`errors`、`total_bits`、`ber`

### Step 7：可视化
- 函数：`plot_ber_loopback(analysis_result)`
- 内容：open-loop vs tracked 对比图、锁定质量、局部 window BER

### Step 8：可选保存
- 文件名：`ber_loopback_{timestamp}.mat`
- 保存内容：`truth`、`meta`、`acq_result`、`selected_result`、`stage_timings`

---

## 数据流边（关键连线）

| 边 | 从 | 到 | 携带数据 |
|----|----|----|---------|
| `CAPTURE_PATH` | 入口 | Step 2.5 truth 链 | 文件路径 |
| `samples` | Step 1 | Step 3-①、Step 4-① | IQ 复数序列 |
| `acq_result` | Step 2 | Step 3-①、Step 4-① | Doppler + 码相位 |
| `truth_pattern` | Step 2.5 | Step 3-③、Step 4-③ | 参考比特 pattern |
| `open_loop_result` | Step 3-⑤ | Step 5 | 解调结果 |
| `tracked_result` | Step 4-⑥ | Step 5 | 解调结果 |
| `selected_result` | Step 5 | Step 6 | 选定结果 |

---

## 关键约束与设计决策

1. **捕获段截断**：Acquisition 只取前 100ms，避免处理全长数据的开销。
2. **Open-loop 内存不足可跳过**：用占位结构体代替，不影响 tracked 主链。
3. **Tracked 必须有 truth**：`track_nav_bits` 要求提供 `truth.nav_bits_pattern_pm1`。
4. **Fallback truth 仅排障**：`build_fallback_tx_truth()` 的内置默认 pattern 不适合做严格 BER 结论。
5. **GPU DLL 批处理近似**：批次内用批首 cursor，锁定稳定时近似误差趋近于零。
