# 闭环 BER 异常排障操作手册

> 创建时间：2026-03-28
> 适用场景：`Milestone 1` 射频线直连闭环 BER 验证中，捕获成功但 BER 长时间停留在 `0.45 ~ 0.50`
> 当前现象：PRN 捕获稳定、次峰比很高、残余频偏可估计，但最终 BER 仍接近随机
> 对应 RX 计划：`2026-03-28_ber_loopback_rx_plan.md`
> 对应 TX 计划：`/home/shen/projects/gnss_tx/experiments/plans/2026-03-28/ber_loopback_tx/2026-03-28_ber_loopback_tx_plan.md`

---

## 2026-03-28 实现更新

当前工程状态已经进入下一阶段：

- TX 侧已经支持导出 `truth JSON`，RX 不再依赖手写 `TX_PATTERN` 作为唯一真值来源。
- RX 侧已经保留 `open_loop_truth` 诊断基线，并新增 `tracked_truth` 主链入口。
- RX 采集侧已经支持：
  - `capture_mode=single`
  - `capture_mode=chunked`
  - `chunk_duration_s` 可调

当前推荐执行顺序已经变更为：

1. 固定当前 30 s 基线采集文件
2. 导出 TX truth JSON
3. 在宿主机同步最新 MATLAB 文件
4. 先跑 `tracked_truth`
5. 若 30 s BER 未收敛，再看 tracking 曲线和重同步事件，而不是先改 TX pattern

推荐命令：

```bash
cd /home/shen/projects/gnss_tx
env PYTHONPATH=src python3 scripts/run_tx.py \
    --config configs/tx_b210_cable_loopback.yaml \
    --dry-run \
    --export-truth-json /mnt/hgfs/GongXiangDocument/GNSS_RX_matlab/tx_truth.json
```

```bash
cd /home/shen/projects/GNSS_RX
env PYTHONPATH=src python3 scripts/record_rx.py \
    --config configs/rx_cable_loopback.yaml \
    --duration 95 \
    --capture-mode chunked \
    --chunk-duration 30 \
    --dry-run
```

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

本手册后续旧小节仍保留，主要用于回看早期排障思路；当前执行时，以本节流程为准。

### 宿主机同步清单

每次 MATLAB 逻辑有更新时，至少同步以下文件到 `GNSS_RX_matlab/`：

- `scripts/run_ber_loopback.m`
- `functions/recover_nav_bits.m`
- `functions/track_nav_bits.m`
- `functions/plot_ber_loopback.m`
- `functions/load_tx_truth_json.m`
- `functions/build_fallback_tx_truth.m`

若同步后在宿主机 MATLAB 中仍看到旧日志格式，优先执行：

```matlab
clear functions
rehash
which run_ber_loopback -all
which recover_nav_bits -all
which track_nav_bits -all
```

---

## 一、当前判断

当前这组问题更像是“**参考比特序列不一致**”或“**开环恢复后的 bit 对齐假设不成立**”，而不是：

- 发端没有发出信号
- PRN 没有对齐
- USRP 持续 underflow
- 单纯的 SNR 不足

已知依据：

- 捕获成功，`Doppler = 0.0 Hz`
- 次峰比很高（`111.01`），说明目标 PRN 很清楚
- 细频偏补偿后，bit 相关相位已经分成两团，说明载波判决轴基本可用
- 但 BER 仍接近 `50%`，说明“恢复出的 bit 序列”和“用于对比的参考序列”大概率不是同一组

因此，下一步不应继续盲目调增益，而应优先确认：

1. RX 端是否真的在拿对的参考 bit 序列做 BER 对比
2. TX 端实际发出的 nav pattern 是否就是计划里写的 `"1 0 1 1 0 0 1 0"`
3. 开环比特恢复是否存在固定的 bit 周期假设错误

---

## 二、执行目标

本手册的目标不是立刻把 BER 调到 0，而是先把问题缩小到以下三类中的一类：

1. **RX 参考序列错了**
2. **TX 实际发送序列和配置不一致**
3. **RX 开环恢复逻辑仍有 bit 边界/时序问题**

只要能先把问题明确归类，后续修复会快很多。

---

## 三、推荐操作流程

### Step 0：冻结本次排障基线

先不要改动采集文件，也不要换新数据，固定使用当前这份 30 s 采集：

```text
C:\VMwareVirtualMachines\GongXiangDocument\GNSS_RX_Data\2026\2026_03_28\20260328_142122_rawiq_sc16_zeroif_prn1_spread_sr4092000_cf100000000_dur30p0s
```

本轮所有判断都基于同一份文件完成，避免“代码变了”和“数据也变了”混在一起。

完成标志：

- [ ] 本轮排障固定使用同一份 30 s 采集文件
- [ ] 不在中途切换另一份采集数据

### Step 1：确认 MATLAB 确实在跑最新脚本

在 MATLAB 中执行：

```matlab
clear functions
rehash
which recover_nav_bits -all
which run_ber_loopback -all
```

检查点：

- `recover_nav_bits.m` 指向 GNSS_RX 当前同步目录
- `run_ber_loopback.m` 指向 GNSS_RX 当前同步目录
- 控制台日志里能看到：
  - `--- 诊断（前 8 个 1 ms 相关）---`
  - `细残余频偏估计：Δf_fine = ...`

完成标志：

- [ ] MATLAB 没有跑到旧缓存版本
- [ ] 日志包含最新诊断输出

### Step 2：先做“RX 参考序列假设”验证

这是当前优先级最高的一步，因为成本最低，而且最可能直接定位问题。

当前 RX 主脚本默认参考序列是：

