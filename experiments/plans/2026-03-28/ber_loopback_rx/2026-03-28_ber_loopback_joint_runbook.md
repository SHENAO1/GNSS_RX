# 闭环 BER 联合执行手册（TX/RX 一体版）

> 创建时间：2026-03-28
> 适用场景：Milestone 1 射频线直连闭环 BER 验证
> 存放策略：本文件在 `gnss_tx` 与 `GNSS_RX` 各保留一份，内容应保持一致
> 关联原计划：
> - `/home/shen/projects/gnss_tx/experiments/plans/2026-03-28/ber_loopback_tx/2026-03-28_ber_loopback_tx_plan.md`
> - `/home/shen/projects/GNSS_RX/experiments/plans/2026-03-28/ber_loopback_rx/2026-03-28_ber_loopback_rx_plan.md`

---

## 一、这份手册解决什么问题

原始 TX/RX 计划是分开写的，实际执行时容易来回跳。本文把它们合并成一条真实操作链，只保留当前最需要的顺序：

1. 先固定离线基线。
2. 先导出 TX truth JSON。
3. 先在宿主机 MATLAB 上把固定 30 s 样本的 `tracked_truth` 跑通。
4. 离线 30 s 收敛后，再做新的联机 30 s 复验。
5. 最后扩展到 `250 s` 和 `1 h`。

一句话总结：

```text
先离线收敛，再联机复验；先 30 s，再 250 s，再 1 h。
```

---

## 二、当前冻结基线

| 项目 | 当前基线 |
|------|----------|
| TX 设备 | `serial=193982` |
| RX 设备 | `serial=8003272` |
| 中心频率 | `100 MHz` |
| 采样率 | `4.092 Msps` |
| RX 天线口 | `RX2` |
| TX 配置 | `configs/tx_b210_cable_loopback.yaml` |
| RX 配置 | `GNSS_RX/configs/rx_cable_loopback.yaml` |
| nav pattern | `1 0 1 1 0 0 1 0` |
| truth 文件 | `tx_truth.json` |
| 30 s 回归样本 | `20260328_142122...dur30p0s` |

当前默认不要同时修改：

- 接线方式
- 中心频率
- 采样率
- nav pattern
- MATLAB truth 来源
- 长时采集时长

---

## 三、先看这个判断表

### 3.1 不需要开真实 USRP 的步骤

- 固定旧的 `30 s` IQ 样本做离线分析
- TX `--dry-run` 导出 truth JSON
- 同步 MATLAB 脚本到宿主机共享目录
- 在宿主机 MATLAB 上跑 `tracked_truth`
- `1 h` 采集命令的 `--dry-run`

### 3.2 需要真实 TX/RX 同时参与的步骤

- 新的 `30 s` 联机复验
- `250 s` 联机采集
- `1 h` 联机采集

### 3.3 联机实验的启动规则

- TX 先启动，RX 后启动。
- TX 发射时长要长于 RX 采集时长，避免边界切掉有效数据。
- 做 `30 s` RX 采集时，TX 推荐发 `60 s`。
- 做 `250 s` RX 采集时，TX 推荐发 `300 s`。
- 两台独立 B210 时，RX 必须固定 `serial=8003272`，避免抢到 TX。

---

## 四、统一执行顺序

### Step 0：冻结本轮离线回归基线

目标：先不要重新采集，先用已经固定的 `30 s` 文件验证软件链路。

回归样本：

```text
C:\VMwareVirtualMachines\GongXiangDocument\GNSS_RX_Data\2026\2026_03_28\20260328_142122_rawiq_sc16_zeroif_prn1_spread_sr4092000_cf100000000_dur30p0s
```

完成标志：

- [ ] 本轮先固定使用该 `30 s` 样本
- [ ] 中途不更换采集文件

### Step 1：TX 导出并确认 truth JSON

这一步只需要 TX 侧做 `dry-run`，不需要真实 RX 同时接收。

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

- [ ] `tx_truth.json` 已导出到共享目录
- [ ] dry-run 输出中的 `nav_pattern`、`initial_nav_bit_index`、`initial_nav_epoch` 正确

### Step 2：同步 MATLAB 脚本到宿主机共享目录

```bash
cd /home/shen/projects/GNSS_RX
rsync -av matlab/ /mnt/hgfs/GongXiangDocument/GNSS_RX_matlab/
```

建议重点确认这些文件已经是新版本：

- `matlab/scripts/run_ber_loopback.m`
- `matlab/functions/recover_nav_bits.m`
- `matlab/functions/track_nav_bits.m`
- `matlab/functions/plot_ber_loopback.m`
- `matlab/functions/load_tx_truth_json.m`
- `matlab/functions/build_fallback_tx_truth.m`

另外确认根目录存在快捷入口脚本（**不在 `matlab/` 子目录下，rsync 不会覆盖它**）：

- `GNSS_RX_matlab/ber.m`

`ber.m` 直接存放在宿主机共享目录根目录，修改或首次部署时需手动复制，不通过 rsync 管理。

