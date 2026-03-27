# BER 闭环验证：三阶段实施方案

> 创建时间：2026-03-27
> 对应主计划：[2026-03-27_ber_loopback_rx_plan.md](2026-03-27_ber_loopback_rx_plan.md)
> 状态：`[ ]` 阶段 0 待执行

---

## 背景与动机

原收端计划（`2026-03-27_ber_loopback_rx_plan.md`）已给出完整的离线处理流程（录 IQ → MATLAB 处理），但直接上两台硬件同步跑 250 秒存在以下风险：

- MATLAB BER 代码（`recover_nav_bits.m`、`run_ber_loopback.m`）尚未验证，有可能在真实硬件采集后才发现算法 bug
- 250 秒采集文件约 2 GB，磁盘与调试成本较高
- 两台设备同步协调增加操作复杂度

**解决思路**：先用合成数据（无硬件）打通 MATLAB 管线，确认代码正确后再逐步升级到真实硬件，最终完成 Milestone 1 指标。

---

## 已实现的 MATLAB 文件（2026-03-27）

| 文件 | 描述 |
|------|------|
| `matlab/functions/generate_ca_code.m` | GPS L1 C/A PRN 码生成（双 LFSR，+/-1，1023 chip，PRN 1~32） |
| `matlab/functions/recover_nav_bits.m` | 开环导航比特恢复（无跟踪环路，每 20 ms 积分取符号） |
| `matlab/scripts/run_ber_loopback.m` | BER 主脚本（文件选择 → 捕获 → 比特恢复 → BER 统计 → 保存 .mat） |

TX 端 nav_pattern 参考：`[+1, -1, +1, +1, -1, -1, +1, -1]`（对应 `"1 0 1 1 0 0 1 0"`）

---

## 三阶段执行方案

### 阶段 0 — 合成数据验证（无硬件）

**目的**：验证 MATLAB 代码逻辑正确，无需任何硬件。

**步骤：**

```bash
cd /home/shen/projects/GNSS_RX

# 生成 30 秒合成 IQ 文件（约 240 MB）
PYTHONPATH=/home/shen/projects/gnss_tx/src:src \
    python3 scripts/gen_synthetic_capture.py \
    --config configs/rx_cable_loopback.yaml \
    --prn-id 1 --snr-db 30 --duration 30
```

输出文件位于 `results/captures/`，文件名含 `_synthetic` 后缀。

在 MATLAB 中运行：

```matlab
cd /home/shen/projects/GNSS_RX
CAPTURE_PATH = 'results/captures/<stem>';   % 替换为实际 stem
run matlab/scripts/run_ber_loopback.m
```

**验收标准：**

| 检查项 | 预期值 |
|--------|--------|
| 捕获次峰比 | ≥ 2.5 |
| 恢复总比特数 | ≈ 1500（30 s × 50 bps） |
| BER（SNR = 30 dB） | ≈ 0 |
| BER（`--snr-db 3`，降低 SNR） | 明显升高（验证 BER 随 SNR 变化的响应） |

**状态：** `[ ]` 待执行

---

### 阶段 1 — 短时真实硬件验证（30 秒，~1500 bit）

**目的**：用真实硬件走通完整链路，时间短、文件小、快速发现硬件问题。

**前提**：阶段 0 通过，MATLAB 管线已验证正确。

**步骤：**

```bash
# 终端 1（TX，B210 #1）
cd /home/shen/projects/gnss_tx
PYTHONPATH=src python3 scripts/run_tx.py \
    --config configs/tx_b210_cable_loopback.yaml \
    --duration 60

# 终端 2（RX，B210 #2，TX 启动约 3 秒后运行）
cd /home/shen/projects/GNSS_RX
PYTHONPATH=src python3 scripts/record_rx.py \
    --config configs/rx_cable_loopback.yaml \
    --duration 30
```

硬件连接：`B210 TX → [衰减器] → 同轴线 → B210 RX`
（衰减器选择见主计划 §2.2，或先用频谱仪实测再定）

在 MATLAB 中运行 `run_ber_loopback.m`，指向刚录制的文件。

**验收标准：**

| 检查项 | 预期值 |
|--------|--------|
| 捕获次峰比 | ≥ 2.5 |
| 恢复总比特数 | ≈ 1500 |
| BER | < 0.01（直连高 SNR，非统计精度要求） |

**状态：** `[ ]` 待执行

---

### 阶段 2 — 完整 BER 测量（250 秒，≥12500 bit）

**目的**：满足 Milestone 1 的 ≥10^4 bit 统计要求，达成正式验收。

**前提**：阶段 1 通过，硬件链路已确认正常。

执行方式与主计划 §Step 3~6 完全一致（采集 250 秒，约 2 GB），不再赘述。

**验收标准（Milestone 1 达成标准）：**

