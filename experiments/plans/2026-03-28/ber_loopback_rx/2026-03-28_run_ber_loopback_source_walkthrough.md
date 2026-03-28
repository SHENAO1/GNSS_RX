# `run_ber_loopback.m` 执行路径解读

> 创建时间：2026-03-28
> 作用：解释 `run_ber_loopback.m` 在执行时到底如何选择采集文件、truth JSON 和最终判决模式
> 对应脚本：`/home/shen/projects/GNSS_RX/matlab/scripts/run_ber_loopback.m`

---

## 一、最容易混淆的 4 个量

### 1. `CAPTURE_PATH`

这是“待分析的采集输入”。

它可以是以下任意一种：

- stem 路径
- `.json` 路径
- `.sc16` 路径

只要给了它，脚本就会围绕这组采集去读原始 IQ 和元数据。

### 2. `latest_capture`

这是脚本在 `CAPTURE_PATH` 没有被显式设置时，自动找到的“最新一组采集”的 stem 路径。

它不是分析模式，也不是 truth 文件。

### 3. `TX_TRUTH_PATH`

这是 TX 侧导出的 `tx_truth.json` 路径。

它只负责提供参考真值，用于和 RX 恢复出来的 bit 序列做对齐和 BER 比较。它不是 IQ 输入文件。

### 4. `BER_MODE`

这是“最终判决模式”。

当前支持的主值：

- `tracked_truth`
- `open_loop_truth`

默认值是 `tracked_truth`。

---

## 二、脚本启动时先做什么

脚本开头会保留以下外部变量：

```matlab
clearvars -except CAPTURE_PATH TX_TRUTH_PATH BER_MODE TRACKING_OPTIONS;
```

这意味着：如果你在运行前已经手动设置了 `CAPTURE_PATH`、`TX_TRUTH_PATH` 或 `BER_MODE`，脚本会直接沿用，不会覆盖掉。

因此，最稳的控制方式就是在 `run(...)` 之前先显式设置它们。

---

## 三、“检测到最新采集文件”到底是什么意思

当 `CAPTURE_PATH` 没有设置时，脚本会执行：

```matlab
latest_capture = find_latest_capture();
```

这一步的含义是：

1. 在默认数据根目录下递归搜索所有 `.json`
2. 过滤掉 `analysis/` 子目录
3. 只保留那些“同名 `.sc16` 也存在”的完整采集
4. 按 `.json` 修改时间选最新的一组
5. 返回该组采集的 stem 路径

所以屏幕上出现：

```text
检测到最新采集文件：
  ...\20260328_142122_...\20260328_142122_...
```

这里展示的不是某个分析结果文件，而是一组原始采集的 stem 路径。

---

## 四、为什么看起来像“目录名/同名文件”

GNSS_RX 当前的数据组织方式是：

```text
<capture_dir>/<capture_stem>.json
<capture_dir>/<capture_stem>.sc16
```

而且经常会把 `capture_dir` 本身命名成和 `capture_stem` 很接近甚至相同。

于是你会看到类似：

```text
...\20260328_142122_xxx\20260328_142122_xxx
```

这不是重复选择了两次文件，而是：

- 前半段是目录
- 后半段是不带扩展名的 stem

后续 loader 会自动补成：

- `...\20260328_142122_xxx.json`
- `...\20260328_142122_xxx.sc16`

---

## 五、按回车后实际分析的是什么

如果提示出现后你直接按回车，逻辑等价于：

```matlab
CAPTURE_PATH = latest_capture;
```

随后脚本会：

1. 用 `load_gnss_rx_capture(CAPTURE_PATH)` 读取该 stem 对应的 `.json + .sc16`
2. 用 `TX_TRUTH_PATH` 指向的 `tx_truth.json` 作为参考真值
3. 先跑 `open_loop_truth` 基线
4. 再跑 `tracked_truth`
5. 默认用 `tracked_truth` 作为最终 BER 判决结果

所以：

- 输入数据是“最新那组采集”
- truth 是 `tx_truth.json`
- 默认最终结果模式是 `tracked_truth`

---

## 六、为什么“tracked_truth”不是文件

`tracked_truth` 只是 `BER_MODE` 的取值。

它决定的是：

- 最终展示哪条结果作为主结果
- BER 统计和 truth 一致性判决用哪条链路的输出

它不决定“读哪一个采集文件”。