完成标志：

- [ ] 宿主机共享目录中的 MATLAB 文件已同步
- [ ] `which run_ber_loopback -all` / `which track_nav_bits -all` 指向共享目录新文件
- [ ] `C:\VMwareVirtualMachines\GongXiangDocument\GNSS_RX_matlab\ber.m` 存在

### Step 3：宿主机 MATLAB 跑固定 30 s 样本的 `tracked_truth`

这一步仍然是离线分析，不需要真实 TX/RX 同时开机。

**一次性初始化**（首次使用或 MATLAB 重启后执行一次，让 `ber` 命令可以被找到）：

```matlab
cd('C:\VMwareVirtualMachines\GongXiangDocument\GNSS_RX_matlab')
```

之后的每次分析，直接在命令行输入：

```matlab
ber
```

`ber` 脚本会自动完成 `addpath`、`rehash`、`TX_TRUTH_PATH` 设置，并调用 `run_ber_loopback.m`。

操作提示：

- `ber` 执行后，脚本会提示”检测到最新采集文件，直接分析最新文件请按回车”。
- `TX_TRUTH_PATH` 自动指向 `GNSS_RX_matlab\tx_truth.json`，无需手动设置。
- 若本轮目标是严格复现固定 `30 s` 基线，应显式指定 `CAPTURE_PATH`，避免误选到更新采集。

固定回归样本的推荐写法：

```matlab
CAPTURE_PATH = ['C:\VMwareVirtualMachines\GongXiangDocument\GNSS_RX_Data\2026\' ...
    '2026_03_28\20260328_142122_rawiq_sc16_zeroif_prn1_spread_sr4092000_' ...
    'cf100000000_dur30p0s\20260328_142122_rawiq_sc16_zeroif_prn1_spread_' ...
    'sr4092000_cf100000000_dur30p0s'];
ber
```

完成标志：

- [ ] 日志显示 `TX truth：JSON 模式`
- [ ] 日志显示 `=== Step 4: tracked BER 主链 ===`
- [ ] 输出包含 tracked BER、匹配率和重同步信息

判定：

- 如果固定 `30 s` 样本都没有收敛，先停在这里排软件链路。
- 如果固定 `30 s` 样本已经收敛，再进入下一步联机复验。

### Step 4：联机 30 s 复验

这一轮开始，需要真实 TX 和真实 RX 同时参与。

先在 TX 端启动：

```bash
cd /home/shen/projects/gnss_tx
env PYTHONPATH=src python3 scripts/run_tx.py \
    --config configs/tx_b210_cable_loopback.yaml \
    --tx-gain 40 \
    --amplitude 1.0 \
    --duration 60
```

TX 启动稳定后，在 RX 端开始采集：

```bash
cd /home/shen/projects/GNSS_RX
env PYTHONPATH=src python3 scripts/record_rx.py \
    --config configs/rx_cable_loopback.yaml \
    --duration 30 \
    --capture-mode single
```

说明：

- `GNSS_RX/configs/rx_cable_loopback.yaml` 已固定 `usrp_addr: "serial=8003272"`。
- 如果仍想命令行显式覆盖，也可以加 `--usrp-addr "serial=8003272"`。

采集结束后，下一步是在宿主机 MATLAB 中分析这份“新生成的 30 s 采集”，而不是继续分析旧的 `20260328_142122...dur30p0s` 基线。

推荐动作：

1. 在 RX 终端记下 `record_rx.py` 输出里的采集文件 stem（文件名不含扩展名部分）。
2. 将 Linux 路径前缀换算为 Windows 路径（见下方规则）。
3. 在 MATLAB 中设置 `CAPTURE_PATH` 后执行 `ber`。

路径换算规则：

- VM/Linux 侧：`/mnt/hgfs/GongXiangDocument/GNSS_RX_Data/...`
- Windows/MATLAB 侧：`C:\VMwareVirtualMachines\GongXiangDocument\GNSS_RX_Data\...`

**方式一：显式指定采集文件（正式复验时推荐）**

将 `<new_capture_stem>` 替换成本次新采集的文件主名，例如 `20260328_192645_rawiq_sc16_zeroif_prn1_spread_sr4092000_cf100000000_dur30p0s`：

```matlab
CAPTURE_PATH = ['C:\VMwareVirtualMachines\GongXiangDocument\GNSS_RX_Data\2026\' ...
    '2026_03_28\<new_capture_stem>\<new_capture_stem>'];
ber
```

**方式二：分析最新采集（快速预览时可用）**

```matlab
clear CAPTURE_PATH
ber
```

然后在提示 `直接分析最新文件请按回车` 时直接回车。

两种方式的取舍：

- 做正式复验记录时，优先用方式一（显式指定 `CAPTURE_PATH`）。
- 只是快速看刚刚那次采集结果时，可以用方式二。
- 如果目录里可能有其他流程新生成的文件，不要依赖方式二。

