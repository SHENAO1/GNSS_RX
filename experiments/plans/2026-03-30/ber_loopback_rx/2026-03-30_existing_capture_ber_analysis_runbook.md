# 已有采集数据 BER 分析手册

> 创建时间：2026-03-30
> 目的：对已经采集完成的 `.sc16 + .json` 数据直接做闭环 BER 分析，而不是重新组织采集流程
> 入口脚本：`/home/shenao/projects/GNSS_RX/matlab/scripts/run_ber_loopback.m`
> 关联计划：`/home/shenao/projects/GNSS_RX/experiments/plans/2026-03-28/ber_loopback_rx/2026-03-28_ber_loopback_rx_plan.md`
> 参考联合手册：`/home/shenao/projects/gnss_tx/experiments/plans/2026-03-28/ber_loopback_tx/2026-03-28_ber_loopback_joint_runbook.md`
> 关联专题：`/home/shenao/projects/GNSS_RX/experiments/special/rx_ber_judgement_logic/README.md`

---

## 一、适用场景

这份手册只处理一件事：

**你已经有了一组采集数据，现在要分析它的误码率（BER）。**

当前默认入口不是 `record_rx.py`，而是 MATLAB 的 `run_ber_loopback.m`。该脚本会对已有采集数据依次完成：

1. 加载 IQ 数据
2. 前 `100 ms` 捕获
3. 加载 `tx_truth.json`
4. 计算 `open_loop_truth` 诊断基线
5. 计算 `tracked_truth` 主链 BER
6. 输出 BER、匹配率、对齐偏移和跟踪诊断图

一句话总结：

```text
先固定样本，再离线分析；先拿 BER 结论，再决定是否需要重采。
```

---

## 二、当前有效样本判定

参考联合 runbook 当前已经验证过的结论：

- 当 `TX 无 underflow` 且 `RX 无 overflow` 时，`tracked_truth` 已在 `30 s` 样本上收敛到 `BER = 0.00e+00`（`0 / 1499 bit`）
- 因此当前正式 BER 验收的首要闸门，不是 truth 契约本身，而是采集连续性有没有被破坏

当前推荐口径：

- 如果这份数据对应的采集过程存在 `overflow` 或 `underflow`，可以分析，但默认不计入正式 BER 验收样本
- 只有在 `TX 无 underflow` 且 `RX 无 overflow` 的前提下，`BER` 才作为有效收敛结论

---

## 三、建议先冻结分析基线

如果你当前是在复盘已有数据，第一步不是换样本，而是先冻结本轮要分析的那一份。

联合 runbook 中已经使用过的固定 `30 s` 回归样本是：

```text
C:\VMwareVirtualMachines\GongXiangDocument\GNSS_RX_Data\2026\2026_03_28\20260328_142122_rawiq_sc16_zeroif_prn1_spread_sr4092000_cf100000000_dur30p0s
```

如果你要复现历史基线，建议：

1. 本轮先固定只分析这一份样本
2. 中途不要切到“最新采集文件”
3. 在 MATLAB 中显式设置 `CAPTURE_PATH`

这样可以避免脚本自动选到另一份更新数据，导致“代码变了”和“样本也变了”混在一起。

---

## 四、最小输入

至少需要以下两类输入：

- 一组采集文件：同名 `.sc16` 与 `.json`
- 一份参考真值：优先推荐与采集 stem 绑定的 sidecar truth

truth JSON 不是采集文件，也不是 BER 结果文件。它是 TX 在发射前导出的“比特真值契约”，主要告诉 RX：

- 当前实际使用的导航 bit pattern
- 发射起点对应的 `initial_nav_epoch` / `initial_nav_bit_index`
- 当前采样参数，如 `sample_rate`、`epochs_per_bit`
- 当前 PRN 编号

若当前日志显示 `TX truth：JSON 模式`，说明脚本正在用正式 truth 契约做 BER 对比。
若回退到 fallback 模式，则当前 BER 更适合做链路自检，不适合作为正式闭环误码率结论。

推荐目录组织：

```text
<capture_dir>/
  20260328_142122_rawiq_sc16_zeroif_prn1_spread_sr4092000_cf100000000_dur30p0s.sc16
  20260328_142122_rawiq_sc16_zeroif_prn1_spread_sr4092000_cf100000000_dur30p0s.json
  20260328_142122_rawiq_sc16_zeroif_prn1_spread_sr4092000_cf100000000_dur30p0s_tx_truth.json
```

说明：

- `CAPTURE_PATH` 可以传 stem 路径，也可以直接传 `.json` 或 `.sc16`
- 若不显式给 `TX_TRUTH_PATH`，脚本当前会按以下顺序自动尝试寻找：
  - `<capture_stem>_tx_truth.json`
  - `<capture_stem>.truth.json`
  - `tx_truth.json`
  - `ber_truth.json`
  - MATLAB 工作区根目录下的 `tx_truth.json`
- 正式 BER 当前优先推荐使用 sidecar truth；根目录 `tx_truth.json` 只作为兼容旧流程的 fallback

### 4.1 为什么现在优先推荐 sidecar truth

