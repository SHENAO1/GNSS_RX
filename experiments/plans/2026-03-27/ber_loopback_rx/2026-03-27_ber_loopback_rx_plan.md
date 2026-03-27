# 接收端实验计划：闭环 BER 验证（收端视角）

> 创建时间：2026-03-27
> 对应发射端计划：`/home/shen/projects/gnss_tx/experiments/plans/2026-03-27/ber_loopback_tx/2026-03-27_ber_loopback_tx_plan.md`
> 状态：`[ ]` 待执行
> 里程碑目标：Milestone 1 — 射频线直连闭环 BER 验证

---

## 一、当前收端代码状态摘要

| 功能模块 | 状态 | 文件 |
|----------|------|------|
| USRP B210 IQ 采集 | ✅ 已实现 | `scripts/record_rx.py` + `src/gnss_rx/flowgraph.py` |
| SC16 文件写入 + JSON 元数据 | ✅ 已实现 | `src/gnss_rx/writer.py` + `src/gnss_rx/metadata.py` |
| MATLAB 数据加载 | ✅ 已实现 | `matlab/functions/load_gnss_rx_capture.m` |
| MATLAB GPS L1 C/A 捕获 | ✅ 已实现 | `matlab/functions/run_prn_acquisition.m` |
| **MATLAB 开环比特恢复** | ❌ 需新建 | `matlab/functions/recover_nav_bits.m`（今日新建） |
| **MATLAB BER 计算** | ❌ 需新建 | `matlab/scripts/run_ber_loopback.m`（今日新建） |

**结论：采集链路无需修改。今日需新建两个 MATLAB 文件实现比特恢复和 BER 统计。**

---

## 二、硬件功率安全核查（必须最先完成）⚠️

### 2.1 硬件参数汇总（双手册交叉核对）

B210 核心 RFIC 为 **Analog Devices AD9361**（`DataSheet/ad9361.pdf`）：

| 参数 | 数值 | 来源 | 备注 |
|------|------|------|------|
| TX 最大输出功率（800 MHz，芯片级） | **8 dBm** | AD9361 Table 1 | 50 Ω 负载 |
| TX 最大输出功率（B210 整机） | **>10 dBm** | B210 Spec Sheet | 含外部开关网络 |
| TX Carrier Leakage（0 dB 数字衰减） | **−50 dBc** | AD9361 Table 1 | 本振泄露 |
| **RX RF 输入绝对最大额定值（峰值）** | **+2.5 dBm** | AD9361 Table 11 | **超过将永久损坏芯片** |
| RX IIP3（800 MHz，最大增益） | −18 dBm | AD9361 Table 1 | 1 dB 压缩点 ≈ −28 dBm |
| RX 增益范围 | 0 ~ 74.5 dB | AD9361 Table 1 | 步进 1 dB |
| RX 噪声系数（800 MHz，最大增益） | 2 dB | AD9361 Table 1 | — |

### 2.2 操作流程：频谱仪实测 → 按测量值选衰减器 → 接 RX

```
步骤 ①  B210 TX → 同轴线 → 频谱仪
         以目标 tx_gain 运行 TX，记录实测功率 P_meas（dBm）

步骤 ②  按下表选定衰减器规格

步骤 ③  断开频谱仪，改接：B210 TX → [衰减器] → 同轴线 → B210 RX
```

**衰减量决策表**（目标：RX 输入峰值 ≤ 0 dBm；GPS 信号 PAPR ≈ 0~3 dB，需在平均功率上加 3 dB 后计算）

| 频谱仪读数 P_meas | 峰值估算 | 最小衰减 A_min | **推荐衰减器** | 衰减后 RX 输入 |
|-------------------|----------|---------------|----------------|----------------|
| +10 dBm | +13 dBm | 13 dB | **20 dB** | −10 dBm ✅ |
| +8 dBm | +11 dBm | 11 dB | **20 dB** | −12 dBm ✅ |
| +5 dBm | +8 dBm | 8 dB | **20 dB** | −15 dBm ✅ |
| ≤ 0 dBm | ≤ +3 dBm | 3 dB | **10 dB** | ≤ −10 dBm ✅ |
| 未测量 | 未知 | — | **30 dB（兜底）** | 保守安全 ✅ |

### 2.3 接收端 SNR 估算（验证衰减后信号仍足够）