MATLAB 中需要重点确认的输出：

- `本次分析文件：...` 是否已经切换到新采集
- `TX truth：JSON 模式`
- `=== Step 4: tracked BER 主链 ===`
- `tracked BER：...`
- `BER 统计结果`

若 RX 命令行出现类似以下提示：

```text
usrp_source :error: In the last 19249 ms, 1 overflows occurred.
```

则本轮采集默认应视为“可疑样本”，不要拿来做正式 BER 验收。经验上，这通常意味着主机侧未能持续接住 USRP 样本流，采集中间发生了丢样或时间连续性破坏；MATLAB 端常见表现是：

- 某个时间点之后 BER 突然整体抬升
- `Tracking 状态` 图中频率估计或相位误差在对应时刻出现尖峰
- `reacq_events` 明显增多
- 前半段正常、后半段突然失稳

处理原则：

- Step 4 的验收样本默认要求 `RX 无 overflow`。
- 若出现 overflow，优先重采，不建议把该次结果直接归因到 TX 比特错误或 tracking 参数错误。

优先缓解手段：

- 优先把采集输出写到 VM 本地磁盘，再在采集后复制到共享目录；不要长期直接写 `/mnt/hgfs/...` 做正式 BER 验收。
- 采集时尽量减少宿主机与 VM 的额外磁盘负载、界面操作和后台任务。
- 若 overflow 频繁复现，可优先试 `chunked` 长采，或在排障阶段暂时降低采样率验证是否是主机吞吐瓶颈。

算法侧的现实边界：

- tracking 可以增强“异常检测、局部重同步、坏窗口隔离”的能力。
- 但如果 overflow 已经导致原始 IQ 样本丢失，算法无法真正恢复被硬件/主机链路丢掉的数据，只能尽量避免让后续 BER 统计被整段污染。

完成标志：

- [ ] 新的 `30 s` 采集成功生成
- [ ] TX 无持续 underflow
- [ ] RX 无 overflow
- [ ] 新采集在 MATLAB 上也能达到低 BER
- [ ] 连续 3 份新 `30 s` 采集都稳定

### Step 5：扩展到 250 s

先在 TX 端启动：

```bash
cd /home/shen/projects/gnss_tx
env PYTHONPATH=src python3 scripts/run_tx.py \
    --config configs/tx_b210_cable_loopback.yaml \
    --tx-gain 40 \
    --amplitude 1.0 \
    --duration 300
```

然后在 RX 端采集：

```bash
cd /home/shen/projects/GNSS_RX
env PYTHONPATH=src python3 scripts/record_rx.py \
    --config configs/rx_cable_loopback.yaml \
    --duration 250 \
    --capture-mode single
```

完成标志：

- [ ] 恢复总比特数 `>= 10^4`
- [ ] 总 BER 保持低误码
- [ ] 无长时间失锁区间
- [ ] 记录实际使用的 `tx_gain`

### Step 6：准备并执行 1 h

先做 RX 侧 `dry-run`，不急着直接开采：

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

若 `dry-run` 正常，再做正式联机实验。建议开始前重新执行一次 Step 1 导出 truth JSON。

推荐优先方案：

- RX 使用 `chunked`
- TX 保持当前稳定配置不变

---

## 五、今天真正执行时的最短路径

如果今天的目标只是回答“链路到底有没有收敛”，建议只跑到这里：

1. Step 1：导出 truth JSON
2. Step 2：同步 MATLAB
3. Step 3：固定 `30 s` 样本跑 `tracked_truth`
4. 若收敛，再做 Step 4：新的联机 `30 s` 复验

也就是说，今天不必一上来就开真机做新的采集。

---

## 六、当前验收标准

### 6.1 固定 30 s 样本

- [ ] `tracked_truth` BER `< 1e-3`
- [ ] `ambiguity_flag = false`
- [ ] 100-bit 滑窗 BER 不再周期性在 `0% ~ 100%` 间摆动
- [ ] 码相位、频偏、相位误差曲线平稳

### 6.2 新 30 s 联机复验

- [ ] 连续 `3` 次新采集 BER `< 1e-3`
- [ ] 异常时能从 tracking 图解释，而不是只看到高 BER 数字

### 6.3 250 s 与 1 h

- [ ] `250 s` 总 BER 保持低误码
- [ ] `1 h` 采集计划可正常生成
- [ ] 长时实验优先走 `chunked`

---

## 七、若 30 s 仍不收敛

不要先改 TX pattern，也不要先盲目调增益，优先按这个顺序排查：

1. 宿主机 MATLAB 是否还在跑旧文件
2. `tracked_truth` 是否首次暴露接口或脚本问题
3. tracking 曲线里的 FLL/PLL/码相位是否稳定
4. truth JSON 字段是否和 dry-run 摘要一致

更细的排障动作见：

- `/home/shen/projects/GNSS_RX/experiments/plans/2026-03-28/ber_loopback_rx/2026-03-28_ber_loopback_debug_playbook.md`
