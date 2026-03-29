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

## 2026-03-29 收敛结论

本轮联机复验已确认：

- 当 `TX 无 underflow` 且 `RX 无 overflow` 时，`tracked_truth` 已在 `30 s` 样本上收敛到 `BER = 0.00e+00`（`0 / 1499 bit`）。
- 同一轮结果中 `tracked_match = 100%`，误码位置图为空，说明当前闭环链路本身已经可用。
- 因此当前主结论更新为：**`overflow/underflow` 是 BER 验收的首要闸门**，不是 TX truth 契约或 tracked BER 主链本身仍然不通。
- 正式验收口径：只有在 `TX 无 underflow` 且 `RX 无 overflow` 的前提下，本轮 BER 才计入有效样本。

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

### Step 1.5：TX truth JSON 是什么（代码口径）

`tx_truth.json` 不是采集文件，也不是 BER 结果文件。它是 TX 在发射前导出的“比特真值契约”，用于告诉 RX：

- TX 实际使用了哪组导航比特 pattern
- 发射起点对应的 `initial_code_phase` / `initial_nav_epoch` / `initial_nav_bit_index`
- 当前采样参数（`sample_rate`、`samples_per_chip`、`epochs_per_bit`）
- 当前 PRN（`prn_id`）

按当前代码，TX 导出的核心字段为：

- `nav_bits_pattern_pm1`：导航比特真值（+1/-1 表示），供相关器/判决直接使用。
- `nav_bits_pattern_01`：与上面等价的 0/1 版本，便于 BER 统计与可视化。
- `initial_code_phase`：发射起点的 C/A 码相位（单位：chip）。
- `initial_nav_epoch`：发射起点对应的导航 epoch（20 个 C/A epoch = 1 bit）。
- `initial_nav_bit_index`：发射起点在 nav pattern 中落到的比特索引。
- `samples_per_chip`：码片过采样倍数（每个 chip 的采样点数）。
- `sample_rate`：实际发射采样率（Hz）。
- `epochs_per_bit`：每个导航比特包含多少个 C/A epoch（GPS L1 C/A 固定为 20）。
- `prn_id`：当前 truth 对应的 PRN 编号。

RX 侧 MATLAB 会优先加载该 JSON，并在日志打印 `TX truth：JSON 模式`。若找不到或字段不完整，会回退到脚本内默认 pattern（fallback 模式）。

实践建议：

- 只要准备做正式 BER 复验，就先重新执行一次 Step 1，确保 JSON 与本轮 TX 参数一致。
- 若日志出现 fallback 模式，默认不能作为“正式收敛结论”，应先修复 truth 来源再评估 BER。

### Step 2：同步 MATLAB 脚本到宿主机共享目录

```bash
cd /home/shen/projects/GNSS_RX
rsync -av matlab/ /mnt/hgfs/GongXiangDocument/GNSS_RX_matlab/
```

建议重点确认这些文件已经是新版本：

- `matlab/scripts/run_ber_loopback.m`
- `matlab/scripts/run_capture_analysis.m`
- `matlab/functions/recover_nav_bits.m`
- `matlab/functions/track_nav_bits.m`
- `matlab/functions/run_prn_acquisition.m`
- `matlab/functions/run_multi_prn_survey.m`
- `matlab/functions/load_gnss_rx_capture.m`
- `matlab/functions/gnss_rx_resolve_accel_options.m`
- `matlab/functions/plot_ber_loopback.m`
- `matlab/functions/load_tx_truth_json.m`
- `matlab/functions/build_fallback_tx_truth.m`

如果只是本轮 BER / GPU 加速逻辑有更新，而不想整目录同步，也可用“最小同步清单”：

