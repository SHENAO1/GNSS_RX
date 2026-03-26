# 2026-03-26 多星子集捕获失败分析

**日期**：2026-03-26
**分支**：gnss_tx `feat/prn-subset-tx` / GNSS_RX `feat/multi-prn-rx`
**目标**：在单星 PRN1 捕获成功的基础上，验证多星子集（PRN 1,5,10,15）的端到端收发链路

---

## 实验记录

### 配置与结果汇总

| 序号 | TX 配置 | tx_gain | amplitude | 发射 PRN | 次峰比 | 结论 |
|------|---------|---------|-----------|---------|--------|------|
| ①    | `tx_b210_visible_spectrum.yaml --tx-gain 20` | 20 dB | 1.0 | PRN1（单星） | **3.216** | **捕获成功** |
| ②    | `--prn-ids 1,5,10,15`（默认配置） | 0 dB | 0.25 | 4 星叠加 | 1.011 | 失败 |
| ③    | `tx_b210_visible_spectrum.yaml --prn-ids 1,5,10,15 --amplitude 0.5` | 10 dB | 0.5 | 4 星叠加 | 1.001 | 失败 |
| ④    | `tx_b210_visible_spectrum.yaml --prn-ids 1,5,10,15 --amplitude 0.5 --tx-gain 30`（等 TX 启动后再采集） | 30 dB | 0.5 | 4 星叠加 | ~1.4（PRN1）/ ~1.35（PRN5,10）/ ~1.25（PRN15） | **部分可见，未过门限** |
| ⑤    | 同④文件，MATLAB 积分时间改为 100ms（重新分析） | 30 dB | 0.5 | 4 星叠加 | ~2.25（PRN1）/ ~2.0（PRN5）/ **~2.4（PRN10）** / ~2.2（PRN15） | **峰值显著升高，差约 0.1~0.5 未过门限** |
| ⑥    | `tx_b210_visible_spectrum.yaml --prn-ids 1,5,10,15 --amplitude 0.5 --tx-gain 35`，100ms 积分 | 35 dB | 0.5 | 4 星叠加 | **8.5（PRN1）/ 8.6（PRN5）/ 8.9（PRN10）/ 8.3（PRN15）** | **✅ 捕获成功（4/32）** |
| ⑦    | 同⑥采集文件，MATLAB 积分时间改为 20ms（重新分析） | 35 dB | 0.5 | 4 星叠加 | **6.1（PRN1）/ 6.3（PRN5）/ 6.7（PRN10）/ 6.3（PRN15）** | **✅ 捕获成功，5× 提速** |
| ⑧    | 同⑥采集文件，MATLAB 积分时间改为 10ms（重新分析） | 35 dB | 0.5 | 4 星叠加 | **5.1（PRN1）/ 5.6（PRN5）/ 5.6（PRN10）/ 4.6（PRN15）** | **✅ 捕获成功，10× 提速** |

> 四次 RX 均使用 `--config configs/rx_all32prn.yaml`，采集时长 2 秒。

**实验④关键发现**：PRN 1、5、10、15 的次峰比已明显高于其余 28 颗（~1.0），
**信号链路和码选择均正确**，仅差 SNR 不足以过 2.5 门限。

---

## 失败原因分析

### 原因 A：TX 启动时序问题（首要怀疑）

GNU Radio + USRP 流图从启动到实际出流约需 **2~3 秒**（USRP 固件握手 + 流图初始化）。
RX 采集窗口只有 **2 秒**（`duration_s: 2.0`）。

若用户启动 TX 后立刻运行 RX 命令，可能整个 2 秒录制窗口都落在 TX 出流之前，录到的是纯噪声。

**佐证**：
- 实验③的次峰比 1.001，比实验②的 1.011 还低，说明不是"信号弱"而是"信号完全不在录制窗口内"
- 实验①之所以成功，可能是用户在 TX 启动后等待了足够长时间再启动 RX

---

### 原因 B：每颗 PRN 的 SNR 不足（结构性原因）

多星叠加时，TX 发出的是 N 颗 PRN 的合并信号，经 √N 功率归一化。
RX 端相关器对单颗 PRN 的有效输入幅度为：

```
per_prn_amplitude = amplitude × tx_scale(tx_gain) / sqrt(N)
```

以实验①为基准做 SNR 预算：

| | 实验① 基准 | 实验③ 子集 |
|--|-----------|-----------|
| tx_gain | 20 dB | 10 dB |
| amplitude | 1.0 | 0.5 |
| 每星有效幅度（相对） | `1.0` | `0.5 / sqrt(4) = 0.125` |
| 幅度差 | 基准 | **−18 dB**（幅度）→ **−18 dB** SNR |
| TX 增益差 | 基准 | **−10 dB** |
| **每星 SNR 总差** | 基准 | **约 −28 dB** |