以 TX = +8 dBm、20 dB 衰减器、1 dB 线缆为例：

```
RX 输入：          8 − 20 − 1 = −13 dBm（低于 +2.5 dBm 绝对限值 15.5 dB）
噪声底（4.092 MHz BW，NF = 2 dB）：≈ −106 dBm
宽带 SNR：         −13 − (−106) = +93 dB
GPS C/A 处理增益： +43 dB
捕获后 SNR：       +136 dB  ← BER 理论趋近于 0，完全满足 Milestone 1
```

---

## 三、BER 统计所需采集时长

```
导航速率：         50 bps
目标总比特数：     ≥ 10^4 bit
所需采集时长：     10000 / 50 = 200 秒
建议采集时长：     250 秒（留 25% 余量，约 12500 bit）
```

**nav_pattern 参考序列（发端固定模式）：**
```
0/1 表示：[1, 0, 1, 1, 0, 0, 1, 0]（循环，8 bit 一周期）
+/-1表示：[+1,-1,+1,+1,-1,-1,+1,-1]
```

---

## 四、分步实验计划

### Step 0：安全核查与硬件连接（预计 15 分钟）

**子步骤（严格按顺序）：**

```
① uhd_find_devices                     确认两台 B210 均在线
② TX → 频谱仪                          接频谱仪，启动 TX，记录 P_meas
③ 查 §2.2 决策表，选定衰减器 A（dB）
④ TX → [衰减器 A dB] → 同轴线 → RX   改接线路
```

```bash
uhd_find_devices
# 期望：列出两台 B210 的序列号
```

**完成标志：**
- [ ] 两台 B210 已被系统识别
- [ ] 频谱仪实测 P_meas = ________ dBm（tx_gain = ________ dB）
- [ ] 选定衰减器：________ dB，衰减后 RX 输入估算 = ________ dBm（须 ≤ 0 dBm）
- [ ] 接线：`B210 TX → [衰减器] → 同轴线 → B210 RX` 已确认到位

### Step 1：接收端干运行验证（预计 5 分钟）

```bash
cd /home/shen/projects/GNSS_RX
PYTHONPATH=src python3 scripts/record_rx.py \
    --config configs/rx_prn1_capture.yaml \
    --dry-run
```

**完成标志：** 脚本正常退出，无 ImportError 或硬件错误，打印配置摘要。

### Step 2：协调发端启动 TX（发端操作，见发端计划）

确认发端终端已运行 `run_tx.py --duration 300`，等待约 3 秒让 TX 稳定。

### Step 3：执行 IQ 采集（预计 250 秒 + 操作 2 分钟）

```bash
cd /home/shen/projects/GNSS_RX

# 修改配置中的采集时长（若默认值不足 250 秒）
# 或通过命令行覆盖：
PYTHONPATH=src python3 scripts/record_rx.py \
    --config configs/rx_prn1_capture.yaml \
    --duration 250
```

**完成标志：**
- [ ] `results/captures/` 下生成 `.sc16` + `.json` 文件对
- [ ] `.json` 中 `sample_count` ≈ 250 × 4.092×10^6 ≈ 1.023 × 10^9 个 sample（文件约 2 GB）
- [ ] 采集期间无连续 overrun（O）报警

> **注意**：250 秒采集约需 2 GB 存储空间，请确认磁盘空间充足（`df -h`）。

### Step 4：MATLAB 捕获验证（预计 10 分钟）

```matlab
% 在 MATLAB 中：
cd /home/shen/projects/GNSS_RX
addpath('matlab/functions');

% 加载最新采集数据
[samples, meta] = load_gnss_rx_capture('results/captures/');  % 或指定具体路径

% 执行 PRN1 捕获（使用前 20 ms 数据即可）
result = run_prn_acquisition(samples(1:round(20e-3 * meta.sample_rate)), meta, struct());

% 检查捕获结果
fprintf('捕获成功: %d\n', result.acquired);
fprintf('次峰比: %.2f\n', result.secondary_peak_ratio);
fprintf('最佳 Doppler: %.1f Hz\n', result.best_doppler_hz);
fprintf('最佳码相位: %d samples\n', result.best_code_phase_samples);
```

**完成标志：**
- [ ] `result.acquired == 1`（次峰比 ≥ 2.5）
- [ ] 记录 `best_doppler_hz` 和 `best_code_phase_samples`