```bash
cd /home/shen/projects/GNSS_RX
cp -v matlab/functions/gnss_rx_resolve_accel_options.m /mnt/hgfs/GongXiangDocument/GNSS_RX_matlab/functions/
cp -v matlab/functions/load_gnss_rx_capture.m /mnt/hgfs/GongXiangDocument/GNSS_RX_matlab/functions/
cp -v matlab/functions/recover_nav_bits.m /mnt/hgfs/GongXiangDocument/GNSS_RX_matlab/functions/
cp -v matlab/functions/run_prn_acquisition.m /mnt/hgfs/GongXiangDocument/GNSS_RX_matlab/functions/
cp -v matlab/functions/run_multi_prn_survey.m /mnt/hgfs/GongXiangDocument/GNSS_RX_matlab/functions/
cp -v matlab/functions/track_nav_bits.m /mnt/hgfs/GongXiangDocument/GNSS_RX_matlab/functions/
cp -v matlab/scripts/run_ber_loopback.m /mnt/hgfs/GongXiangDocument/GNSS_RX_matlab/scripts/
cp -v matlab/scripts/run_capture_analysis.m /mnt/hgfs/GongXiangDocument/GNSS_RX_matlab/scripts/
cp -v matlab/README.md /mnt/hgfs/GongXiangDocument/GNSS_RX_matlab/
```

适用场景：

- 只更新了少量 MATLAB 文件，希望减少共享目录同步时间
- 只想确保 BER 主链与 GPU 加速相关文件已经覆盖到宿主机
- 当前共享目录中还有其他手工文件，不希望被整目录镜像影响

若采用“最小同步清单”，完成后仍建议在 MATLAB 中执行：

```matlab
which run_ber_loopback -all
which run_prn_acquisition -all
which recover_nav_bits -all
which gnss_rx_resolve_accel_options -all
```

确认宿主机 MATLAB 确实已经加载到共享目录中的新文件。

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

反向结论（2026-03-29 已验证）：

- 若本轮同时满足 `TX 无 underflow` 与 `RX 无 overflow`，当前 `tracked_truth` 主链已验证可收敛到 `BER=0`。
- 因此在“无 overflow/underflow 但 BER 仍高”的场景之外，不应再优先怀疑 truth JSON、pattern 偏移或 tracked BER 主链整体失效。

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

### Step 4.5：扩展到 100 s

`100 s` 作为 30 s → 250 s 的过渡验证，用于在短时间内确认"本地落盘 + 采后复制"流程正常、无 overflow，再进入更长时间的 250 s。

先在 TX 端启动（TX 发 120 s，保证覆盖 RX 的 100 s 采集）：

```bash
cd /home/shen/projects/gnss_tx
sudo chrt -f 50 env PYTHONPATH=src python3 scripts/run_tx.py \
    --config configs/tx_b210_cable_loopback.yaml \
    --tx-gain 40 \
    --amplitude 1.0 \
    --duration 120
```

然后在 RX 端采集：

```bash
cd /home/shen/projects/GNSS_RX

CAPTURE_NAME=20260329_ber100s_localdisk_rawiq_sc16_zeroif_prn1_spread_sr4092000_cf100000000_dur100p0s
LOCAL_STEM=/home/shen/GNSS_RX_Data_local/2026/2026_03_29/$CAPTURE_NAME/$CAPTURE_NAME
SHARE_DIR=/mnt/hgfs/GongXiangDocument/GNSS_RX_Data/2026/2026_03_29/$CAPTURE_NAME

mkdir -p "$(dirname "$LOCAL_STEM")"
printf 'LOCAL_STEM=<%s>\n' "$LOCAL_STEM"
printf 'SHARE_DIR=<%s>\n' "$SHARE_DIR"

sudo chrt -f 50 env PYTHONPATH=src python3 scripts/record_rx.py \
    --config configs/rx_cable_loopback.yaml \
    --duration 100 \
    --capture-mode single \
    --output-stem "$LOCAL_STEM"
```

采集结束后复制到共享目录：

```bash
mkdir -p "$SHARE_DIR"
cp -v "$(dirname "$LOCAL_STEM")"/*.json "$SHARE_DIR"/
cp -v "$(dirname "$LOCAL_STEM")"/*.sc16 "$SHARE_DIR"/
ls -lh "$SHARE_DIR"
```

判定标准：

- `100 s @ 4.092 Msps` 时，`.sc16` 文件量级约为 `1.5 ~ 1.7 GB`
- 若变量丢失，见"变量丢失时的恢复步骤"

在宿主机 MATLAB 中分析（参考 Step 5 的 Step 5A~5D，`CAPTURE_PATH` 改为 100 s 对应路径）：