| 检查项 | 预期值 |
|--------|--------|
| 恢复总比特数 | ≥ 10,000 |
| BER | ≈ 0（或 < 1e-3） |
| 结果文件 | `results/ber_loopback_YYYYMMDD_HHMMSS.mat` 已保存 |

**状态：** `[ ]` 待执行

---

## 误码率计算原理详解

本节从信号模型出发，逐步推导整个 BER 分析管线的数学原理，对应 `recover_nav_bits.m` 和 `run_ber_loopback.m` 的每一步实现。

---

### 1. 信号模型

TX 端生成的基带信号为 GPS L1 C/A BPSK 扩频信号：

```
s(n) = A · d[k] · c[m]
```

其中：
- `A`：信号幅度
- `d[k] ∈ {+1, -1}`：导航比特，每 20 ms 切换一次（50 bps），是我们要恢复的目标
- `c[m] ∈ {+1, -1}`：C/A 伪随机码（PRN），以 1.023 MHz 速率重复，每 1 ms 一个周期（1023 chip）
- `n`：样本时间索引，采样率 4.092 MHz（每个 chip 对应 4 个样本）

**关键关系**：每个导航比特包含 `20 个 C/A 码周期`。整个信号是 `d[k]` 先调制到 `c[m]` 上再发出——接收端必须先"解扩"（去掉 C/A 码）才能看到 `d[k]`。

经过信道（线缆直连）后，RX 收到的信号还叠加了两个效应：
- **Doppler 频偏** `fd`：TX/RX 两台 B210 本振存在微小频率偏差（即便静止），导致信号产生一个固定的频率旋转
- **加性白噪声** `w(n)`

因此接收到的复基带样本为：

```
r(n) = A · d[k] · c[m] · exp(j·2π·fd·n/fs) + w(n)
```

后续所有处理的目标，就是从 `r(n)` 中把 `d[k]` 的符号（+1 或 -1）估计出来。

---

### 2. 第一步：去除 DC 偏置

```matlab
samples = samples - mean(samples);
```

B210 的 AD9361 RFIC 在零中频（Zero-IF）架构下，本振泄露会在基带产生一个直流分量（DC offset）。这个 DC 偏置与 PRN 码做相关时不会被消除（因为 C/A 码均值并不严格为零），会在积分结果中引入一个常数偏差，影响 bit 判决。直接减去均值可以简单有效地去除。

---

### 3. 第二步：频率补偿（去 Doppler）

```matlab
freq_comp    = exp(-1j * 2*pi * doppler_hz * n / fs);
samples_comp = samples .* freq_comp;
```

接收信号中的 Doppler 频偏 `fd` 来自捕获阶段（`run_prn_acquisition.m` 搜索出的 `best_doppler_hz`）。

将接收信号乘以共轭旋转因子 `exp(-j·2π·fd·n/fs)`，相当于把频谱搬移回零频：

```
r(n) · exp(-j·2π·fd·n/fs)
  = A · d[k] · c[m] · exp(j·2π·fd·n/fs) · exp(-j·2π·fd·n/fs) + w'(n)
  = A · d[k] · c[m] + w'(n)
```

补偿后信号中不再有频率旋转，后续的相关积分才能正确累加（否则积分区间内信号相位在旋转，正负抵消导致积分结果趋近于零）。

> **注意**：这是开环补偿——用捕获时估计的 `fd` 在整段数据上做静态旋转。若采集过程中频率有缓慢漂移，长时间后补偿残差会积累，这是开环方案的局限性。

---

### 4. 第三步：码对齐与相关解扩（1 ms 单周期相关）

捕获结果的 `best_code_phase_samples` 告诉我们：本地 PRN 序列与接收信号的 C/A 码之间相差多少个样本。从这个偏移处开始，本地 PRN 和接收信号的码片就是对齐的。

对每个 1 ms 窗口（= `samples_per_ms = 4092` 个样本）做相关：

```matlab
corr_1ms = sum(real(segment_1ms) .* prn_one_ms)
```

数学上，这是接收信号与本地 PRN 的内积。当两者完全对齐时：

```
Σ [A · d[k] · c[m] + noise] · c_local[m]
  = A · d[k] · Σ c[m]·c_local[m]  +  Σ noise · c_local[m]
  = A · d[k] · 1023               +  noise_ms
```

因为 `c[m] · c_local[m] = (+1)·(+1) 或 (-1)·(-1) = +1`（完全对齐时），所以 `Σ c[m]·c_local[m] = 1023`。

当对齐偏差 ≥ 1 chip 时，C/A 码的自相关函数趋近于零（这是伪随机码的核心特性），因此对其他 PRN 或错位码的相关输出几乎为零——这就是**扩频解扩**的工作原理。

> 这一步相当于把 1023 chip 的"扩频增益"释放出来：噪声被 PRN 长度 1023 分摊（积分增益 ≈ +30 dB），而信号 `d[k]` 的幅度被放大了 1023 倍。

---

