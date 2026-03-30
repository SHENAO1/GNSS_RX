# 接收端专项实验：BER 判断逻辑分析

> 创建时间：2026-03-29
> 适用范围：当前 `GNSS_RX` 仓库中的 MATLAB BER 主链
> 关注文件：
> - `matlab/scripts/run_ber_loopback.m`
> - `matlab/functions/track_nav_bits.m`
> - `matlab/functions/recover_nav_bits.m`
> - `matlab/functions/load_tx_truth_json.m`

---

## 1. 这份文档回答什么问题

这份专题不讨论“采集为什么 overflow”或“TX/RX 联机怎么跑”，而是只回答一个更聚焦的问题：

**接收端当前到底是如何形成最终 BER 判断的？**

这里的“判断”分成三层：

1. **能不能继续算**：捕获是否成功、truth 是否可用
2. **当前结果像不像正确对齐**：`ambiguity_flag`、`match_rate`、`pattern_offset`、`bit_offset_ms`
3. **最后报出来的 BER 数字怎么来的**：哪些 bit 被计入，哪些只是做诊断

---

## 2. 一句话结论

当前默认主链是 `tracked_truth`，最终 `BER` 由 `run_ber_loopback.m` 在 **Step 6** 里直接对 `selected_result.rx_bits` 和 `selected_result.ref_bits` 做**全量逐位比较**得到；`lock_quality` 与 `window_ber.valid` 目前只参与**诊断和标记坏窗口**，**不会自动把坏段从总 BER 中剔除**。

---

## 3. 总体流程图

```mermaid
flowchart TD
    A[CAPTURE_PATH / 最新采集] --> B[Step 1\nload_gnss_rx_capture]
    B --> C[Step 2\nrun_prn_acquisition\n前 100 ms 捕获]
    C -->|捕获失败| X[脚本终止]
    C -->|捕获成功| D[Step 2.5\n加载 TX truth JSON\n或 fallback truth]

    D --> E[Step 3\nrecover_nav_bits\nopen-loop 基线]
    D --> F
    C --> F[Step 4\ntrack_nav_bits\ntracked 主链]

    subgraph T[tracked 主链内部]
        F1[1 ms DLL 码跟踪\nprompt / early / late]
        F2[FLL + PLL\n载波跟踪]
        F3[前 2000 ms 初始对齐\n搜索 bit_offset / pattern_offset / polarity]
        F4[长时间 bit 时序稳定性检查\nwindow_match_rate]
        F5[按 20 ms 积分成 bit\n生成 rx_bits]
        F6[生成 ref_bits]
        F7[tracked_result.ber]
        F8[lock_quality + window_ber.valid\n仅诊断]
        F1 --> F2 --> F3 --> F4 --> F5 --> F6 --> F7
        F4 --> F8
        F2 --> F8
    end

    F --> G{BER_MODE}
    E --> G
    G -->|默认 tracked_truth| H[selected_result = tracked_result]
    G -->|open_loop_truth| I[selected_result = open_loop_result]
    H --> J[Step 5\nambiguity / match_rate 告警]
    I --> J
    J --> K[Step 6\nerrors = sum(rx_bits != ref_bits)\nBER = errors / total_bits]
    F8 -.不会自动剔除坏段.-> K
```

---

## 4. 当前 BER 判断逻辑拆解

### 4.1 Step 2 先决定“能不能继续算”

入口脚本先只取前 `100 ms` 做捕获；如果 `acq_result.detected/acquired` 为假，就直接报错退出，不会进入 BER 阶段。

对应实现：

- `run_ber_loopback.m`
  - `ACQ_DURATION_S = 0.1`
  - 捕获成功判定：`detected` / `acquired`
  - 捕获失败阈值提示：次峰比阈值 `2.5`

这意味着：

- 当前 BER 分析默认建立在“先成功捕获”的前提上
- 如果连捕获都没过，脚本不会给出一个“高 BER”结果，而是直接终止

---

### 4.2 Step 2.5 先确定参考真值来自哪里

truth 有两种来源：

1. **JSON 模式**
   - 通过 `load_tx_truth_json.m` 读取发送端导出的标准契约
   - 要求存在 `nav_bits_pattern_pm1`、`initial_nav_bit_index`、`sample_rate`、`epochs_per_bit`、`prn_id` 等字段