若捕获失败，见 §六 风险预案。

### Step 5：开环比特恢复（新建 MATLAB 函数，预计 30 分钟开发 + 5 分钟运行）

**新建文件：** `matlab/functions/recover_nav_bits.m`

该函数基于捕获结果，对完整采集数据进行开环比特恢复，**无需跟踪环路**：

```matlab
function [bits, timestamps_s] = recover_nav_bits(samples, meta, acq_result)
% RECOVER_NAV_BITS  基于捕获结果的开环导航比特恢复
%
% 输入：
%   samples     - 复数 IQ 样本（列向量，complex double）
%   meta        - 采集元数据结构体（含 sample_rate, center_freq 等）
%   acq_result  - run_prn_acquisition 返回的捕获结果结构体
%
% 输出：
%   bits         - 恢复的导航比特序列（列向量，+1/-1 整数）
%   timestamps_s - 每个比特对应的时间戳（秒，从采集开始计）
%
% 算法（开环，无跟踪环路）：
%   1. 由捕获的 Doppler 偏移生成频率补偿复指数
%   2. 由捕获的码相位生成对齐的本地 PRN 序列
%   3. 每 20 ms（1 个导航 bit 周期）进行相关积分
%   4. 积分结果取符号 → 恢复 bit

    fs = meta.sample_rate;                    % 采样率，Hz
    chip_rate = 1.023e6;                      % C/A 码片速率，Hz
    samples_per_chip = fs / chip_rate;        % 每 chip 的采样数
    samples_per_ms = round(fs * 1e-3);        % 每 ms 采样数（1 个 C/A 码周期）
    samples_per_bit = samples_per_ms * 20;    % 每个导航 bit 的采样数（20 ms）
    code_phase = acq_result.best_code_phase_samples;  % 码相位（采样点数）
    doppler_hz = acq_result.best_doppler_hz;

    % 1. 去除 DC 偏置
    samples = samples - mean(samples);

    % 2. 频率补偿（补偿 Doppler 偏移）
    n = (0:length(samples)-1)';
    freq_comp = exp(-1j * 2 * pi * doppler_hz * n / fs);
    samples_comp = samples .* freq_comp;

    % 3. 生成本地 PRN 序列（PRN1，从码相位 0 开始）
    prn_chips = generate_ca_code(1);          % 需要 generate_ca_code 函数
    % 按 samples_per_chip 展开 PRN 为 sample 级
    prn_samples = repelem(prn_chips, round(samples_per_chip));
    prn_one_ms = prn_samples(1:samples_per_ms);  % 1 ms 的本地 PRN

    % 4. 对齐码相位：从 code_phase 位置开始处理
    start_idx = code_phase + 1;  % MATLAB 1-indexed

    % 5. 逐 bit 积分（每 bit = 20 ms = 20 个 C/A 码周期）
    num_bits = floor((length(samples_comp) - start_idx + 1) / samples_per_bit);
    bits = zeros(num_bits, 1);
    timestamps_s = zeros(num_bits, 1);

    for k = 1:num_bits
        bit_start = start_idx + (k-1) * samples_per_bit;
        bit_end   = bit_start + samples_per_bit - 1;
        if bit_end > length(samples_comp)
            break;
        end
        bit_segment = samples_comp(bit_start:bit_end);

        % 对 20 个 C/A 码周期做相关累加
        corr_sum = 0;
        for ms = 1:20
            ms_start = (ms-1) * samples_per_ms + 1;
            ms_end   = ms * samples_per_ms;
            corr_sum = corr_sum + sum(real(bit_segment(ms_start:ms_end)) .* prn_one_ms);
        end

        bits(k) = sign(corr_sum);
        timestamps_s(k) = (bit_start - 1) / fs;
    end

    % 去掉末尾未填充的零
    valid = bits ~= 0;
    bits = bits(valid);
    timestamps_s = timestamps_s(valid);
end
```

**辅助函数（若 MATLAB 工程中无 `generate_ca_code`，需新建）：**