如果所有样本都共用 MATLAB 工作区根目录中的单份 `tx_truth.json`，很容易出现：

- 当前分析的是 `3 月 30 日` 的采集
- 根目录里的 truth 却是另一个时间点 later dry-run 导出的
- MATLAB 日志虽然显示 `JSON 模式`，但 truth 并不一定匹配当前采集轮次

因此从当前版本开始，更推荐让每份采集形成下面这组三件套：

```text
<capture_dir>/
  <capture_stem>.sc16
  <capture_stem>.json
  <capture_stem>_tx_truth.json
```

这样复制到主力机后，只要设置 `CAPTURE_PATH`，`ber` 就会先匹配同目录、同 stem 的 truth 文件。

---

## 五、先看这个判断表

### 5.1 不需要开真实 USRP 的步骤

- 固定旧的 `30 s` IQ 样本做离线分析
- TX `--dry-run` 导出 truth JSON
- 同步 MATLAB 脚本到宿主机共享目录
- 在宿主机 MATLAB 上跑 `tracked_truth`

### 5.2 什么时候才需要重采

- 采集日志已知存在 `overflow` 或 `underflow`
- 图上明显出现中途连续性破坏
- 当前样本连捕获都失败

如果只是“还没分析 BER”，那下一步不是重采，而是先跑 `run_ber_loopback.m`。

---

## 六、推荐执行方式

### 方式 A：显式指定采集文件和 truth JSON

在 MATLAB 中执行：

```matlab
cd('/home/shenao/projects/GNSS_RX/matlab')
addpath(fullfile(pwd, 'functions'));
addpath(fullfile(pwd, 'scripts'));
clear functions
rehash

CAPTURE_PATH = '/path/to/your/capture_stem_or_json_or_sc16';
TX_TRUTH_PATH = '/path/to/your/tx_truth.json';
BER_MODE = 'tracked_truth';

run('scripts/run_ber_loopback.m')
```

这是当前最推荐的方式，因为输入明确，不依赖自动发现。

如果你在 VMware 宿主机 MATLAB 上工作，更推荐直接写成固定回归样本的绝对路径，例如：

```matlab
cd('C:\VMwareVirtualMachines\GongXiangDocument\GNSS_RX_matlab')
addpath(fullfile(pwd, 'functions'));
addpath(fullfile(pwd, 'scripts'));
clear functions
rehash

CAPTURE_PATH = ['C:\VMwareVirtualMachines\GongXiangDocument\GNSS_RX_Data\2026\' ...
    '2026_03_28\20260328_142122_rawiq_sc16_zeroif_prn1_spread_sr4092000_' ...
    'cf100000000_dur30p0s\20260328_142122_rawiq_sc16_zeroif_prn1_spread_' ...
    'sr4092000_cf100000000_dur30p0s'];
TX_TRUTH_PATH = 'C:\VMwareVirtualMachines\GongXiangDocument\GNSS_RX_matlab\tx_truth.json';
BER_MODE = 'tracked_truth';

run('scripts/run_ber_loopback.m')
```

这样能避免脚本误选到“当前目录下最新的一组采集”。

### 方式 B：只指定采集文件，让脚本自动找 truth

```matlab
cd('/home/shenao/projects/GNSS_RX/matlab')
addpath(fullfile(pwd, 'functions'));
addpath(fullfile(pwd, 'scripts'));
clear functions
rehash

CAPTURE_PATH = '/path/to/your/capture_stem_or_json_or_sc16';
BER_MODE = 'tracked_truth';

run('scripts/run_ber_loopback.m')
```

前提是 sidecar truth 已放在采集目录里，或者命名满足脚本的自动发现规则。

### 方式 C：只想先看 open-loop 基线

```matlab
CAPTURE_PATH = '/path/to/your/capture_stem_or_json_or_sc16';
TX_TRUTH_PATH = '/path/to/your/tx_truth.json';
BER_MODE = 'open_loop_truth';
run('scripts/run_ber_loopback.m')
```

用途：

- 验证 truth 对齐是否明显错位
- 对比 `open_loop_truth` 与 `tracked_truth` 的结论是否一致

注意：当前默认最终结论仍应优先看 `tracked_truth`。

### 方式 D：先补齐 sidecar truth，再分析已有样本

如果你现在只有采集文件，但还没有和本轮 TX 参数一致的 truth JSON，建议优先补一份与采集 stem 绑定的 sidecar truth：

```bash
cd /home/shenao/projects/gnss_tx
env PYTHONPATH=src python3 scripts/run_tx.py \
    --config configs/tx_b210_cable_loopback.yaml \
    --tx-gain 40 \
    --amplitude 1.0 \
    --dry-run \
    --export-truth-json /path/to/<capture_dir>/<capture_stem>_tx_truth.json
```

这一步不需要真实 RX 同时运行。

如果你暂时只能维护一份全局 truth，也可以继续导出到：

```text
/mnt/hgfs/GongXiangDocument/GNSS_RX_matlab/tx_truth.json
```

但这条路径现在只建议作为兼容旧流程的 fallback，不建议继续作为正式 BER 的首选 truth 来源。