```matlab
TX_TRUTH_PATH = 'C:\VMwareVirtualMachines\GongXiangDocument\GNSS_RX_matlab\tx_truth.json';
CAPTURE_PATH = ['C:\VMwareVirtualMachines\GongXiangDocument\GNSS_RX_Data\2026\' ...
    '2026_03_29\20260329_ber100s_localdisk_rawiq_sc16_zeroif_prn1_spread_' ...
    'sr4092000_cf100000000_dur100p0s\20260329_ber100s_localdisk_rawiq_' ...
    'sc16_zeroif_prn1_spread_sr4092000_cf100000000_dur100p0s'];
ber
```

完成标志：

- [ ] 100 s 采集成功写入本地磁盘
- [ ] TX 无持续 underflow，RX 无 overflow
- [ ] 文件成功复制到共享目录，`.sc16` 约 1.5~1.7 GB
- [ ] MATLAB 分析通过，BER 低误码，无明显失锁段

---

### Step 5：扩展到 250 s

`250 s` 已经进入正式 BER 验收区间，当前默认**不要长期直接写 `/mnt/hgfs/...`**。推荐流程改为：

1. RX 先写 VM 本地磁盘，降低共享目录写盘抖动导致的 overflow 风险。
2. 采集结束后，再把整份采集目录复制到共享目录。
3. 宿主机 MATLAB 分析共享目录中的副本，而不是直接读取 VM 本地路径。

建议先准备一个固定的本地采集 stem，避免 `dry-run`、正式采集和采后复制各自生成不同文件名。

先在 RX 端准备本地目录变量：

```bash
CAPTURE_NAME=20260328_ber250s_localdisk_rawiq_sc16_zeroif_prn1_spread_sr4092000_cf100000000_dur250p0s
LOCAL_STEM=/home/shen/GNSS_RX_Data_local/2026/2026_03_28/$CAPTURE_NAME/$CAPTURE_NAME
SHARE_DIR=/mnt/hgfs/GongXiangDocument/GNSS_RX_Data/2026/2026_03_28/$CAPTURE_NAME

mkdir -p "$(dirname "$LOCAL_STEM")"
```

注意：

- 以上 `CAPTURE_NAME` / `LOCAL_STEM` / `SHARE_DIR` 必须在**同一个 shell 会话**里定义后再执行后续采集命令。
- 如果你新开了一个终端 tab，或者只复制了 `record_rx.py` 那段命令而没有先执行变量定义块，`"$LOCAL_STEM"` 会展开为空字符串。
- 同理，如果只重新定义了 `LOCAL_STEM` 但没有同时定义 `SHARE_DIR`，采后复制阶段的目标目录也会变成空字符串。
- 可在正式采集前先执行一次 `printf 'LOCAL_STEM=<%s>\n' "$LOCAL_STEM"`；若输出为 `LOCAL_STEM=<>`，说明变量尚未生效，需要先重新执行上面的定义块。
- 采后复制前建议同时检查 `printf 'SHARE_DIR=<%s>\n' "$SHARE_DIR"`；若输出为 `SHARE_DIR=<>`，不要执行 `mkdir -p "$SHARE_DIR"` 或 `rsync/cp`，应先重新执行变量定义块。
- 若不想依赖 shell 变量，也可以直接把 `--output-stem` 写成完整绝对路径。

这类错误的典型表现是：

```text
ValueError: output_stem 在提供时不能为空。
```

它通常不是 `record_rx.py` 内部采集逻辑出错，而是 shell 在执行命令时已经把 `"$LOCAL_STEM"` 展开成了空字符串，等价于：

```bash
--output-stem ""
```

推荐把“变量定义 + 自检 + 采集命令”连续放在同一个终端里执行：

```bash
CAPTURE_NAME=20260329_ber250s_localdisk_rawiq_sc16_zeroif_prn1_spread_sr4092000_cf100000000_dur250p0s
LOCAL_STEM=/home/shen/GNSS_RX_Data_local/2026/2026_03_29/$CAPTURE_NAME/$CAPTURE_NAME
SHARE_DIR=/mnt/hgfs/GongXiangDocument/GNSS_RX_Data/2026/2026_03_29/$CAPTURE_NAME

mkdir -p "$(dirname "$LOCAL_STEM")"
printf 'LOCAL_STEM=<%s>\n' "$LOCAL_STEM"

cd /home/shen/projects/GNSS_RX
env PYTHONPATH=src python3 scripts/record_rx.py \
    --config configs/rx_cable_loopback.yaml \
    --duration 250 \
    --capture-mode single \
    --output-stem "$LOCAL_STEM"
```