```matlab
% matlab/functions/generate_ca_code.m
function prn = generate_ca_code(prn_id)
% 生成 GPS L1 C/A PRN 码（+/-1，1023 chip）
% 与 gnss_tx/src/gnss_tx/ca/prn_generator.py 逻辑一致
    G2_taps = {
        [2,6],[3,7],[4,8],[5,9],[1,9],[2,10],[1,8],[2,9],[3,10],...
        [2,3],[3,4],[5,6],[6,7],[7,8],[8,9],[9,10],[1,4],[2,5],...
        [3,6],[4,7],[5,8],[6,9],[1,3],[4,6],[5,7],[6,8],[7,9],...
        [8,10],[1,6],[2,7],[3,8],[4,9]
    };
    G1 = ones(1,10); G2 = ones(1,10);
    taps = G2_taps{prn_id};
    prn = zeros(1,1023);
    for i = 1:1023
        g1_out = G1(10);
        g2_out = xor(G2(taps(1)), G2(taps(2)));
        prn(i) = xor(g1_out, g2_out);
        G1 = [xor(G1(3),G1(10)), G1(1:9)];
        G2 = [xor(xor(xor(xor(xor(G2(2),G2(3)),G2(6)),G2(8)),G2(9)),G2(10)), G2(1:9)];
    end
    prn = 1 - 2*prn;  % 0→+1，1→-1（双极性）
end
```

**完成标志：**
- [ ] `recover_nav_bits.m` 文件已创建
- [ ] 函数运行无报错，返回 `bits` 向量
- [ ] `length(bits)` ≥ 10,000（满足 BER 统计要求）

### Step 6：BER 计算与统计（预计 10 分钟）

**新建文件：** `matlab/scripts/run_ber_loopback.m`

```matlab
%% run_ber_loopback.m
% Milestone 1 BER 闭环验证主脚本
% 执行日期：2026-03-27

clear; close all;
addpath('../functions');

%% 参数配置
CAPTURE_PATH = '../results/captures/';  % 修改为实际采集文件路径
PRN_ID = 1;

% TX 端已知导航比特模式（+/-1 表示，与 DEFAULT_NAV_PATTERN 一致）
TX_PATTERN = [+1, -1, +1, +1, -1, -1, +1, -1];   % 对应 "1 0 1 1 0 0 1 0"

%% Step 1：加载采集数据
fprintf('=== Step 1: 加载采集数据 ===\n');
[samples, meta] = load_gnss_rx_capture(CAPTURE_PATH);
fprintf('采集时长：%.1f 秒，样本数：%d\n', length(samples)/meta.sample_rate, length(samples));

%% Step 2：捕获（取前 100 ms 用于捕获，减少计算量）
fprintf('=== Step 2: GPS L1 C/A 捕获 ===\n');
acq_samples = samples(1:round(0.1 * meta.sample_rate));
acq_result = run_prn_acquisition(acq_samples, meta, struct());

if ~acq_result.acquired
    error('捕获失败！次峰比 = %.2f（阈值 2.5）。请检查信号链路或调整增益。', ...
          acq_result.secondary_peak_ratio);
end
fprintf('捕获成功！Doppler = %.1f Hz，码相位 = %d samples，次峰比 = %.2f\n', ...
        acq_result.best_doppler_hz, acq_result.best_code_phase_samples, ...
        acq_result.secondary_peak_ratio);

%% Step 3：开环比特恢复
fprintf('=== Step 3: 开环比特恢复 ===\n');
[rx_bits, bit_times] = recover_nav_bits(samples, meta, acq_result);
fprintf('恢复比特数：%d\n', length(rx_bits));

if length(rx_bits) < 1000
    warning('恢复比特数不足 1000，请检查捕获结果或增大采集时长。');
end

%% Step 4：比特对齐（循环相位搜索）
fprintf('=== Step 4: 比特序列对齐 ===\n');
pattern_len = length(TX_PATTERN);
pattern_cyc = repmat(TX_PATTERN(:), ceil(length(rx_bits)/pattern_len) + 1, 1);

best_offset = 0;
best_match = 0;
for offset = 0:pattern_len-1
    ref = pattern_cyc(offset+1 : offset+length(rx_bits));
    match_rate = mean(sign(rx_bits) == sign(ref));
    if match_rate > best_match
        best_match = match_rate;
        best_offset = offset;
    end
end
fprintf('最佳对齐偏移：%d bit（匹配率 %.1f%%）\n', best_offset, best_match * 100);

if best_match < 0.5
    warning('最高匹配率 %.1f%% < 50%%，序列可能反相，尝试取反...', best_match * 100);
    rx_bits = -rx_bits;
    best_match = 1 - best_match;
    fprintf('取反后匹配率：%.1f%%\n', best_match * 100);
end

%% Step 5：BER 统计
fprintf('=== Step 5: BER 统计 ===\n');
ref_bits = pattern_cyc(best_offset+1 : best_offset+length(rx_bits));
errors = sum(sign(rx_bits) ~= sign(ref_bits));
total_bits = length(rx_bits);
ber = errors / total_bits;

fprintf('\n========================================\n');
fprintf('  BER 统计结果\n');
fprintf('========================================\n');
fprintf('  总发送比特数：%d\n', total_bits);
fprintf('  误码个数：    %d\n', errors);
fprintf('  BER：         %.2e\n', ber);
fprintf('  对齐相位偏移：%d bit\n', best_offset);
fprintf('  捕获 Doppler：%.1f Hz\n', acq_result.best_doppler_hz);
fprintf('  次峰比：      %.2f\n', acq_result.secondary_peak_ratio);
fprintf('========================================\n');

%% Step 6：保存结果
result_path = sprintf('../results/ber_loopback_%s.mat', datestr(now,'yyyymmdd_HHMMSS'));
save(result_path, 'rx_bits', 'ref_bits', 'errors', 'total_bits', 'ber', 'acq_result', 'meta');
fprintf('结果已保存至：%s\n', result_path);
```