2. **fallback 模式**
   - 当找不到 JSON 时，用脚本内默认 pattern 兜底
   - 只适合兼容旧流程和粗排障，不适合做严格 BER 结论

当前代码对 JSON 的依赖重点其实是：

- `track_nav_bits.m` 至少需要 `truth.nav_bits_pattern_pm1`
- `run_ber_loopback.m` 在日志里会明确打印 `truth_mode = json / fallback`

因此，从工程口径上看：

- **没有 JSON 也能算 BER**
- 但**没有 JSON 时，这个 BER 更像“脚本自洽程度”而不是“严格 TX/RX 闭环误码率”**

---

### 4.3 Step 3 的 open-loop 只是诊断基线，不是默认最终结论

`recover_nav_bits.m` 会做一条更“离线枚举”的基线：

1. 先按 acquisition 的码相位和 Doppler 取出每个 `1 ms` 的复相关
2. 先做粗残余频偏补偿
3. 穷举：
   - `bit_offset_ms = 0..19`
   - `pattern_offset`
   - `polarity = +/-1`
4. 选择评分最高的一组作为 `open_loop_result`

其用途是：

- 帮我们确认 truth 对齐有没有明显错位
- 帮我们判断问题更像“tracking 不稳”还是“对齐/真值本身就不对”

但默认模式下：

- `selected_result = tracked_result`
- 只有显式设置 `BER_MODE = 'open_loop_truth'` 时才会把 open-loop 作为最终主结果

所以当前系统里：

- `open-loop` 是**对照组**
- `tracked` 才是**主判决链**

---

### 4.4 Step 4 的 tracked 主链才是现在的核心

`track_nav_bits.m` 里的逻辑可以拆成 5 个子阶段。

#### 阶段 A：1 ms 码跟踪

函数 `track_code_phase_ms(...)` 逐 `1 ms` 计算：

- `prompt`
- `early`
- `late`

并通过它们的强弱关系微调下一毫秒的码相位；如果锁定指标偏低，还会在局部采样点范围内做一次小范围重搜。

这一步的产物是：

- `prompt_ms`
- `early_ms`
- `late_ms`
- `code_phase_samples`
- `code_track_events`
- `lock_metric_ms`

它决定的是：后面所有 bit 判决所依赖的 `prompt` 是否站在正确码相位上。

#### 阶段 B：载波跟踪

函数 `track_carrier_from_prompt(...)` 先做：

- FLL 平滑频偏估计

再做：

- PLL 相位细调

得到：

- `prompt_fll`
- `prompt_pll`
- `carrier_history`

这一步决定的是：20 ms 积分时，相位会不会互相抵消。

#### 阶段 C：只在前 2000 ms 做“初始对齐”

函数 `estimate_initial_bit_alignment(...)` 只取训练段：

- `training_ms = min(alignment_training_ms, length(prompt_pll))`
- 默认 `alignment_training_ms = 2000`

然后搜索：

- `bit_offset_ms = 0..19`
- `pattern_offset = 0..pattern_len-1`
- `polarity = +/-1`

评分主式为：

```text
score = 1e6 * match_rate + 1e3 * mean(real(bit_corr_rot .* ref_bits))
```

最后输出：

- `bit_offset_ms`
- `pattern_offset`
- `polarity`
- `match_rate`
- `ambiguity_flag`
- `ambiguity_margin`

这里有一个非常关键的事实：

**`tracked_result.match_rate` 直接等于 `initial_alignment.match_rate`，它只反映初始训练窗的匹配质量，不代表整段采集的全局匹配率。**

这也是为什么会出现下面这种现象：

- 前 2 秒很干净
- 中后段因为 overflow/失锁导致 BER 崩掉
- 但 `tracked match_rate` 看起来仍然不错

#### 阶段 D：检查 bit 时序是否在后续漂移

函数 `check_bit_timing_stability(...)` 会按窗口周期性检查：

- 当前 `initial_bit_offset_ms` 的能量
- 与局部最优 `bit_offset` 的能量相比差多少

定义：

