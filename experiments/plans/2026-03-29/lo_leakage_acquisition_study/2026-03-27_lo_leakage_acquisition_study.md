# 实验方案：本振泄露对单星 GPS L1 C/A 捕获的影响

> 创建时间：2026-03-26
> 状态：`[ ]` 待执行
> 前置条件：单星 PRN1 基线捕获已验证（次峰比 3.2，见 `../../../records/2026-03-26/prn_subset_snr_debug/2026-03-26_prn_subset_snr_debug.md`）

---

## 一、背景与研究动机

### 1.1 USRP B210 的本振泄露机制

B210 采用**直接变频（Zero-IF）架构**，本振（LO）与射频混频器共用同一 PLL 时钟。在这种结构中，存在两条独立的 LO 泄露路径：

```
                   ┌──────────────────────┐
                   │      TX 链路         │
  基带 IQ  ──►  混频器 ──►  PA ──►  TX 天线
                   ▲              │
                   │ LO 信号       │ 泄露功率（经空间或直接耦合到 RX）
                   │              ▼
  RX 天线  ──►  LNA ──►  混频器 ──►  ADC ──►  基带 IQ
                   ▲
                   │ RX 自身 LO（→ DC 直流偏置）
```

**路径 1 — TX 端 LO 泄露（对空辐射）**：
TX 混频器的隔离度有限（典型 −20 ~ −30 dBc），LO 信号以连续波（CW）形式从 TX 天线辐射出去。在我们的环回实验（TX/RX 天线近距离摆放）中，这个 CW 泄露信号会被 RX 天线收到，叠加在目标 GPS 扩频信号上。

**路径 2 — RX 端 LO 自漏（直流偏置）**：
RX 混频器的 LO 信号向 ADC 方向漏出，在基带产生固定直流偏置（DC offset）。这部分已被捕获脚本中的 `samples - mean(samples)` 一阶去除，但残差仍然存在。

### 1.2 LO 泄露在捕获中的表现

GPS L1 C/A 捕获是一个 **Doppler × 码相位** 二维搜索，每个格元累加 1 ms 的循环相关能量。LO 泄露（本质上是中心频率处的连续波）对这个搜索图的影响与 PRN 扩频信号截然不同：

| 成分 | 经 PRN 相关后的行为 | 对搜索图的影响 |
|------|---------------------|----------------|
| GPS PRN 扩频信号 | 解扩后能量集中在真实码相位处（处理增益 ≈ 43 dB） | 一个尖锐主峰 |
| LO 泄露 CW（Doppler=0） | 无解扩增益，能量均匀铺散到所有码相位格元 | 抬高噪声基底（等效于色噪声） |
| LO 泄露 CW（Doppler≠0） | 同上，只在对应 Doppler 行有能量 | 该 Doppler 行整体抬高 |
| ADC 直流偏置残差 | 仅在 Doppler=0 行，从 mean 中减去后残差分布在码相位 0 附近 | Doppler=0 行可能出现虚假峰 |

**关键推论**：

1. **次峰比退化**：LO 泄露抬高搜索图底噪，使次峰比（峰值 / 次峰值）减小，即便主峰绝对功率不变。
2. **虚假峰风险**：若去 DC 不彻底，残余直流集中在码相位 0 附近，形成伪峰，尤其在低 SNR 时可能超越真实峰。
3. **ADC 动态范围压缩**：极近距离环回时，LO 泄露功率可能接近甚至超过 GPS 信号，迫使 ADC 动态范围分配给干扰，有效减少 GPS 信号的量化精度。
4. **RX 增益敏感性**：增大 `rx_gain_db` 在放大 GPS 信号的同时也等比例放大 LO 泄露，净 SNR 增益有限。

---

## 二、实验目标

1. **量化** LO 泄露在不同 TX-RX 隔离度下对捕获搜索图的影响（次峰比、噪声基底）。
2. **验证**一阶去 DC（`samples - mean`）对 LO 泄露的抑制效果及其残差大小。
3. **确定**安全操作区间：在当前实验室环境（近距离环回）下，LO 泄露对捕获结论（成功/失败）是否有显著影响，还是可以被忽略。
4. **为后续多星实验提供依据**：多星叠加时每颗星 SNR 已下降 `10·log₁₀(N)` dB，LO 泄露是否会进一步压缩余量？

---

## 三、实验设计

### 3.1 变量定义