如果 `printf` 输出仍然是空值，先不要继续采集；应先重新执行变量定义块，或者直接改用下方“绝对路径写死”的方式。

如果希望先确认路径无误，先在 RX 端做一次 `dry-run`：

```bash
cd /home/shen/projects/GNSS_RX
env PYTHONPATH=src python3 scripts/record_rx.py \
    --config configs/rx_cable_loopback.yaml \
    --duration 250 \
    --capture-mode single \
    --output-stem "$LOCAL_STEM" \
    --dry-run
```

若要在 `dry-run` 阶段顺手确认变量是否已经正确展开，可先执行：

```bash
printf 'LOCAL_STEM=<%s>\n' "$LOCAL_STEM"
printf 'SHARE_DIR=<%s>\n' "$SHARE_DIR"
```

只有在两个输出都不是空字符串时，再继续执行后续采集命令。

若希望完全绕开 shell 变量展开问题，可直接使用绝对路径版本：

```bash
cd /home/shen/projects/GNSS_RX
env PYTHONPATH=src python3 scripts/record_rx.py \
    --config configs/rx_cable_loopback.yaml \
    --duration 250 \
    --capture-mode single \
    --output-stem /home/shen/GNSS_RX_Data_local/2026/2026_03_29/20260329_ber250s_localdisk_rawiq_sc16_zeroif_prn1_spread_sr4092000_cf100000000_dur250p0s/20260329_ber250s_localdisk_rawiq_sc16_zeroif_prn1_spread_sr4092000_cf100000000_dur250p0s
```

这种写法更长，但不会受到当前 shell 变量状态的影响，适合正式验收时减少操作失误。

#### 关于进程优先级（250 s 及以上必读）

B200 是 USB 设备，UHD 传输层的缓冲参数（`num_send_frames`、`num_recv_frames`、`recv_buff_size`）影响的是 USB DMA 内存分配，不是网络 socket 缓冲——**不能像 Ethernet USRP（X300/N200）那样随意调大**，过大的值会触发 `LIBUSB_ERROR_NO_MEM` 崩溃。

因此对于 250 s 及以上长时测试，抑制 underflow/overflow 的推荐手段是**提升进程 CPU 调度优先级**，而不是调整缓冲区大小：

```bash
# 推荐：SCHED_FIFO 实时调度（priority 50），在 guest 内核层面几乎不被抢占
# nice -n -15 只调整权重，hypervisor 仍可抢占整个 VM，效果有限
# chrt 语法：sudo chrt -f <priority> <命令>，env 写在 chrt 后面传入 PYTHONPATH
sudo chrt -f 50 env PYTHONPATH=src python3 <脚本> <参数>
```

两端都应使用 `sudo chrt -f 50`：TX 端保证 GNU Radio 调度线程能及时喂样到 USRP；RX 端保证 `Sc16CaptureSink` 写盘线程不被抢占。

先在 TX 端启动：

```bash
cd /home/shen/projects/gnss_tx
sudo chrt -f 50 env PYTHONPATH=src python3 scripts/run_tx.py \
    --config configs/tx_b210_cable_loopback.yaml \
    --tx-gain 40 \
    --amplitude 1.0 \
    --duration 300
```

然后在 RX 端采集：

```bash
cd /home/shen/projects/GNSS_RX

# 1. 定义本次采集路径变量（日期改为当天）
CAPTURE_NAME=20260329_ber250s_localdisk_rawiq_sc16_zeroif_prn1_spread_sr4092000_cf100000000_dur250p0s
LOCAL_STEM=/home/shen/GNSS_RX_Data_local/2026/2026_03_29/$CAPTURE_NAME/$CAPTURE_NAME
SHARE_DIR=/mnt/hgfs/GongXiangDocument/GNSS_RX_Data/2026/2026_03_29/$CAPTURE_NAME

# 2. 创建本地目录并确认变量已正确展开（输出为空则停止，重新执行上面的定义块）
mkdir -p "$(dirname "$LOCAL_STEM")"
printf 'LOCAL_STEM=<%s>\n' "$LOCAL_STEM"

# 3. 正式采集
sudo chrt -f 50 env PYTHONPATH=src python3 scripts/record_rx.py \
    --config configs/rx_cable_loopback.yaml \
    --duration 250 \
    --capture-mode single \
    --output-stem "$LOCAL_STEM"
```