**完成标志（Milestone 1 达成标准）：**
- [ ] `total_bits` ≥ 10,000
- [ ] `errors` 有具体数值
- [ ] `ber` 有具体数值（理想情况下 BER < 1e-3，直连高 SNR 下预期 BER ≈ 0）
- [ ] 结果已保存到 `.mat` 文件

---

## 五、今日预期结果

| 指标 | 预期值 | 依据 |
|------|--------|------|
| 捕获次峰比 | ≥ 5（室内直连） | 上次测量 PRN1 次峰比 3.2（天线近场），直连更高 |
| 恢复总比特数 | ≈ 12,000（250 秒） | 50 bps × 250 s |
| BER | ≈ 0（或 < 1e-3） | 12-bit ADC + 室内直连，SNR 极高 |

---

## 六、风险点与预案

| 风险 | 概率 | 预案 |
|------|------|------|
| **RX 硬件过载（未接衰减器）** | 高 | 执行前检查衰减器，先用频谱仪测功率 |
| 捕获失败（次峰比 < 2.5） | 中 | 检查 TX 是否在运行；调整 rx_gain；检查衰减器是否过大（>40 dB） |
| 磁盘空间不足（文件约 2 GB） | 中 | `df -h` 提前检查，必要时清理旧采集文件 |
| overrun（O）导致数据不连续 | 中 | 降低采样率至 2.048 MHz（但需同步调整 TX 端），或优先使用高速 USB 3.0 |
| 比特对齐失败（匹配率 <50%） | 低 | 检查 TX nav_pattern 是否与 BER 参考一致；尝试 invert bits |
| `recover_nav_bits` 码相位漂移 | 低 | 开环恢复对长数据会有码相位漂移，如出现误码集中在后半段，考虑分段捕获 |

---

## 七、文件输出汇总

| 文件 | 路径 | 说明 |
|------|------|------|
| IQ 采集数据 | `results/captures/YYYYMMDD_*.sc16` | 约 2 GB，250 秒 IQ 数据 |
| 采集元数据 | `results/captures/YYYYMMDD_*.json` | 采样率、中心频率等配置 |
| 比特恢复函数 | `matlab/functions/recover_nav_bits.m` | 今日新建 |
| CA 码生成函数 | `matlab/functions/generate_ca_code.m` | 今日新建（若不存在） |
| BER 主脚本 | `matlab/scripts/run_ber_loopback.m` | 今日新建 |
| BER 结果 | `results/ber_loopback_YYYYMMDD_HHMMSS.mat` | 实验结果归档 |

---

## 八、实验记录模板

执行完毕后，在 `experiments/` 下新建实验记录：

```
experiments/2026-03-27_ber_loopback_results.md
```

至少记录：
- 硬件配置（衰减器规格、tx_gain、rx_gain）
- 采集文件路径
- 捕获结果（Doppler、码相位、次峰比）
- **BER 统计三元组：总 bit 数 / 误码数 / BER 数值**
- 是否达成 Milestone 1 标准