| 变量 | 取值 | 说明 |
|------|------|------|
| **TX-RX 物理隔离度** | 0（直连电缆）/ ~30 cm（近场）/ ~1 m（中场）/ TX 关闭 | 通过天线间距或 RF 衰减器调整 |
| **RX 增益 `rx_gain_db`** | 10 / 20 / 30 / 40 dB | 与现有基线配置对齐 |
| **TX 增益 `tx_gain`** | 10 / 20 dB（固定单星 PRN1） | 与 `tx_b210_visible_spectrum.yaml` 基线一致 |
| **是否去 DC** | 开（当前默认）/ 关（注释掉 `mean`）| MATLAB 分析中切换 |

**固定参数**（全程不变）：

- 中心频率：100 MHz
- 采样率：4.092 MHz
- PRN：1
- 非相干积分：20 ms
- Doppler 搜索：−5000 Hz ~ +5000 Hz，步长 250 Hz

### 3.2 实验条件（五组）

#### 条件 C0（基准 — TX 关闭）

**目的**：仅测量 RX 端 LO 自漏（直流偏置）基线，无任何有用信号。

```bash
# TX 端不启动
# RX 端采集
PYTHONPATH=src python3 scripts/record_rx.py \
    --config configs/rx_prn1_capture.yaml
# 期望：捕获失败，次峰比 ≈ 1.0；频谱只有 LO 尖峰和热噪声
```

**分析要点**：
- 查看原始 IQ 谱：直流分量幅度（LO 自漏功率估计）
- 去 DC 前后的谱对比
- 搜索图的底噪基线分布

#### 条件 C1（近场环回 — 当前实验室配置）

**目的**：与现有基线一致，测量 TX LO 泄露 + RX LO 自漏叠加效果。

```bash
# TX 端（PRN1，基线配置）
cd /home/shen/projects/gnss_tx
PYTHONPATH=src python3 scripts/run_tx.py \
    --config configs/tx_b210_visible_spectrum.yaml \
    --duration 30

# RX 端（各 rx_gain 值分别采集）
PYTHONPATH=src python3 scripts/record_rx.py \
    --config configs/rx_prn1_capture.yaml  # rx_gain_db: 20
```

需要为不同 RX 增益值创建配置变体（见 §3.4）。

#### 条件 C2（中场，~1 m 隔离）

**目的**：拉开 TX-RX 天线距离，测量 LO 泄露功率随距离下降对捕获的影响。

操作：将 TX USRP 和 RX USRP 天线分置于实验台两端（约 1 m），保持其余参数与 C1 相同。

#### 条件 C3（RF 衰减器，人工增加隔离）

**目的**：在固定物理距离下，用 RF 同轴衰减器（如 20 dB、30 dB 固定衰减器）串入 TX 天线侧，等效模拟更大空间隔离，精确控制 TX 泄露功率。

```
B210 TX 端口 → [20 dB 衰减器] → 天线（对空辐射）
```

此条件与 C1 对比，可以将 LO 泄露功率（随 GPS 信号同比衰减）和空间路径损耗效应分开讨论。

#### 条件 C4（禁用去 DC）

**目的**：量化一阶去 DC 处理对 LO 自漏的实际抑制量，以及禁用后对次峰比的具体影响。

操作：在 MATLAB 中注释掉 `run_prn_acquisition.m` 第 42 行的去 DC 操作，重新分析 C0 和 C1 的已保存数据（无需重新采集）：

```matlab
% 临时注释去 DC（仅用于本实验）
% samples = samples - mean(samples);   % <-- 注释此行
```

### 3.3 测量指标

每个条件、每个 RX 增益值，记录以下指标：

| 指标 | 计算方式 | 记录位置 |
|------|----------|----------|
| **次峰比** | 主峰功率 / 次峰功率 | 捕获结果 `result.secondary_peak_ratio` |
| **捕获决策** | 次峰比 ≥ 2.5 → 成功 | `result.acquired` |
| **最佳 Doppler 估计** | `result.best_doppler_hz` | 验证是否偏向 LO 泄露对应频率 |
| **最佳码相位** | `result.best_code_phase_samples` | 检查是否在 0 附近（DC 残差特征） |
| **搜索图底噪均值** | `mean(search_map(:))` | MATLAB 额外计算 |
| **搜索图底噪标准差** | `std(search_map(:))` | 评估干扰均匀性 |
| **峰值信噪比（dB）** | `10·log₁₀(peak_power / noise_floor)` | 类 CN0 指标 |
| **直流分量功率** | `abs(mean(samples))^2`（去 DC 前） | 量化 LO 自漏幅度 |