采集结束后，再复制到共享目录。当前实测更推荐直接 `cp`，因为 `/mnt/hgfs/...` 上使用 `rsync` 时，可能因临时文件名过长而失败：

```text
rsync: [receiver] mkstemp ".../.<very_long_filename>.<suffix>" failed: File name too long (36)
```

因此，正式验收时推荐优先使用：

```bash
mkdir -p "$SHARE_DIR"
cp -v "$(dirname "$LOCAL_STEM")"/*.json "$SHARE_DIR"/
cp -v "$(dirname "$LOCAL_STEM")"/*.sc16 "$SHARE_DIR"/
```

复制完成后，建议立刻确认共享目录内已经真的出现两份文件：

```bash
ls -lh "$SHARE_DIR"
```

判定标准：

- 目录内至少应看到同名的 `.json` 与 `.sc16`
- `250 s @ 4.092 Msps` 时，`.sc16` 文件量级应约为 `3.9 ~ 4.1 GB`

如果仍希望使用 `rsync`，建议至少加上以下参数，减少 `/mnt/hgfs/...` 上的兼容性问题：

```bash
mkdir -p "$SHARE_DIR"
rsync -av --inplace --no-owner --no-group --no-perms \
    "$(dirname "$LOCAL_STEM")"/ "$SHARE_DIR"/
```

但当前 runbook 默认推荐仍然是 `cp`，因为它在本轮实测中比默认 `rsync` 更稳。

另一个常见错误是 `SHARE_DIR` 为空时直接执行：

```bash
mkdir -p "$SHARE_DIR"
rsync ...
```

这时可能出现：

```text
mkdir: 无法创建目录 "": 没有那个文件或目录
```

或让 `rsync` 误把目标解析成根目录 `/`。因此，复制前的变量自检不要省略。

#### 变量丢失时的恢复步骤

若已经看到以下任意一种报错：

```text
mkdir: 无法创建目录 "": 没有那个文件或目录
cp: 对 './*.json' 调用 stat 失败: 没有那个文件或目录
cp: 对 './*.sc16' 调用 stat 失败: 没有那个文件或目录
ls: 无法访问 '': 没有那个文件或目录
```

说明此时 `$LOCAL_STEM` 或 `$SHARE_DIR` 已经为空。采集文件本身**没有丢失**，只是 shell 变量丢了。恢复步骤如下：

**第一步：确认本地采集文件实际存在**

```bash
ls /home/shen/GNSS_RX_Data_local/2026/
```

找到对应日期目录，再往下看：

```bash
ls /home/shen/GNSS_RX_Data_local/2026/2026_03_29/
```

确认采集目录名（即 `CAPTURE_NAME`）。

**第二步：重新定义三个变量**

把 `CAPTURE_NAME` 替换为上一步实际看到的目录名（直接赋值，**不要加尖括号**，`<...>` 在 bash 里是重定向符会导致报错）：

```bash
# 示例（替换为实际目录名）：
CAPTURE_NAME=20260329_ber250s_localdisk_rawiq_sc16_zeroif_prn1_spread_sr4092000_cf100000000_dur250p0s
LOCAL_STEM=/home/shen/GNSS_RX_Data_local/2026/2026_03_29/$CAPTURE_NAME/$CAPTURE_NAME
SHARE_DIR=/mnt/hgfs/GongXiangDocument/GNSS_RX_Data/2026/2026_03_29/$CAPTURE_NAME
```

**第三步：自检变量不为空**

```bash
printf 'LOCAL_STEM=<%s>\n' "$LOCAL_STEM"
printf 'SHARE_DIR=<%s>\n' "$SHARE_DIR"
```

两行输出都不是 `<>` 才能继续。

**第四步：确认本地文件确实存在**

```bash
ls -lh "$(dirname "$LOCAL_STEM")"
```

应看到 `.json` 和 `.sc16` 两个文件。

**第五步：重新执行复制**

```bash
mkdir -p "$SHARE_DIR"
cp -v "$(dirname "$LOCAL_STEM")"/*.json "$SHARE_DIR"/
cp -v "$(dirname "$LOCAL_STEM")"/*.sc16 "$SHARE_DIR"/
ls -lh "$SHARE_DIR"
```

注意：采集文件不会因为复制命令出错而被删除，重新执行上面步骤即可。

