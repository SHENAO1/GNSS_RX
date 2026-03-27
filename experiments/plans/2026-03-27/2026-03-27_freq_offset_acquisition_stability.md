# 实验方案：人为频偏对 GPS L1 C/A 捕获稳定性的影响

> 创建时间：2026-03-27
> 状态：`[ ]` 待执行
> 前置条件：
> - 单星 PRN1 基线捕获已验证（次峰比 3.2，积分 20 ms）
> - MATLAB 路径可移植性已完成（`GNSS_RX_DATA_DIR` 环境变量）
> - 合成数据生成工具 `gen_synthetic_capture.py` 可用（无硬件即可执行本实验）

---

## 一、背景：真实 GPS 接收机的频偏来源与量级估算

### 1.1 频偏的两大来源

真实 GPS 接收机面对的频偏由两部分叠加：

#### 来源 A — 卫星 Doppler 频移

GPS 卫星轨道高度约 20,200 km，轨道速度约 3.87 km/s。接收机观测到的径向分量最大约 800 m/s（低仰角、卫星过顶瞬间），对应 L1 载波 Doppler：

```
f_doppler = f_L1 × v_radial / c
           = 1575.42 MHz × 800 m/s / (3×10⁸ m/s)
           ≈ ±4200 Hz（单向最大值）
```

#### 来源 B — 接收机本振误差（时钟频偏）

商用 TCXO（温度补偿晶体振荡器）在常温下典型精度 ±2 ppm，在极端温度下可达 ±5 ppm。折算到 GPS L1：

```
f_clock_error = f_L1 × ppm × 10⁻⁶
              = 1575.42 MHz × 2×10⁻⁶ ≈ ±3150 Hz （±2 ppm，常温）
              = 1575.42 MHz × 5×10⁻⁶ ≈ ±7877 Hz （±5 ppm，极端）
```

#### 合计：捕获阶段的总频率不确定度

| 来源 | 量级（L1，1575.42 MHz） |
|------|------------------------|
| Doppler（最大） | ±4200 Hz |
| TCXO 误差（常温，±2 ppm） | ±3150 Hz |
| TCXO 误差（极端，±5 ppm） | ±7877 Hz |
| **最坏合计** | **≈ ±12 kHz** |

> **结论：** 这也是为什么工业标准的 GPS 捕获引擎将 Doppler 搜索范围设计为 **±10~15 kHz**，步长设计为 **500 Hz 以内**（对应 1 ms 相干积分的 sinc 主瓣半宽约 1 kHz）。

### 1.2 折算到本实验平台（100 MHz 中心频率，USRP B210）

本实验不涉及真实卫星（近距离 RF 环回），Doppler = 0。但为测试捕获算法鲁棒性，我们**人为在接收端注入频偏**，模拟以下两种场景：

| 模拟场景 | 等效频偏（100 MHz 基础） | 等效对应 L1 真实量级 |
|----------|------------------------|----------------------|
| B210 时钟误差（±2 ppm） | ±200 Hz | 参考量级 |
| 实验室最坏时钟漂移 | ±500 Hz | — |
| 真实 GPS Doppler（等比缩放） | ±4200 × (100/1575) ≈ ±267 Hz | ±4200 Hz @ L1 |
| 真实 GPS 总不确定度（等比缩放） | ±762 Hz | ±12 kHz @ L1 |
| 超出搜索范围（压力测试） | ±5000 ~ ±15000 Hz | 远超正常范围 |

> **实验的主要频偏测试点：** 覆盖 ±0 Hz 至 ±15000 Hz，步长从细（100 Hz）到粗（5000 Hz），完整映射次峰比随频偏变化的曲线。

### 1.3 Doppler 搜索分格损失（bin straddle loss）

当真实频偏恰好落在两个 Doppler 搜索格元的中间时，两个格元都只获得了部分相关能量，峰值下降。对于非相干累加（N 个 1 ms 片段），单个格元的相关幅度与频偏的关系近似：

```
|R(Δf)| ≈ |sinc(Δf × T_coh)| = |sinc(Δf × 0.001)|
```

当步长为 500 Hz、偏移为 250 Hz（格间中点）时：

```
损失 = 20·log₁₀|sinc(250 × 0.001)| = 20·log₁₀|sinc(0.25)|
      ≈ 20·log₁₀(0.9003) ≈ −0.9 dB（单 ms 相干积分）
```

非相干累加后此损失基本保持（幅度而非功率叠加），约 **−1 dB 峰值下降**，是可接受的。