```matlab
TX_PATTERN = [+1, -1, +1, +1, -1, -1, +1, -1];
```

但最近恢复出的前 8 bit 更像：

```text
-1 -1 +1 +1 -1 +1 -1 +1
```

先在同一份采集文件上做两次离线对比，不重新采集。

#### 2.1 基线参考序列

保持：

```matlab
TX_PATTERN = [+1, -1, +1, +1, -1, -1, +1, -1];
```

运行一次并记录：

- `最佳对齐偏移`
- `匹配率`
- `BER`

#### 2.2 候选参考序列

临时改成：

```matlab
TX_PATTERN = [-1, -1, +1, +1, -1, +1, -1, +1];
```

再次运行同一份采集文件，并记录：

- `最佳对齐偏移`
- `匹配率`
- `BER`

判定规则：

- 如果 BER 明显下降，说明当前主问题是“RX 参考序列假设错了”
- 如果 BER 仍接近 `50%`，继续做 Step 3

完成标志：

- [ ] 已在同一份采集上比较两套 `TX_PATTERN`
- [ ] 已记录哪一套参考序列更匹配

### Step 3：核对 TX 端“配置值”和“实际发射值”

如果 Step 2 显示候选参考序列更好，下一步就要确认 TX 端到底发了什么。

先检查配置文件：

```bash
cd /home/shen/projects/gnss_tx
sed -n '1,220p' configs/tx_b210_cable_loopback.yaml
```

重点确认：

- `nav_pattern`
- `initial_nav_bit_index`
- `initial_nav_epoch`
- `initial_code_phase`

然后做一次干运行：

```bash
cd /home/shen/projects/gnss_tx
PYTHONPATH=src python3 scripts/run_tx.py \
    --config configs/tx_b210_cable_loopback.yaml \
    --tx-gain 40 \
    --amplitude 1.0 \
    --dry-run
```

重点核对参数摘要中是否明确显示：

- `nav_pattern = 1 0 1 1 0 0 1 0`
- `initial_nav_bit_index = 0`
- `initial_nav_epoch = 0`

完成标志：

- [ ] YAML 中 `nav_pattern` 与计划一致
- [ ] 干运行参数摘要与 YAML 一致
- [ ] 未发现命令行覆盖或非零初始偏移

### Step 4：检查 TX 端代码链路是否有隐式改写

如果配置文件没问题，但 Step 2 又表明参考序列疑似不一致，就继续检查发端代码链。

优先查看以下文件：

- `src/gnss_tx/nav/nav_bits.py`
- `src/gnss_tx/gr/top_block.py`
- `src/gnss_tx/usrp/tx_controller.py`

重点确认：

- `0 -> -1`、`1 -> +1` 的映射没有被改
- `nav_pattern` 没有被额外改写
- `initial_nav_bit_index` 没有被非预期覆盖
- replay buffer 仍按完整 nav 周期生成

建议检查命令：

```bash
cd /home/shen/projects/gnss_tx
rg -n "nav_pattern|initial_nav_bit_index|initial_nav_epoch|normalize_nav_bits|DEFAULT_NAV_PATTERN" \
    src/gnss_tx
```

完成标志：

- [ ] `nav_pattern` 映射逻辑已核查
- [ ] 没有发现隐藏覆盖路径

### Step 5：只有在前四步都不能解释时，才重新采集

重新采集前要确保：

1. RX 使用的 `TX_PATTERN` 已确定
2. TX 配置和 dry-run 输出一致
3. MATLAB 脚本已同步并确认正在运行最新版本

此时再重新采一份 30 s 数据，才有意义。

完成标志：

- [ ] 新采集前，参考序列假设已固定
- [ ] 新采集前，TX 实际配置已确认

---

## 四、勾选清单

### 4.1 RX 侧清单

- [ ] `clear functions` 已执行
- [ ] `which recover_nav_bits -all` 已确认路径正确
- [ ] `which run_ber_loopback -all` 已确认路径正确
- [ ] 同一份采集文件已用“基线参考序列”重跑
- [ ] 同一份采集文件已用“候选参考序列”重跑
- [ ] 两次 BER / 匹配率已记录

### 4.2 TX 侧清单

- [ ] `configs/tx_b210_cable_loopback.yaml` 已核查
- [ ] `nav_pattern` 已确认
- [ ] `initial_nav_bit_index` 已确认
- [ ] `initial_nav_epoch` 已确认
- [ ] `run_tx.py --dry-run` 已执行
- [ ] dry-run 输出和 YAML 一致

### 4.3 判定清单

- [ ] 已判断是否为“RX 参考序列错了”
- [ ] 已判断是否为“TX 实际发送值和配置不一致”
- [ ] 已判断是否有必要重新采集

---

## 五、推荐记录模板

建议把本轮排障结果按下面格式回填到实验记录里：

```text
采集文件：

MATLAB 脚本版本：

基线 TX_PATTERN：
最佳偏移：
匹配率：
BER：

候选 TX_PATTERN：
最佳偏移：
匹配率：
BER：

TX dry-run 输出：
nav_pattern =
initial_nav_bit_index =
initial_nav_epoch =

结论：
1.
2.
3.
```

---

## 六、当前推荐优先级

按收益和成本排序，建议优先执行：

1. Step 2：对同一份采集测试候选 `TX_PATTERN`
2. Step 3：核对 TX YAML 和 dry-run 摘要
3. Step 4：检查 TX 代码链路
4. Step 5：确认后再重新采集

当前最不推荐的做法：

- 不核对参考序列就继续调 `tx_gain`
- 不固定采集文件就同时改代码和重新采集
- 还没确认 TX 实际发送内容，就继续调 RX 频偏算法