实验①本身次峰比仅 3.216（阈值 2.5），属于刚刚通过。
任何方向的 SNR 下降都会导致失败。

---

## 下一步操作清单

按优先级依次尝试，每步确认后再进行下一步。

### ✅ 步骤 1：验证 TX 启动时序（解决原因 A）

TX 启动后**等待 5~10 秒**再启动 RX，确保 TX 已稳定出流：

```bash
# 终端 1：启动 TX，等待出现 "Press Ctrl-C to stop" 提示再切换终端
cd ~/projects/gnss_tx
PYTHONPATH=src python3 scripts/run_tx.py \
    --config configs/tx_b210_visible_spectrum.yaml \
    --prn-ids 1,5,10,15 --amplitude 0.5

# 终端 2：看到 TX 启动完成后再运行（约等 5 秒）
cd /home/shen/projects/GNSS_RX
PYTHONPATH=src python3 scripts/record_rx.py --config configs/rx_all32prn.yaml
```

- [x] 实验④验证：等待 TX 出流后采集，PRN 1/5/10/15 次峰比升至 ~1.4，时序问题已解决
- [x] 信号链路正确，进入步骤 2 解决 SNR 不足

---

### ⏳ 步骤 2：进一步提升 TX 增益过门限

实验④ tx_gain=30 dB 时次峰比约 1.4，距门限 2.5 仍有约 5 dB 差距。
继续提升 tx_gain：

```bash
# 终端 1
cd ~/projects/gnss_tx
PYTHONPATH=src python3 scripts/run_tx.py \
    --config configs/tx_b210_visible_spectrum.yaml \
    --prn-ids 1,5,10,15 --amplitude 0.5 --tx-gain 40

# 终端 2（等 TX 启动完成）
cd /home/shen/projects/GNSS_RX
PYTHONPATH=src python3 scripts/record_rx.py --config configs/rx_all32prn.yaml
```

- [x] 实验⑥验证：tx_gain=35 + 100ms 积分，PRN 1/5/10/15 次峰比 8.3~8.9，**全部捕获成功**
- [x] 步骤 4（100ms 积分）已验证有效：次峰比从 ~1.4 升至 ~2.0~2.4，差 0.1~0.5 即可过门限

---

### 步骤 3：先用 2-PRN 子集缩小问题范围

2 颗 PRN 叠加的每星 SNR 损失只有 1/√2（约 −3 dB），比 4 颗（−6 dB）更容易通过：

```bash
# TX
cd ~/projects/gnss_tx
PYTHONPATH=src python3 scripts/run_tx.py \
    --config configs/tx_b210_visible_spectrum.yaml \
    --prn-ids 1,5 --amplitude 0.7 --tx-gain 20

# RX（等 TX 启动完成）
cd /home/shen/projects/GNSS_RX
PYTHONPATH=src python3 scripts/record_rx.py --config configs/rx_all32prn.yaml
```

- [ ] 若 PRN 1、5 出峰，说明链路正常，逐步增加 PRN 数量验证

---

### ✅ 步骤 4：增加 MATLAB 积分时间（提升算法灵敏度）

非相干累加时间从 10 ms 增加到 100 ms（10×），理论 SNR 提升约 **+10 dB**：

| `noncoherent_ms` | 积分增益 | 说明 |
|-----------------|---------|------|
| 10 ms（原值） | 基准 | 实验④次峰比约 1.4 |
| 100 ms（新值） | **+10 dB** | 预期次峰比超过 2.5 |

已修改以下三处默认值（均改为 100）：
- `matlab/scripts/run_capture_analysis.m`：`cfg.noncoherent_ms = 100`
- `matlab/functions/run_multi_prn_survey.m`：`cfg.noncoherent_ms = 100`
- `matlab/functions/run_prn_acquisition.m`：`cfg.noncoherent_ms = 100`

> 注意：2 秒采集文件含 2000 ms 数据，100 ms 积分足够。运行时间约为原来 10×。

**amplitude 不可超过 0.5 的原因**：

对 N 颗 PRN 叠加，信号峰值 = √N × amplitude，须不超过 DAC 上限 1.0：

| amplitude | N=4 峰值 | DAC 状态 |
|-----------|---------|----------|
| 0.5 | √4 × 0.5 = **1.0** | 安全上限 ✅ |
| 1.0 | √4 × 1.0 = **2.0** | 削波 ❌ |
| 2.0 | √4 × 2.0 = **4.0** | 严重削波 ❌ |

削波会破坏 C/A 码的自相关特性，使相关峰变宽消失，不可通过提升 amplitude 代替 tx_gain。

- [x] 已修改 MATLAB 积分时间为 100 ms

---

---

## 成功配置存档（实验⑥）