之后在宿主机 MATLAB 中分析共享目录副本。建议按下面顺序执行，避免路径、旧函数缓存和 GPU 兼容问题混在一起。

**Step 5A：初始化 MATLAB 工作目录**

```matlab
cd('C:\VMwareVirtualMachines\GongXiangDocument\GNSS_RX_matlab')
clear functions
rehash
```

**Step 5B：若准备启用 GPU，加上兼容模式初始化**

对于较新的 NVIDIA GPU，当前 MATLAB 可能需要先开启 CUDA forward compatibility，才能正常 `gpuDevice`：

```matlab
parallel.gpu.enableCUDAForwardCompatibility(true);
gpuDevice
```

若要先做最小 GPU 烟雾测试，可执行：

```matlab
parallel.gpu.enableCUDAForwardCompatibility(true);
g = gpuDevice;

A = rand(1000, 'single');
B = gpuArray(A);
C = B .* 2;
gather(C(1:5,1:5))
```

说明：

- 该设置默认只对**当前 MATLAB 会话**生效，重启 MATLAB 后需重新执行。
- 若希望每次启动自动开启，可写入 `startup.m`：

```matlab
parallel.gpu.enableCUDAForwardCompatibility(true);
```

- 若希望通过环境变量方式持久化，也可先设置：

```matlab
setenv("MW_CUDA_FORWARD_COMPATIBILITY","1")
```

然后重启 MATLAB。

**Step 5C：确认 MATLAB 已加载到共享目录中的新脚本**

```matlab
which ber -all
which run_ber_loopback -all
which run_prn_acquisition -all
which recover_nav_bits -all
which gnss_rx_resolve_accel_options -all
```

期望结果：

- `ber.m` 指向 `GNSS_RX_matlab` 根目录
- `run_ber_loopback.m` 指向 `GNSS_RX_matlab\scripts`
- `run_prn_acquisition.m`、`recover_nav_bits.m`、`gnss_rx_resolve_accel_options.m` 指向 `GNSS_RX_matlab\functions`

**Step 5D：正式运行 GPU 加速版 BER 分析**

先显式设置加速配置、truth JSON 路径和采集文件路径，再执行 `ber`。

基础写法如下：

```matlab
ACCEL_OPTIONS = struct( ...
    'backend', 'gpu', ...
    'precision', 'single', ...
    'batch_ms', 2000, ...
    'use_parfor', false, ...
    'device_index', []);

TX_TRUTH_PATH = 'C:\VMwareVirtualMachines\GongXiangDocument\GNSS_RX_matlab\tx_truth.json';
```

然后显式指定这次 `250 s` 的共享目录采集路径，再执行 `ber`：

```matlab
CAPTURE_PATH = ['C:\VMwareVirtualMachines\GongXiangDocument\GNSS_RX_Data\2026\' ...
    '2026_03_28\20260328_ber250s_localdisk_rawiq_sc16_zeroif_prn1_spread_' ...
    'sr4092000_cf100000000_dur250p0s\20260328_ber250s_localdisk_rawiq_' ...
    'sc16_zeroif_prn1_spread_sr4092000_cf100000000_dur250p0s'];
ber
```

若实验日期已切换到新一天，应同步更新 `CAPTURE_PATH` 中的日期目录与文件名。例如 `2026-03-29` 可写为：

```matlab
ACCEL_OPTIONS = struct( ...
    'backend', 'gpu', ...
    'precision', 'single', ...
    'batch_ms', 2000, ...
    'use_parfor', false, ...
    'device_index', []);
TX_TRUTH_PATH = 'C:\VMwareVirtualMachines\GongXiangDocument\GNSS_RX_matlab\tx_truth.json';
CAPTURE_PATH = ['C:\VMwareVirtualMachines\GongXiangDocument\GNSS_RX_Data\2026\' ...
    '2026_03_29\20260329_ber250s_localdisk_rawiq_sc16_zeroif_prn1_spread_' ...
    'sr4092000_cf100000000_dur250p0s\20260329_ber250s_localdisk_rawiq_' ...
    'sc16_zeroif_prn1_spread_sr4092000_cf100000000_dur250p0s'];
ber
```

若 GPU 路径初始化失败，但仍想先把本轮结果跑出来，推荐改为自动回退模式：