```text
window_match_rate = base_energy / best_energy
```

含义：

- 接近 `1.0`：当前 bit 边界仍像是正确的
- 明显低于 `1.0`：说明更优的 bit 边界已经漂到别处去了

默认参数：

- `bit_timing_check_interval_ms = 1000`
- `bit_timing_check_span_ms = 2000`
- `bit_timing_realign_margin = 1.05`

这一步不会直接改写最终 `bit_offset_ms`，而是：

- 生成 `window_match_rate`
- 记录 `bit_timing_watch` 事件

所以它更像“监控器”，不是“自动修复器”。

#### 阶段 E：按固定 bit 边界积分并判决

后续 `integrate_bits_from_prompt(...)` 会沿着 **阶段 C 找到的固定 `bit_offset_ms`**，把每 `20 ms` 的 `prompt_pll` 积成一个 bit：

1. `bit_corr = sum(prompt_pll(ms_s:ms_e))`
2. 用 `phi_axis = angle(sum(bit_corr.^2))/2` 估公共相位轴
3. `rx_bits = sign(real(bit_corr_rot))`
4. 用已选好的 `pattern_offset + polarity` 生成 `ref_bits`
5. `tracked_result.ber = mean(rx_bits ~= ref_bits)`

注意这里的 `tracked_result.ber` 也是**全量 bit 平均**，并没有在这个位置使用 `lock_quality` 去剔除坏段。

---

## 5. 哪些量属于“判决”，哪些量只是“诊断”

### 5.1 真正参与最终 BER 数字的量

`run_ber_loopback.m` 的 Step 6 会重新计算：

```matlab
errors = sum(sign(selected_result.rx_bits) ~= sign(selected_result.ref_bits));
total_bits = length(selected_result.rx_bits);
ber = errors / total_bits;
```

所以真正进入最终打印结果的，是：

- `selected_result.rx_bits`
- `selected_result.ref_bits`
- `selected_result.bit_offset_ms`
- `selected_result.pattern_offset`
- `selected_result.polarity`
- `selected_result.match_rate`

其中默认 `selected_result = tracked_result`。

### 5.2 只做告警或解释，不自动改写总 BER 的量

下面这些量当前都很重要，但它们**不会自动从总 BER 里删掉坏样本**：

- `ambiguity_flag`
- `ambiguity_margin`
- `reacq_events`
- `window_match_rate`
- `lock_quality_per_bit`
- `window_ber.valid`

当前它们的角色是：

- 帮你判断“这个 BER 能不能信”
- 帮你解释“为什么 BER 在某段时间突然抬升”
- 帮你定位是否发生过 bit timing 漂移或局部重同步

但它们**不是** Step 6 的总 BER 掩码。

---

## 6. 当前实现里的几个关键阈值

| 位置 | 含义 | 当前值 |
|------|------|--------|
| Step 2 | acquisition 次峰比判定阈值 | `2.5` |
| tracking 默认参数 | 最短 tracking 长度 | `200 ms` |
| tracking 默认参数 | 训练窗长度 | `2000 ms` |
| tracking 默认参数 | code lock 阈值 | `0.08` |
| tracking 默认参数 | FLL 突变阈值 | `10 Hz` |
| tracking 默认参数 | bit timing 检查周期 | `1000 ms` |
| tracking 默认参数 | bit timing 检查窗长 | `2000 ms` |
| tracking 默认参数 | bit 时序正常阈值 | `window_match_rate >= 0.9` |
| Step 5 | `match_rate` 低可信度告警阈值 | `< 0.55` |
| tracked 初始对齐 | ambiguity 条件之一 | `match_rate < 0.7` |
| tracked 初始对齐 | ambiguity 条件之二 | `ambiguity_margin < 2e4` |
| window BER | 默认滑窗长度 | `100 bit` |

---

## 7. 当前代码口径下，应该怎样理解“BER 判断”

### 7.1 它不是单一数字，而是“三级口径”

建议把当前系统的 BER 判断理解成三层：

1. **脚本层硬门槛**
   - acquisition 成功，否则直接退出
2. **truth/对齐层可信度**
   - `truth_mode`
   - `ambiguity_flag`
   - `match_rate`
   - `pattern_offset / bit_offset_ms`