若步长加大到 1000 Hz，中点损失 ≈ −3.9 dB，更显著。

---

## 二、实验目标

1. **绘制"次峰比 vs 频偏"曲线**，找到捕获从成功过渡到失败的临界频偏值 `f_critical`。
2. **量化 Doppler 步长对分格损失的影响**：对比步长 250 / 500 / 1000 Hz 下的次峰比退化曲线。
3. **确定当前搜索范围 ±10 kHz 的实际保护余量**：在基线 SNR（PRN1，近场环回）下，次峰比曲线在何处降到阈值 2.5 以下？
4. **评估去 DC 与频偏的交叉影响**：去 DC 依赖 `mean(samples)`，人为频偏是否影响 DC 估计（理论上不应，但需验证）。

---

## 三、实验设计

### 3.1 频偏注入方法

在 MATLAB 分析阶段，加载 IQ 样本后，在送入 `run_prn_acquisition` 前乘以一个复指数来模拟接收机本振误差：

```matlab
% 注入人为频偏 f_offset_hz（单位 Hz）
% 正值 = RX 本振偏高，等效信号向负 Doppler 方向移动
t_vec = (0 : length(samples)-1)' / meta.sample_rate_hz;
samples_shifted = samples .* exp(1j * 2 * pi * f_offset_hz * t_vec);

% 然后送入标准捕获函数
result = run_prn_acquisition(samples_shifted, meta, cfg);
```

> **注意：** 频偏注入在**样本域**完成，无需修改 `run_prn_acquisition.m` 本身。所有现有测试不受影响。

### 3.2 测试频偏网格

分两段扫描：

**细粒度扫描（分格损失区间，覆盖 ±0 ~ ±2000 Hz）**

| 频偏（Hz） | 意义 |
|-----------|------|
| 0 | 基线（无偏移） |
| ±100 | 小于一个步长格（步长 500 Hz 的 1/5） |
| ±250 | 步长 500 Hz 格间中点（最大分格损失） |
| ±500 | 恰好落在下一个格元 |
| ±750 | 步长 500 Hz 格间中点 |
| ±1000 | 两个格元外 |
| ±1500 | 三个格元外 |
| ±2000 | 四个格元外 |

**粗粒度扫描（搜索范围边界与超范围测试）**

| 频偏（Hz） | 意义 |
|-----------|------|
| ±3000 | 搜索范围中段 |
| ±5000 | 搜索范围 ±10 kHz 的一半 |
| ±8000 | 接近搜索范围边界 |
| ±9500 | 搜索范围 ±10 kHz 内的次末格 |
| ±10000 | 搜索范围边界（≈ 最后一格） |
| ±11000 | 刚超出搜索范围 |
| ±15000 | 明显超出搜索范围（预期捕获失败） |

### 3.3 Doppler 步长对比组

对同一数据集（基线 PRN1 采集），分别使用三种步长配置运行完整频偏扫描：

| 配置 | `doppler_step_hz` | `doppler_min/max_hz` | 格元总数 |
|------|------------------|----------------------|---------|
| 粗步长 | 1000 Hz | ±10000 | 21 |
| **当前默认** | **500 Hz** | **±10000** | **41** |
| 细步长 | 250 Hz | ±10000 | 81 |

### 3.4 数据来源

本实验**优先使用已有采集数据或合成数据**，无需额外 RF 采集：

**选项 A（推荐，无硬件）— 合成数据**

```bash
cd /home/shen/projects/GNSS_RX
PYTHONPATH=/home/shen/projects/gnss_tx/src:src \
  python3 scripts/gen_synthetic_capture.py \
  --config configs/rx_prn1_sn193982.yaml \
  --snr-db 10 \
  --duration 2
```

合成数据的优点：SNR 精确已知、无 LO 泄露干扰、可控重复，适合单独研究频偏效应。

**选项 B — 真实采集数据（近场环回）**

复用 `2026-03-26_prn_subset_snr_debug.md` 中实验①的采集文件（PRN1，tx_gain=20dB，次峰比 3.2）。

建议同时用 A 和 B，对比合成数据（纯理论）与真实 RF 数据（含 LO 泄露）的结果差异。

---

## 四、详细实验步骤

### 步骤 0：准备阶段（约 15 分钟）

1. 确认 MATLAB 工作路径和环境变量：
   ```matlab
   addpath(genpath('/home/shen/projects/GNSS_RX/matlab'));
   setenv('GNSS_RX_DATA_DIR', '/mnt/hgfs/GongXiangDocument/GNSS_RX_Data');
   ```