如果你是在宿主机 MATLAB 上分析，还应确认 `GNSS_RX_matlab/` 中的脚本已经同步到较新版本；至少要覆盖：

- `matlab/scripts/run_ber_loopback.m`
- `matlab/functions/load_gnss_rx_capture.m`
- `matlab/functions/run_prn_acquisition.m`
- `matlab/functions/recover_nav_bits.m`
- `matlab/functions/track_nav_bits.m`
- `matlab/functions/load_tx_truth_json.m`
- `matlab/functions/build_fallback_tx_truth.m`
- `matlab/functions/plot_ber_loopback.m`

---

## 七、你会看到什么输出

脚本正常运行后，核心输出分 4 组：

### 1. 捕获是否成功

典型输出：

```text
=== Step 2: GPS L1 C/A 捕获 ===
捕获成功！Doppler = ... Hz，码相位 = ... samples，次峰比 = ...
```

如果这里失败，脚本会直接终止，不会继续算 BER。

### 2. truth 是不是正确加载

典型输出：

```text
TX truth：JSON 模式，来源 = ...
```

如果看到 fallback 模式，说明当前 BER 只能作为“脚本链路是否自洽”的参考，不适合当严格闭环 BER 结论。

### 3. open-loop 与 tracked 两条结果

典型输出：

```text
open-loop 匹配率：...
tracked BER：...
```

其中：

- `open-loop` 更像诊断基线
- `tracked` 是当前默认主链

### 4. 最终 BER 汇总

典型输出块：

```text
========================================
  BER 统计结果
========================================
  模式：        tracked_truth
  truth 模式：  json
  总发送比特数：...
  误码个数：    ...
  BER：         ...
  bit 偏移：    ...
  pattern 偏移：...
  极性：        ...
  truth 匹配率：...
  捕获 Doppler：...
  次峰比：      ...
========================================
```

---

## 八、怎么解读结果

当前代码口径下，建议按这个顺序读结果：

1. 先看 `BER`
2. 再看 `truth 匹配率`
3. 再看 `ambiguity_flag`
4. 最后结合图看 `reacq_events`、局部 BER、频率尖峰和码相位漂移

几个关键判断：

- `BER` 很低且 `truth 匹配率` 很高：这组数据可作为有效 BER 样本
- `tracked_match` 很高但后半段 BER 突然变差：优先怀疑采集过程中有 overflow 或丢样
- `match_rate < 55%`：更像 truth mismatch 或 bit timing 歧义
- `ambiguity_flag = true`：最优对齐和次优对齐太接近，当前结论不够稳

特别注意：

- 当前 Step 6 的 BER 是对 `selected_result.rx_bits` 和 `selected_result.ref_bits` 做全量逐位比较
- `lock_quality` 和 `window_ber.valid` 目前主要用于诊断，不会自动把坏窗口从总 BER 中剔除

所以某一段采集如果中途坏掉，最终 BER 会直接被那一段拉高。

联合 runbook 已经明确过一个容易误判的点：

- `tracked_match` 可能主要反映前期训练窗的对齐质量
- 如果后半段才发生 overflow 或丢样，`tracked_match` 仍可能看起来很好

因此在可疑样本上，优先看：

- `selected_ber`
- `Tracked 误码位置`
- `局部 BER`
- `Tracking 状态`
- `reacq_events`

---

## 九、建议的实际分析顺序

针对一组已经采好的数据，建议按以下顺序执行：

1. 用显式 `CAPTURE_PATH + TX_TRUTH_PATH` 先跑一次 `BER_MODE = 'tracked_truth'`
2. 记录 `BER`、`match_rate`、`bit_offset_ms`、`pattern_offset`
3. 再跑一次 `BER_MODE = 'open_loop_truth'` 做对照
4. 对比两条链的结果是否同时指向同一结论
5. 若 BER 偏高，优先看图中的后半段失稳、频率尖峰和重同步事件
6. 只有在确认样本连续性被破坏时，才进入“重新采集”分支

不建议一上来就重采。只有在以下情况才把“重采”作为下一步：

- 捕获直接失败
- 采集日志已知存在 overflow 或 underflow
- 图上明显出现中途连续性破坏

---

## 十、结果保存

脚本最后会询问是否保存结果到 `.mat` 文件：

```text
是否保存结果到 .mat 文件？[y/N]：
```

如果输入 `y`，结果会保存到：

```text
/home/shenao/projects/GNSS_RX/matlab/results/ber_loopback_<timestamp>.mat
```

保存内容包含：

- `truth`
- `meta`
- `acq_result`
- `open_loop_result`
- `tracked_result`
- `selected_result`
- `analysis_result`
- `errors`
- `total_bits`
- `ber`

后续复盘时，优先读 `analysis_result`。

---

## 十一、当前推荐结论

如果你的目标是“分析这份数据的误码率”，当前默认动作应是：

1. 不改采集链
2. 不先写新的 capture runbook
3. 直接把这份数据喂给 `run_ber_loopback.m`
4. 先拿到 `tracked_truth` 的 BER 与诊断图
5. 再根据结果决定是否需要重采

这也是当前 `GNSS_RX` 代码状态下最贴近真实问题的执行路径。
