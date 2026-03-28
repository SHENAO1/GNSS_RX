# 接收端实验计划：闭环 BER 验证（收端视角）

> 创建时间：2026-03-28
> 对应发射端计划：`/home/shen/projects/gnss_tx/experiments/plans/2026-03-28/ber_loopback_tx/2026-03-28_ber_loopback_tx_plan.md`
> 参考昨日收端计划：`/home/shen/projects/GNSS_RX/experiments/plans/2026-03-27/ber_loopback_rx/2026-03-27_ber_loopback_rx_plan.md`
> 状态：`[~]` truth 契约、tracked BER 主链和 chunked 采集接口已实现，待宿主机验证 30 s 低 BER
> 里程碑目标：Milestone 1 — 先在固定 30 s 样本上收敛，再扩展到 250 s / 1 h

---

## 一、当前目标

当前主线不再是“继续补 MATLAB 基础脚本”，而是让现有链路真正收敛：

1. 冻结当前 `20260328_142122...dur30p0s` 采集文件作为软件回归基线。
2. 在宿主机 MATLAB 上跑通 `tracked_truth`，优先把 30 s BER 拉到低误码。
3. 在 30 s 收敛后，再做新的 30 s 复验。
4. 然后扩展到 `250 s`，最后扩展到 `1 h`。

在 30 s BER 收敛前，默认不并行调整大量 RF 变量。

---

## 二、当前代码状态

### 2.1 已落地能力

| 功能 | 状态 | 文件 |
|------|------|------|
| USRP B210 IQ 采集 | ✅ 已实现 | `scripts/record_rx.py` |
| `single/chunked` 双采集模式 | ✅ 已实现 | `scripts/record_rx.py` + `src/gnss_rx/runtime.py` |
| chunk 元数据记录 | ✅ 已实现 | `src/gnss_rx/metadata.py` |
| MATLAB 数据加载 | ✅ 已实现 | `matlab/functions/load_gnss_rx_capture.m` |
| MATLAB GPS L1 C/A 捕获 | ✅ 已实现 | `matlab/functions/run_prn_acquisition.m` |
| truth JSON 加载 | ✅ 已实现 | `matlab/functions/load_tx_truth_json.m` |
| fallback truth 构造 | ✅ 已实现 | `matlab/functions/build_fallback_tx_truth.m` |
| open-loop truth 基线 | ✅ 已实现 | `matlab/functions/recover_nav_bits.m` |
| tracked BER 主链 | ✅ 已实现 | `matlab/functions/track_nav_bits.m` |
| BER 双路径主脚本 | ✅ 已实现 | `matlab/scripts/run_ber_loopback.m` |
| 新版 BER / tracking 绘图 | ✅ 已实现 | `matlab/functions/plot_ber_loopback.m` |

### 2.2 已确认结论

- TX 侧 truth JSON 已接通，RX 不再依赖手写 `TX_PATTERN` 作为唯一真值。
- `open_loop_truth` 已证明问题更像 time-varying drift，而不是 TX pattern 错误。
- 当前主矛盾已经收敛到 RX：需要验证 tracked BER 主链能否稳定压低 30 s BER。
- `record_rx.py` 的 `single/chunked` 接口与 Python 回归测试已通过。

### 2.3 当前未完成项

- 宿主机 MATLAB 尚未实跑新版 `tracked_truth`。
- “30 s BER < 1e-3”尚未被验证。
- 250 s 和 1 h 目前只有接口与流程就绪，尚未开始正式回归。

---

## 三、冻结的实验基线

在 30 s BER 收敛前，默认冻结以下基线：

| 项目 | 当前基线 |
|------|----------|
| TX 设备 | `serial=193982` |
| RX 天线口 | `RX2` |
| 中心频率 | `100 MHz` |
| 采样率 | `4.092 Msps` |
| 接线 | `B210 TX(TX/RX) -> 同轴线 -> B210 RX(RX2)` |
| RX 设备 serial | `8003272`（两台设备直连时必须在 `usrp_addr` 中指定，避免与 TX 冲突） |
| truth | `tx_truth.json` |
| 回归采集文件 | `20260328_142122...dur30p0s` |

在这一阶段，不建议同时修改：

- 接线方式
- 收端采样率
- 导航模式
- MATLAB truth 来源
- 长时采集时长

---

## 四、推荐执行顺序

### Step 0：导出并确认 truth JSON

```bash
cd /home/shen/projects/gnss_tx
env PYTHONPATH=src python3 scripts/run_tx.py \
    --config configs/tx_b210_cable_loopback.yaml \
    --tx-gain 40 \
    --amplitude 1.0 \
    --dry-run \
    --export-truth-json /mnt/hgfs/GongXiangDocument/GNSS_RX_matlab/tx_truth.json
```

完成标志：

- [ ] `tx_truth.json` 已导出到宿主机共享目录
- [ ] dry-run 输出中的 `nav_pattern`、`initial_nav_bit_index`、`initial_nav_epoch` 正确