2. 生成合成数据（SNR = 10 dB，2 秒）：
   ```bash
   cd /home/shen/projects/GNSS_RX
   PYTHONPATH=/home/shen/projects/gnss_tx/src:src \
     python3 scripts/gen_synthetic_capture.py \
     --config configs/rx_prn1_sn193982.yaml \
     --snr-db 10 --duration 2
   ```
   记录生成文件路径（`.sc16` + `.json`）。

3. 确认 `run_prn_acquisition.m` 默认参数：
   - `doppler_min_hz = -10000`, `doppler_max_hz = 10000`
   - `doppler_step_hz = 500`
   - `noncoherent_ms = 10`
   - `detection_threshold = 2.5`

### 步骤 1：基线验证（频偏 = 0）

```matlab
[samples, meta] = load_gnss_rx_capture('<合成数据路径>.json');

cfg = struct();
cfg.noncoherent_ms  = 10;
cfg.doppler_min_hz  = -10000;
cfg.doppler_max_hz  =  10000;
cfg.doppler_step_hz = 500;

result_baseline = run_prn_acquisition(samples, meta, cfg);
fprintf('基线次峰比: %.3f，捕获: %d\n', result_baseline.secondary_peak_ratio, result_baseline.acquired);
```

预期：次峰比 ≥ 5（合成数据，SNR=10 dB，信噪比比真实 RF 更干净）。

### 步骤 2：细粒度频偏扫描（±0 ~ ±2000 Hz）

```matlab
fine_offsets = [0, 100, 250, 500, 750, 1000, 1500, 2000, ...
               -100, -250, -500, -750, -1000, -1500, -2000];
t_vec = (0:length(samples)-1)' / meta.sample_rate_hz;

spr_fine = zeros(size(fine_offsets));
for k = 1:numel(fine_offsets)
    f_off = fine_offsets(k);
    shifted = samples .* exp(1j * 2*pi * f_off * t_vec);
    res = run_prn_acquisition(shifted, meta, cfg);
    spr_fine(k) = res.secondary_peak_ratio;
    fprintf('频偏 %+6d Hz: 次峰比 = %.3f  %s\n', f_off, spr_fine(k), ...
            res.acquired ? '✓' : '✗');
end
```

### 步骤 3：粗粒度频偏扫描（±3000 ~ ±15000 Hz）

```matlab
coarse_offsets = [3000, 5000, 8000, 9500, 10000, 11000, 15000, ...
                 -3000, -5000, -8000, -9500, -10000, -11000, -15000];

spr_coarse = zeros(size(coarse_offsets));
for k = 1:numel(coarse_offsets)
    f_off = coarse_offsets(k);
    shifted = samples .* exp(1j * 2*pi * f_off * t_vec);
    res = run_prn_acquisition(shifted, meta, cfg);
    spr_coarse(k) = res.secondary_peak_ratio;
end
```

### 步骤 4：Doppler 步长对比

```matlab
step_sizes = [250, 500, 1000];  % Hz
colors     = {'b', 'r', 'k'};

all_offsets = sort(unique([fine_offsets, coarse_offsets]));
t_vec = (0:length(samples)-1)' / meta.sample_rate_hz;

figure; hold on;
for s_idx = 1:numel(step_sizes)
    cfg_s = cfg;
    cfg_s.doppler_step_hz = step_sizes(s_idx);

    spr_sweep = zeros(size(all_offsets));
    for k = 1:numel(all_offsets)
        shifted = samples .* exp(1j * 2*pi * all_offsets(k) * t_vec);
        res = run_prn_acquisition(shifted, meta, cfg_s);
        spr_sweep(k) = res.secondary_peak_ratio;
    end
    plot(all_offsets, spr_sweep, [colors{s_idx} '-o'], ...
         'DisplayName', sprintf('步长 %d Hz', step_sizes(s_idx)));
end
yline(2.5, 'g--', '捕获阈值 2.5');
xlabel('注入频偏 (Hz)'); ylabel('次峰比');
title('次峰比 vs 频偏（不同 Doppler 步长）');
legend show; grid on;
```

### 步骤 5：合成数据 vs 真实 RF 数据对比

重复步骤 2~3，将 `samples` 替换为真实 RF 采集数据（`2026-03-26_prn_subset_snr_debug.md` 实验①），在同一张图上叠加绘制，观察 LO 泄露是否改变频偏容限。