### 5. 第四步：20 ms 相干积分（比特积分）

```matlab
corr_sum = 0;
for ms = 1:20
    corr_sum = corr_sum + sum(real(bit_segment_ms) .* prn_one_ms);
end
```

在 20 ms 的一个导航比特周期内，同一个 `d[k]` 值调制在 **20 个连续的 C/A 码周期**上。对这 20 个 1 ms 相关结果做累加：

```
I_bit = Σ(ms=1~20) corr_1ms
      = A · d[k] · 1023 · 20  +  Σ(ms=1~20) noise_ms
      = A · d[k] · 20460      +  noise_20ms
```

噪声项中 20 个独立噪声样本的累加，标准差只增长 `√20` 倍，而信号幅度增长了 `20` 倍。信噪比相比单个 1 ms 相关提升 `20 / √20 = √20 ≈ +13 dB`。

**总处理增益** = 解扩增益（1023）× 比特积分增益（20）= 20460 倍幅度，约 +43 dB 功率增益。

---

### 6. 第五步：符号判决（恢复比特）

```matlab
bits(k) = sign(corr_sum);
```

对积分结果取符号：

```
d_hat[k] = sign(I_bit) =
    +1  若 I_bit > 0  （判决为 d[k] = +1）
    -1  若 I_bit < 0  （判决为 d[k] = -1）
```

这是最大似然 BPSK 判决。在高 SNR 下（直连线缆场景），噪声项远小于信号项，`I_bit` 的符号与 `d[k]` 几乎总是一致。

---

### 7. 第六步：相位对齐（解决起始偏移未知问题）

TX 端循环发送 8 bit 模式 `[+1,-1,+1,+1,-1,-1,+1,-1]`，但 RX 采集的起始时刻不一定恰好落在模式的第 0 bit 处。因此恢复出的比特流 `rx_bits` 可能从模式的任意位置开始。

解决方法：遍历 8 种可能的对齐偏移（0 ~ 7），对每种偏移生成对应的参考序列，计算匹配率，取最高的那个：

```
match_rate(offset) = mean(sign(rx_bits) == sign(ref_pattern_shifted_by_offset))
```

```
best_offset = argmax_{offset ∈ 0..7} match_rate(offset)
```

直连高 SNR 场景下，正确偏移的匹配率应接近 100%，错误偏移约为 50%（随机猜对的概率）。

**极性反转处理**：BPSK 存在 180° 相位模糊（即收到的 `d_hat` 与发送的 `d` 整体反号）。若所有偏移下匹配率均 < 50%，说明整体反相，将 `rx_bits` 取反后匹配率会变成 > 50%。代码中已内置此逻辑。

---

### 8. 第七步：BER 计算

经过对齐后，将接收比特与参考序列逐位比较：

```
errors     = Σ 1(sign(rx_bits[i]) ≠ sign(ref_bits[i]))
total_bits = length(rx_bits)
BER        = errors / total_bits
```

**为什么需要 ≥ 10^4 bit？**

BER 是概率估计量，其统计误差约为：

```
σ_BER ≈ sqrt(BER · (1 - BER) / N)
```

在直连场景下理论 BER ≈ 0，若观测到 0 个误码而 N = 10^4，则 BER 上界（95% 置信）约为 `3 / 10^4 = 3×10⁻⁴`。这是 Milestone 1 能声称"BER ≈ 0"的最低统计可信度要求。

---

### 完整数据流总结

```
IQ 样本 r(n)
    │
    ▼ 去 DC
    │
    ▼ × exp(-j·2π·fd·n/fs)     ← 使用捕获到的 Doppler fd
    │
    ▼ 对齐码相位（从 best_code_phase_samples 开始）
    │
    ▼ 逐比特循环（每 20 ms）：
    │   20 次 × [1 ms 窗口 × PRN 相关] → corr_sum
    │   bit_hat = sign(corr_sum)
    │
    ▼ rx_bits[]（+1/-1 序列）
    │
    ▼ 遍历 8 个偏移，找最大匹配率 best_offset
    │
    ▼ 逐位比对 rx_bits vs ref_pattern[best_offset:]
    │
    ▼ BER = errors / total_bits
```

---

## 风险与应对

| 风险 | 阶段 | 应对 |
|------|------|------|
| 合成数据捕获失败（次峰比 < 2.5） | 0 | 检查 `gen_synthetic_capture.py` 是否成功写入文件；确认 `meta.prn_id = 1` |
| `recover_nav_bits` 码相位漂移（误码集中在后半段） | 1/2 | 开环方案对长数据有累积漂移风险；如有此现象，考虑分段捕获 |
| BER 极性反转（匹配率 < 50%） | 0/1/2 | `run_ber_loopback.m` 已内置自动取反逻辑 |
| 硬件过载（忘接衰减器） | 1/2 | 严格执行主计划 §Step 0，先接频谱仪实测功率 |