### 3.4 配置文件变体

在 `configs/` 目录下为本实验创建以下配置文件变体（仅改变 `rx_gain_db`，其余字段继承 `rx_prn1_capture.yaml`）：

```yaml
# configs/rx_prn1_lo_study_g10.yaml
rx_gain_db: 10.0
# （其余字段与 rx_prn1_capture.yaml 相同）

# configs/rx_prn1_lo_study_g30.yaml
rx_gain_db: 30.0

# configs/rx_prn1_lo_study_g40.yaml
rx_gain_db: 40.0
```

---

## 四、数据采集步骤

### 4.1 采集流程（针对 C0/C1/C2/C3）

每个条件按以下顺序执行（约 5 分钟 / 条件）：

1. 布置物理环境（天线间距 / 衰减器）。
2. 启动 TX（或确认 TX 关闭，用于 C0）。
3. 等待 TX 冷启动稳定（约 5 秒）。
4. 对每个 `rx_gain_db`（10/20/30/40 dB）分别采集一次，每次 2 秒，共 4 次采集。
5. 记录每次采集的文件路径和配置。

### 4.2 采集命令模板

```bash
cd /home/shen/projects/GNSS_RX

# C0：TX 关闭，RX gain=20 dB
PYTHONPATH=src python3 scripts/record_rx.py \
    --config configs/rx_prn1_capture.yaml

# C1：TX 开启（PRN1，tx_gain=20dB），RX gain 变体
PYTHONPATH=src python3 scripts/record_rx.py \
    --config configs/rx_prn1_lo_study_g10.yaml

PYTHONPATH=src python3 scripts/record_rx.py \
    --config configs/rx_prn1_capture.yaml        # gain=20（已有基线）

PYTHONPATH=src python3 scripts/record_rx.py \
    --config configs/rx_prn1_lo_study_g30.yaml

PYTHONPATH=src python3 scripts/record_rx.py \
    --config configs/rx_prn1_lo_study_g40.yaml
```

---

## 五、MATLAB 分析方案

### 5.1 分析框架

在现有 `run_capture_analysis.m` 基础上，新增以下分析步骤（建议单独创建 `run_lo_leakage_study.m`）：

```matlab
%% run_lo_leakage_study.m
% 本振泄露影响研究主分析脚本

conditions = {'C0_tx_off', 'C1_near_g10', 'C1_near_g20', 'C1_near_g30', 'C1_near_g40', ...
              'C2_1m_g20', 'C3_att20dB_g20'};

results = struct();

for i = 1:numel(conditions)
    % 1. 加载对应条件的采集数据
    [samples, meta] = load_capture(data_paths{i});

    % 2. 去 DC 前的直流功率估计
    dc_power_before = abs(mean(samples))^2;

    % 3. 标准捕获（去 DC）
    cfg = struct();
    cfg.noncoherent_ms = 20;
    cfg.doppler_min_hz = -5000;
    cfg.doppler_max_hz =  5000;
    cfg.doppler_step_hz = 250;
    result_dc_on = run_prn_acquisition(samples, meta, cfg);

    % 4. 禁用去 DC 捕获（对比用）
    samples_no_dc_rm = samples;  % 不调用 mean() 减法
    result_dc_off = run_prn_acquisition_no_dc(samples_no_dc_rm, meta, cfg);
    %   （需创建 run_prn_acquisition_no_dc.m，仅注释掉去 DC 行）

    % 5. 记录指标
    results(i).condition        = conditions{i};
    results(i).dc_power_before  = dc_power_before;
    results(i).spr_dc_on        = result_dc_on.secondary_peak_ratio;
    results(i).acquired_dc_on   = result_dc_on.acquired;
    results(i).spr_dc_off       = result_dc_off.secondary_peak_ratio;
    results(i).best_doppler     = result_dc_on.best_doppler_hz;
    results(i).noise_floor_mean = mean(result_dc_on.search_map(:));
    results(i).noise_floor_std  = std(result_dc_on.search_map(:));
    results(i).peak_snr_db      = 10*log10(result_dc_on.peak_power / results(i).noise_floor_mean);

    % 6. 绘图：搜索图热图（每个条件单独一张）
    figure('Name', conditions{i});
    plot_acquisition_heatmap(result_dc_on, meta, conditions{i});
end

% 7. 汇总对比图：次峰比 vs RX 增益（各条件叠加）
plot_spr_vs_rxgain(results);

% 8. 汇总对比图：去 DC 前后次峰比变化
plot_dc_removal_effect(results);
```