### 步骤 6：去 DC 与频偏的交叉验证

```matlab
% 理论：频偏注入后，samples 的均值（DC 分量）不变，去 DC 不影响
% 验证：比较去 DC 前后，频偏注入点的次峰比是否有差异

f_test_offsets = [0, 250, 500, 1000, 5000];
for k = 1:numel(f_test_offsets)
    shifted = samples .* exp(1j * 2*pi * f_test_offsets(k) * t_vec);

    % 标准（含去 DC）
    res_with_dc = run_prn_acquisition(shifted, meta, cfg);

    % 手动去 DC 前比较 DC 幅度
    dc_before = abs(mean(shifted));
    dc_after  = abs(mean(shifted - mean(shifted)));
    fprintf('偏移 %5d Hz: DC 幅度 before=%.4f, after=%.4f, 次峰比=%.3f\n', ...
            f_test_offsets(k), dc_before, dc_after, res_with_dc.secondary_peak_ratio);
end
```

---

## 五、预期结果与关键图表

### 图 1 — 次峰比 vs 频偏（总览曲线）

```
次峰比
 10 |                               --------
    |                              /        \
  5 |                     --------            --------
    |              -------                           ------
  2.5|- - - - - - - - - - - - - - - - - - - - - - - - - - -（阈值）
    |         ---                                          ---
  1 |--------                                                  ---------
    +---+---+---+---+---+---+---+---+---+---+---+---+---+---+---+--->
      -15k -10k -8k -5k -3k -1k  0   1k  3k  5k  8k  10k 12k 15k  Hz
```

形状预期：
- 在 ±10 kHz 以内：次峰比维持在基线附近，250 Hz 格间有小幅波动（~−1 dB）
- 在 ±10 kHz 边界：次峰比急剧下降（信号滑出搜索范围）
- 在 ±12 kHz 以上：次峰比 ≈ 1（捕获失败）

### 图 2 — 分格损失细节（±0 ~ ±2000 Hz 放大图）

展示 500 Hz 步长下的周期性次峰比波动（周期恰为步长 500 Hz），以及 250 Hz 步长的更平坦曲线。

### 图 3 — 捕获搜索图热图对比（频偏 0 vs 频偏 250 Hz vs 频偏 5000 Hz）

三张热图并排，直观显示频偏如何导致主峰在 Doppler 轴方向漂移。

### 图 4 — f_critical 汇总表

| 数据来源 | Doppler 步长 | 正向 `f_critical` | 负向 `f_critical` |
|----------|------------|------------------|------------------|
| 合成数据（SNR=10 dB） | 500 Hz | ~ Hz | ~ Hz |
| 真实 RF（近场，SNR≈3） | 500 Hz | ~ Hz | ~ Hz |
| 合成数据 | 250 Hz | ~ Hz | ~ Hz |
| 合成数据 | 1000 Hz | ~ Hz | ~ Hz |

（`f_critical`：次峰比降到 2.5 阈值以下的最小频偏值，实验后填写）

---

## 六、与 LO 泄露研究的关联

本实验与同日 [`2026-03-27_lo_leakage_acquisition_study.md`](./2026-03-27_lo_leakage_acquisition_study.md) 互为补充：

| 研究维度 | LO 泄露研究 | 频偏稳定性研究 |
|---------|-------------|---------------|
| 干扰来源 | TX 端对空辐射泄露 | RX 本振误差（人为注入） |
| 搜索图影响 | 底噪抬高，峰值不变 | 主峰在 Doppler 轴漂移 |
| 主要退化路径 | 次峰比分母增大 | 次峰比分子减小（峰滑出格元） |
| 叠加效应 | **两者同时存在时，次峰比余量从两个方向被压缩** | 同左 |

**建议联合实验**：在完成本实验（得到 `f_critical`）后，在 LO 泄露存在的条件下（C1 近场配置），重新测量频偏容限，对比两者叠加后 `f_critical` 的退化量。

---

## 七、实验记录模板

执行完毕后，在同目录新建实验记录：

```
experiments/plans/2026-03-27/2026-03-27_freq_offset_results.md
```

至少包含：

- 合成数据参数（SNR、PRN、积分时间）
- 真实 RF 数据文件路径
- 次峰比 vs 频偏原始数据表（所有测试点）
- `f_critical`（三种步长各一个值）
- 分格损失实测值 vs 理论预测（sinc 模型）对比
- 对后续实验的建议（Doppler 搜索步长、范围是否需要调整）