3. **误码统计层**
   - Step 6 的全量 BER

### 7.2 当前“总 BER”更像分析结果，不是自动化验收结论

因为现在还没有把：

- `overflow`
- `underflow`
- `lock_quality`
- `window_ber.valid`

真正接到 Step 6 的统计掩码里，所以当前打印出来的总 BER 更适合解释为：

**“在当前选中的对齐参数下，对整段比特序列做的全量误码统计结果。”**

它还不是一个已经内建了“坏段剔除策略”的严格验收 BER。

---

## 8. 对 overflow 场景最重要的理解

结合当前实现，overflow 后最常见的误判方式是：

1. 前训练窗仍然很干净
2. `initial_alignment.match_rate` 仍然很高
3. 后续某段发生 bit timing 漂移或重同步
4. `window_match_rate`、`reacq_events`、`window_ber` 已经提示异常
5. 但 Step 6 仍对**全量 bit**做 BER 统计

所以当前工程上应当坚持：

- `tracked match_rate` 不能单独当作“整段稳定”的证明
- `window_ber.valid=false` 不能理解成“坏段已经从总 BER 里自动去掉了”
- 如果 RX 日志出现 overflow，且 BER 后段明显抬升，应优先视为**采集连续性破坏**，而不是先怀疑 TX bit 本身错了

---

## 9. 当前逻辑的工程含义

### 9.1 现在默认已经有的优点

- `tracked_truth` 已经把码跟踪、载波跟踪、初始对齐、滑窗诊断串成一条完整主链
- 有 `open-loop` 对照组，方便区分“tracking 问题”和“truth/对齐问题”
- 有 `reacq_events`、`window_match_rate`、`lock_quality`，已经具备做更严格验收掩码的基础

### 9.2 现在最需要记住的限制

- `tracked_result.match_rate` 不是整段全局 match
- `lock_quality` 目前只进了 `window_ber.valid`
- Step 6 的总 BER 没有做坏段剔除
- fallback truth 可以跑流程，但不适合正式闭环结论

---

## 10. 如果后面要把它升级成“正式验收口径”，优先改哪里

最自然的演进方向是把 Step 6 从“全量 BER”升级成“有效段 BER + 总 BER 同时输出”。

建议顺序：

1. 先保留当前 `raw_ber` 口径不变，避免历史结果失去可比性
2. 新增 `effective_bit_mask`
   - 来源可以是 `lock_quality_per_bit`
   - 或 `window_ber.valid` 映射回 bit 级掩码
3. 再新增：
   - `effective_errors`
   - `effective_total_bits`
   - `effective_ber`
4. 最后把 overflow/underflow 事件与有效段统计一起归档

这样既不会丢掉“整段污染程度”，又能给出“有效样本上的 BER”。

---

## 11. 对照源码时最值得看的位置

- `matlab/scripts/run_ber_loopback.m`
  - Step 2：捕获是否成功
  - Step 4：默认主链是 `tracked_truth`
  - Step 5：`ambiguity_flag` / `match_rate < 0.55` 告警
  - Step 6：最终总 BER 的全量逐位统计
- `matlab/functions/track_nav_bits.m`
  - `estimate_initial_bit_alignment(...)`
  - `check_bit_timing_stability(...)`
  - `build_bit_lock_quality(...)`
  - `compute_window_ber(...)`
- `matlab/functions/recover_nav_bits.m`
  - `joint_search_with_truth(...)`
  - 作为 open-loop 对照组
- `matlab/functions/load_tx_truth_json.m`
  - truth JSON 必需字段定义

---

## 12. 本文结论

当前接收端的“BER 判断逻辑”已经不是单纯的 `rx_bits != ref_bits`，而是：

- 先捕获
- 再拿 truth 建立对齐
- 再用 tracked 主链做 bit 判决
- 最后输出全量 BER
- 同时附带一组尚未进入总 BER 掩码的可信度/坏段诊断量

如果后面我们要继续把 BER 从“可解释分析结果”推进到“正式验收口径”，最关键的一步不是继续加新图，而是把 **`lock_quality` / `window_ber.valid` 真正接入 Step 6 的统计口径**。