### 5.2 关键可视化

**图 1 — 各条件捕获搜索图热图（2D 伪彩图）**
横轴：码相位（chip），纵轴：Doppler（Hz），颜色：相关能量（dB）
→ 直观对比 LO 泄露在不同条件下对搜索图底噪和峰形的影响

**图 2 — 次峰比 vs RX 增益（折线图）**
X 轴：`rx_gain_db`（10/20/30/40 dB），Y 轴：次峰比
多条折线：C0/C1/C2/C3 各条件
参考线：次峰比阈值 2.5（捕获判决门限）
→ 显示在何种增益下 LO 泄露开始导致捕获失败

**图 3 — 去 DC 效果对比（配对柱状图）**
每个条件两根柱：去 DC 开 vs 关，Y 轴：次峰比
→ 量化一阶去 DC 的实际效果

**图 4 — 频谱对比（归一化 PSD）**
各条件的原始 IQ 频谱，标注 LO 泄露尖峰位置和功率
→ 与搜索图底噪结果对应，建立泄露功率与捕获退化的直接关联

### 5.3 预期的 LO 泄露分布特征

在搜索图中，若存在 LO 泄露 CW（频率偏移 Δf 相对中心频率接近 0）：
- 在 Doppler = 0 Hz 行，所有码相位格元能量均匀抬高（CW 与 PRN 码无相关性，能量扩散）
- 若 LO 泄露有非零 Doppler（TX/RX LO 之间存在微小频差），抬高出现在对应的 Doppler 行
- 直流残差（mean 减法后的余量）集中在码相位 ≈ 0 的狭窄区域，在 Doppler=0 行形成一个宽约 1~2 chip 的伪峰

---

## 六、预期结论与判断标准

| 场景 | 预期次峰比 | 解读 |
|------|------------|------|
| C0（TX 关闭） | ≈ 1.0，捕获失败 | 无信号基线，LO 自漏不足以产生虚假主峰 |
| C1 近场，gain=20（基线） | ~3.2（已验证） | 当前实验室配置，LO 泄露存在但不影响决策 |
| C1 近场，gain=40 dB | 可能 < 2.5，捕获失败风险 | 高增益时 LO 泄露被放大，底噪压缩次峰比 |
| C2 远场，1 m | ≥ 3.2（优于 C1） | 物理隔离有效减少 TX LO 泄露 |
| C3 衰减器 20 dB | 可能 ≥ 5.0 | 信号和泄露同比衰减，但 LO 泄露衰减更多（非等比） |
| 禁用去 DC | 次峰比下降，可能 < 2.5 | 验证一阶去 DC 对于低隔离度场景的必要性 |

---

## 七、可能的扩展实验（本方案外）

以下扩展实验暂不执行，记录供后续参考：

- **IQ 失衡校正**：B210 存在 IQ 幅度/相位不平衡，与 LO 泄露叠加后产生镜频干扰，影响 Doppler 搜索的对称性。可通过发射已知纯音信号（`signal_mode: "tone"`）估计 IQ 失衡参数并补偿。
- **非相干积分时间扫描**：在固定 LO 泄露条件下，扫描 `noncoherent_ms`（1/5/10/20 ms），测试积分时间对抑制 LO 泄露（相对于 GPS 信号的相关增益差异）的效果。
- **多星环境下 LO 泄露**：在 4 星叠加（已验证次峰比 5.1~8.9）的基础上，引入 LO 泄露干扰，测试最弱 PRN 的次峰比退化量。

---

## 八、实验记录模板

执行完毕后，在 `experiments/` 目录新建实验记录，命名为：

```
YYYY-MM-DD_lo_leakage_acquisition_results.md
```

至少包含以下内容：

- 实验日期和硬件配置（天线摆放、衰减器型号）
- 各条件的采集文件路径（`.sc16` + `.json`）
- 汇总表格（次峰比、捕获决策、底噪）
- 关键图的截图路径
- 结论：LO 泄露在当前实验室环境下的量化影响
- 对后续多星实验的建议（捕获阈值是否需要调整）