| 参数 | 值 |
|------|---|
| TX 命令 | `run_tx.py --config tx_b210_visible_spectrum.yaml --prn-ids 1,5,10,15 --amplitude 0.5 --tx-gain 35` |
| RX 命令 | `record_rx.py --config configs/rx_all32prn.yaml` |
| MATLAB 积分时间 | 100 ms（`noncoherent_ms=100`） |
| 捕获结果 | PRN 1/5/10/15 次峰比 8.3~8.9，其余 28 颗 ~1.0 |
| 文件 stem | `20260326_154940_rawiq_sc16_zeroif_prn_all32_spread_sr4092000_cf100000000_dur2p0s` |

**关键经验**：
- tx_gain=35，amplitude=0.5（4 颗 PRN 安全上限）
- MATLAB 积分时间 100ms（20ms 为速度/灵敏度折中，后续待验证）
- TX 启动后须等到流图稳定（约 10~30 秒，出现 underflow 提示即可开始 RX 采集）

---

## 下一步计划

### 阶段一：确定最小可用积分时间

目标：找到能可靠捕获的最小 `noncoherent_ms`，减少 MATLAB 运行时间。

实验⑥次峰比 8.5，门限 2.5，理论安全裕量约 10 dB，积分时间可大幅缩短：

| 积分时间 | 相对 100ms | 预期次峰比（估算） | 运行时间 |
|---------|-----------|--------------|--------|
| 100 ms | 基准 | 8.5 | 慢（已验证） |
| **20 ms** | −7 dB | **~6.4（实测）** | **5× 快（当前默认）** ✅ |
| **10 ms** | −10 dB | **~5.2（实测）** | **10× 快** ✅ |

- [x] 用实验⑥采集文件重跑 `noncoherent_ms=20`，次峰比 6.1 / 6.3 / 6.7 / 6.3，**全部通过**（5× 提速）
- [x] 用实验⑥采集文件重跑 `noncoherent_ms=10`，次峰比 5.1 / 5.6 / 5.6 / 4.6，**全部通过**（10× 提速）

#### MATLAB 分析命令（不修改代码，通过传参覆盖积分时间）

```matlab
% 指定积分时间的通用写法：构造 cfg 结构体，只需填要覆盖的字段，其余自动用默认值
cfg = struct('noncoherent_ms', 10);   % 改为 20 或 100 即可切换

% Windows 宿主机完整路径示例（根据实际文件路径修改）
result = run_capture_analysis( ...
    'C:\VMwareVirtualMachines\GongXiangDocument\GNSS_RX_Data\2026\2026_03_26\20260326_154940_rawiq_sc16_zeroif_prn_all32_spread_sr4092000_cf100000000_dur2p0s\20260326_154940_rawiq_sc16_zeroif_prn_all32_spread_sr4092000_cf100000000_dur2p0s.json', ...
    cfg);
```

> **说明**：`run_capture_analysis` 第二个参数 `cfg` 中只需填想覆盖的字段，
> 未填字段自动使用 `build_default_cfg` 的默认值（当前默认 `noncoherent_ms=20`）。
> 不传第二个参数则完全使用默认配置。

---

### 阶段二：验证全 32 颗 PRN 叠加捕获

目标：确认 32 星叠加时（每颗星 SNR 降低 √32 倍）是否还能可靠捕获。

```bash
# TX：发射全部 32 颗 PRN
cd ~/projects/gnss_tx
PYTHONPATH=src python3 scripts/run_tx.py \
    --config configs/tx_b210_all32prn.yaml --tx-gain 35

# RX（等 TX 启动稳定）
cd /home/shen/projects/GNSS_RX
PYTHONPATH=src python3 scripts/record_rx.py --config configs/rx_all32prn.yaml
```

- [ ] 预期 32/32 颗均出峰；若捕获率不足，提升 tx_gain 或积分时间

---

### 阶段三：SNR 边界测试（可选）

目标：了解链路的 SNR 余量，确定 tx_gain 的最低可用值。

- [ ] 固定 `noncoherent_ms=20`，逐步降低 `tx_gain`：35 → 30 → 25 → 20
- [ ] 记录每个增益下次峰比，找到捕获失败的临界点
- [ ] 绘制 tx_gain vs 次峰比 曲线

---

## 参考配置文件

| 文件 | 路径 |
|------|------|
| TX 子集配置 | `gnss_tx/configs/tx_b210_prn_subset.yaml` |
| TX 可见谱配置 | `gnss_tx/configs/tx_b210_visible_spectrum.yaml` |
| RX 多星采集配置 | `GNSS_RX/configs/rx_all32prn.yaml` |
| MATLAB 分析入口 | `GNSS_RX/matlab/scripts/run_capture_analysis.m` |
