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

- [ ] 预期：PRN 1、5、10、15 的柱状图超过红线 2.5
- [ ] 若仍不过，考虑步骤 4（增加 MATLAB 积分时间）代替继续升增益

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

## 参考配置文件

| 文件 | 路径 |
|------|------|
| TX 子集配置 | `gnss_tx/configs/tx_b210_prn_subset.yaml` |
| TX 可见谱配置 | `gnss_tx/configs/tx_b210_visible_spectrum.yaml` |
| RX 多星采集配置 | `GNSS_RX/configs/rx_all32prn.yaml` |
| MATLAB 分析入口 | `GNSS_RX/matlab/scripts/run_capture_analysis.m` |