### Step 1：同步 MATLAB 文件到宿主机共享目录

推荐至少同步以下文件：

- `matlab/scripts/run_ber_loopback.m`
- `matlab/functions/recover_nav_bits.m`
- `matlab/functions/track_nav_bits.m`
- `matlab/functions/plot_ber_loopback.m`
- `matlab/functions/load_tx_truth_json.m`
- `matlab/functions/build_fallback_tx_truth.m`

```bash
cd /home/shen/projects/GNSS_RX
rsync -av matlab/ /mnt/hgfs/GongXiangDocument/GNSS_RX_matlab/
```

完成标志：

- [ ] 宿主机 `GNSS_RX_matlab` 已同步到最新版本
- [ ] `which run_ber_loopback -all` / `which track_nav_bits -all` 指向共享目录中的新文件

### Step 2：固定 30 s 样本跑 `tracked_truth`

在宿主机 MATLAB 中：

```matlab
cd('C:\VMwareVirtualMachines\GongXiangDocument\GNSS_RX_matlab')
addpath(fullfile(pwd, 'functions'));
addpath(fullfile(pwd, 'scripts'));
clear functions
rehash

TX_TRUTH_PATH = 'C:\VMwareVirtualMachines\GongXiangDocument\GNSS_RX_matlab\tx_truth.json';
BER_MODE = 'tracked_truth';
run('scripts/run_ber_loopback.m')
```

完成标志：

- [ ] 日志显示 `TX truth：JSON 模式`
- [ ] 日志显示 `=== Step 4: tracked BER 主链 ===`
- [ ] 输出包含 tracked BER、匹配率和重同步信息

### Step 3：若 30 s 收敛，再做新的 30 s 复验

```bash
cd /home/shen/projects/GNSS_RX
env PYTHONPATH=src python3 scripts/record_rx.py \
    --config configs/rx_cable_loopback.yaml \
    --duration 30 \
    --capture-mode single
```

> **两台设备直连时**：加 `--usrp-addr "serial=8003272"` 指定 RX 设备，避免与 TX（serial=193982）冲突：
> ```bash
> env PYTHONPATH=src python3 scripts/record_rx.py \
>     --config configs/rx_cable_loopback.yaml \
>     --usrp-addr "serial=8003272" \
>     --duration 30 \
>     --capture-mode single
> ```
> 注意：两台独立 B210 各有自己的时钟，存在频率偏移属正常现象，FLL 会自动补偿。若 BER 偏高，优先检查 tracking 图中 FLL 是否收敛。

目标：

- [ ] 连续 3 份新 30 s 采集都能达到低 BER
- [ ] 若其中一份异常，能从 tracking 图解释，而不是只留下高 BER 数字

### Step 4：扩展到 250 s

```bash
cd /home/shen/projects/GNSS_RX
env PYTHONPATH=src python3 scripts/record_rx.py \
    --config configs/rx_cable_loopback.yaml \
    --duration 250 \
    --capture-mode single
```

目标：

- [ ] 总 BER 保持低误码
- [ ] 无长时间失锁区间

### Step 5：准备 1 h

1 h 默认优先 `chunked`，但保留 `single`：

```bash
cd /home/shen/projects/GNSS_RX
env PYTHONPATH=src python3 scripts/record_rx.py \
    --config configs/rx_cable_loopback.yaml \
    --duration 3600 \
    --capture-mode chunked \
    --chunk-duration 30 \
    --dry-run
```

```bash
cd /home/shen/projects/GNSS_RX
env PYTHONPATH=src python3 scripts/record_rx.py \
    --config configs/rx_cable_loopback.yaml \
    --duration 3600 \
    --capture-mode single \
    --dry-run
```

目标：

- [ ] `chunked` 与 `single` 都能正常生成采集计划
- [ ] 长时实验默认走 `chunked`

---

## 五、当前验收标准

### 5.1 30 s 回归基线

- [ ] `tracked_truth` BER `< 1e-3`
- [ ] `ambiguity_flag = false`
- [ ] 100-bit 滑窗 BER 不再周期性在 `0% ~ 100%` 间摆动
- [ ] 码相位、频偏、相位误差曲线平稳

### 5.2 新 30 s 复验

- [ ] 连续 3 次短时采集 BER `< 1e-3`
- [ ] 若失败，能够在 tracking 图中定位失锁原因

### 5.3 250 s

- [ ] 恢复总比特数 `>= 10^4`
- [ ] 总 BER 保持低误码
- [ ] 结果文件包含 truth、open-loop、tracked 和 tracking 历史

---

## 六、当前风险与排查优先级

优先级从高到低：

1. 宿主机 MATLAB 仍在跑旧文件
2. `tracked_truth` 在宿主机 MATLAB 首次实跑时暴露语法或接口问题
3. RX 的码相位/bit timing 跟踪仍不够稳
4. 新采集重新引入新的 RF 变量

如需更细的排障步骤，执行 [2026-03-28_ber_loopback_debug_playbook.md](2026-03-28_ber_loopback_debug_playbook.md)。