```matlab
ACCEL_OPTIONS = struct('backend', 'auto', 'precision', 'single');
TX_TRUTH_PATH = 'C:\VMwareVirtualMachines\GongXiangDocument\GNSS_RX_matlab\tx_truth.json';
CAPTURE_PATH = ['C:\VMwareVirtualMachines\GongXiangDocument\GNSS_RX_Data\2026\' ...
    '2026_03_29\20260329_ber250s_localdisk_rawiq_sc16_zeroif_prn1_spread_' ...
    'sr4092000_cf100000000_dur250p0s\20260329_ber250s_localdisk_rawiq_' ...
    'sc16_zeroif_prn1_spread_sr4092000_cf100000000_dur250p0s'];
ber
```

若只想强制走 CPU，也可显式指定：

```matlab
ACCEL_OPTIONS = struct('backend', 'cpu', 'precision', 'double');
TX_TRUTH_PATH = 'C:\VMwareVirtualMachines\GongXiangDocument\GNSS_RX_matlab\tx_truth.json';
CAPTURE_PATH = ['C:\VMwareVirtualMachines\GongXiangDocument\GNSS_RX_Data\2026\' ...
    '2026_03_29\20260329_ber250s_localdisk_rawiq_sc16_zeroif_prn1_spread_' ...
    'sr4092000_cf100000000_dur250p0s\20260329_ber250s_localdisk_rawiq_' ...
    'sc16_zeroif_prn1_spread_sr4092000_cf100000000_dur250p0s'];
ber
```

**Step 5E：若 MATLAB 仍提示找不到入口函数**

先执行：

```matlab
cd('C:\VMwareVirtualMachines\GongXiangDocument\GNSS_RX_matlab')
clear functions
rehash
which ber -all
```

**Step 5F：若 GPU 仍不可用，记录这些诊断信息**

```matlab
version -release
gpuDeviceCount
parallel.gpu.enableCUDAForwardCompatibility
canUseGPU
```

这些输出可用于判断当前是 MATLAB 版本、驱动、还是工具箱兼容性问题。

运行后建议优先确认以下输出：

- `加速配置：requested=... resolved=...`
- 若启用了 GPU：`GPU 设备：[...] ...`
- `本次分析文件：...` 是否已经指向刚复制到共享目录的 `250 s` 文件
- `TX truth：JSON 模式`
- `Step 2 后端：...`
- `Step 3 后端：...`
- `Step 4 后端：cpu（tracking 主循环在 v1 保持 CPU）`
- `=== Step 4: tracked BER 主链 ===`
- `tracked BER`
- `BER 统计结果`
- `Step 2 用时 / Step 3 用时 / Step 4 用时`
- 是否出现明显的 `reacq_events`、后段 BER 抬升或 tracking 尖峰

操作提醒：

- `250 s @ 4.092 Msps` 的 `.sc16` 文件约为 `4.1 GB`，建议 VM 本地磁盘至少预留 `6~8 GB` 空间。
- `tx_truth.json` 体积很小，仍然可以继续放在共享目录，不需要为了它改成本地中转。
- 如果这套“本地落盘后再复制”的流程下仍然出现 overflow，再优先怀疑主机吞吐或 GNU Radio/USRP 链路本身，而不是先怀疑 `/mnt/hgfs/...`。

完成标志：

- [ ] 恢复总比特数 `>= 10^4`
- [ ] 总 BER 保持低误码
- [ ] 无长时间失锁区间
- [ ] 记录实际使用的 `tx_gain`
- [ ] 原始 IQ 先成功写入 VM 本地磁盘，再完整复制到共享目录

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

如果今天的目标只是回答”链路到底有没有收敛”，建议只跑到这里：

1. Step 1：导出 truth JSON
2. Step 2：同步 MATLAB
3. Step 3：固定 `30 s` 样本跑 `tracked_truth`
4. 若收敛，再做 Step 4：新的联机 `30 s` 复验

如果 30 s 已经稳定，想进一步验证长时行为，按以下顺序递进：

5. Step 4.5：联机 `100 s`（验证本地落盘 + 采后复制流程，约 1.5~1.7 GB）
6. Step 5：联机 `250 s`（正式 BER 验收，约 4.1 GB）
7. Step 6：联机 `1 h`（长时稳定性，优先走 `chunked`）

也就是说，今天不必一上来就开真机做新的采集；30 s 收敛后再按需递进到更长时长。

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