采集文件是由 `CAPTURE_PATH` 或 `latest_capture` 决定的。

---

## 七、脚本其实会同时跑两条链

即使你设置了：

```matlab
BER_MODE = 'tracked_truth';
```

脚本仍会先后执行：

1. `recover_nav_bits(...)` 对应的 `open_loop_truth`
2. `track_nav_bits(...)` 对应的 `tracked_truth`

区别只是最后：

- `BER_MODE='tracked_truth'` 时，主结果取 `tracked_result`
- `BER_MODE='open_loop_truth'` 时，主结果取 `open_loop_result`

所以它不是“只跑 tracked，不跑 open-loop”，而是“两条都跑，最后选哪条做主结果”。

---

## 八、什么时候一定要显式设置 `CAPTURE_PATH`

下面这些场景，建议不要依赖“直接分析最新文件请按回车”：

- 你要严格复现固定回归样本 `20260328_142122...dur30p0s`
- 目录里刚生成了新的联机采集
- 有多人共用共享目录，最新文件可能不是你要的
- 你正在排障，需要保证前后两次分析输入完全相同

推荐写法：

```matlab
CAPTURE_PATH = ['C:\VMwareVirtualMachines\GongXiangDocument\GNSS_RX_Data\2026\' ...
    '2026_03_28\20260328_142122_rawiq_sc16_zeroif_prn1_spread_sr4092000_' ...
    'cf100000000_dur30p0s\20260328_142122_rawiq_sc16_zeroif_prn1_spread_' ...
    'sr4092000_cf100000000_dur30p0s'];
TX_TRUTH_PATH = 'C:\VMwareVirtualMachines\GongXiangDocument\GNSS_RX_matlab\tx_truth.json';
BER_MODE = 'tracked_truth';
run('scripts/run_ber_loopback.m')
```

对于联机 `30 s` 复验，这通常意味着：

1. 先跑完 TX `--duration 60`
2. 再跑完 RX `record_rx.py --duration 30`
3. 从 RX 终端输出中抄下新的 `data_file=...`
4. 将 Linux 共享目录路径改写为 Windows MATLAB 路径
5. 把这次“新采集”的 stem 写入 `CAPTURE_PATH`

如果只是临时快速看结果，也可以不手填 `CAPTURE_PATH`，而是：

```matlab
clear CAPTURE_PATH
TX_TRUTH_PATH = 'C:\VMwareVirtualMachines\GongXiangDocument\GNSS_RX_matlab\tx_truth.json';
BER_MODE = 'tracked_truth';
run('scripts/run_ber_loopback.m')
```

然后在脚本提示“直接分析最新文件请按回车”时直接按回车。

但这只适合你能确认“刚刚采的那份就是目录里最新文件”的场景。

---

## 九、一句话记忆版

可以把这 4 个量记成：

- `CAPTURE_PATH`：我要分析哪组 IQ
- `latest_capture`：脚本替我自动选的“最新 IQ”
- `TX_TRUTH_PATH`：拿来对比的 TX 真值
- `BER_MODE`：最后用哪条链的结果做主判决

---

## 十、为什么 `tracked_match` 可能看起来很好，但后半段 BER 已经崩了

这在出现 RX overflow 或中途采集连续性破坏时尤其容易误判。

当前 `track_nav_bits.m` 的执行顺序是：

1. 先在 `estimate_initial_bit_alignment(...)` 中做初始对齐
2. 再把该初始对齐结果用于整段 bit 积分与 BER 统计

而 `tracked_result.match_rate` 实际保存的是：

```matlab
tracked_result.match_rate = initial_alignment.match_rate;
```

也就是说，它主要反映“初始训练窗口”的匹配质量，而不是整段 `30 s` 的全局 match。

同时默认参数里：

```matlab
alignment_training_ms = 2000
```

所以如果：

- 前 2 s 很干净
- 18 s 左右发生 overflow
- 18 s 之后 tracking 被异常拖偏

那么就会出现：

- `tracked_match` 仍然很好
- 但 `selected_ber`、`局部 BER`、`误码位置` 已经明显恶化

因此在 overflow 或后半段突发异常场景下，`tracked_match` 不能单独作为“整段 30 s 仍然正常”的证据，必须同时结合：

- `selected_ber`
- `window_ber`
- `reacq_events`
- `fll_freq_hz / phase_error_deg`

一起判断。
