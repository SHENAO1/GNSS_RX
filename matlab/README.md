# GNSS_RX MATLAB 工作区

本目录提供 GNSS_RX 的 MATLAB 离线分析链，读取接收端导出的 `.sc16 + .json` 采集文件，
完成快速可视化、指定 PRN 捕获、多星对比和结果归档。

---

## 函数目录

| 文件 | 说明 |
|------|------|
| `scripts/run_capture_analysis.m` | **主入口**：加载→绘图→PRN捕获→多星扫描→归档 |
| `functions/load_gnss_rx_capture.m` | 加载 `.sc16 + .json`，组装复数基带样本和元数据 |
| `functions/gnss_rx_resolve_data_dir.m` | 统一解析采集数据根目录（优先级：本地配置 > 环境变量 > 默认路径） |
| `functions/find_latest_capture.m` | 自动查找数据根目录下最新的完整采集文件对 |
| `functions/plot_capture_overview.m` | 生成时域图、频谱图和 IQ 散点图 |
| `functions/run_prn_acquisition.m` | **通用捕获入口**：从 `meta.prn_id` 读取目标 PRN（1~32），执行 Doppler×码相位二维搜索 |
| `functions/run_prn1_acquisition.m` | 向后兼容封装：强制 PRN1，内部调用 `run_prn_acquisition` |
| `functions/run_multi_prn_survey.m` | 对 PRN1~32 批量搜索，生成多星对比结果 |
| `functions/plot_multi_prn_survey.m` | 绘制多星次峰比柱状图 |
| `functions/save_analysis_artifacts.m` | 保存图片、`.json` 摘要和 `.mat` 结果 |
| `gnss_rx_user_paths.m.example` | 用户本地路径配置模板 |
| `scripts/run_capture_iq_diagnostic.m` | 原始 IQ 诊断入口：去均值、BPSK 粗相位校正、sample-phase 分组散点图 |
| `scripts/run_ber_loopback_chunk_group.m` | chunked BER 汇总入口：对单个 chunk 或整组 chunk 运行正式 BER 并汇总 |
| `scripts/run_ber_loopback_chunk_selection.m` | chunked BER 逐段入口：按 chunk 序号依次运行 BER，并输出每段结果 |
| `scripts/run_capture_analysis_chunk_group.m` | chunked 快速体检入口：枚举目录中的 chunk，并按序号批量调用 `run_capture_analysis` |

---

## 入口对比

下面这 4 个入口最容易混淆，可以按“快速体检”与“正式 BER”两类来记。

| 文件 | 类型 | 主要用途 | 输入方式 | 典型输出 | 适用场景 |
|------|------|----------|----------|----------|----------|
| `run_capture_analysis_chunk_group.m` | 快速体检 | 对 chunk 调用 `run_capture_analysis(...)`，看加载、频谱、IQ、捕获、多星扫描 | `CAPTURE_DIR` 或指定 chunk 序号 | `overview_time / overview_spectrum / iq_scatter / acquisition / survey` | 想先确认样本是否正常、PRN1 是否能稳定捕获 |
| `run_capture_iq_diagnostic.m` | IQ 诊断 | 专门检查 IQ 散点为什么“看起来不对”，包括去均值、粗相位校正、sample-phase 分组 | 单个 `CAPTURE_PATH` | `iq_diagnostic_compare.png`、`iq_diagnostic_sample_phase.png`、诊断统计量 | 怀疑 `Q` 偏大、散点图歪斜、存在 DC / 相位旋转 / sample-phase 过渡现象 |
| `run_ber_loopback_chunk_group.m` | 正式 BER | 对单个 chunk 或整组 chunk 运行 `tracked_truth` BER，并给出整组汇总 | 单个 `CAPTURE_PATH` 或 `CAPTURE_DIR` | `aggregate_errors / aggregate_bits / aggregate_ber` | 想得到正式 BER 结论，尤其是整组 15 个 chunk 的总 BER |
| `run_ber_loopback_chunk_selection.m` | 正式 BER | 按指定 chunk 序号逐段运行 BER，并把每段 BER 依次打印、汇总返回 | `CAPTURE_DIR` + `2:15`、`[1 8 15]` 等 | 每段 `errors / total_bits / ber`，外加所选 chunk 汇总 | 想定位“哪一段 BER 变差了”，而不只看整组 aggregate |

一句话区分：

- `run_capture_analysis_chunk_group`：先看图、看捕获、看体检
- `run_capture_iq_diagnostic`：专门查 IQ 几何为什么怪
- `run_ber_loopback_chunk_group`：正式 BER，看单段或整组总结果
- `run_ber_loopback_chunk_selection`：正式 BER，但把指定 chunk 挨个展开看

推荐顺序：

1. 先用 `run_capture_analysis_chunk_group(CAPTURE_DIR, [1 8 15])` 抽查代表 chunk
2. 若 IQ 散点可疑，再对单个可疑 chunk 跑 `run_capture_iq_diagnostic(CAPTURE_PATH)`
3. 想看整组正式结论，用 `run_ber_loopback_chunk_group(CAPTURE_DIR)`
4. 想定位异常区段，用 `run_ber_loopback_chunk_selection(CAPTURE_DIR, 2:15)`

---

## 架构图

| 文件 | 说明 |
|------|------|
| `../docs/diagrams/matlab_architecture.drawio` | `run_capture_analysis` 主链：加载、总览、PRN 捕获、多星扫描、归档 |
| `../docs/diagrams/ber_loopback.drawio` | `run_ber_loopback` 诊断链：truth 读取、open-loop 基线、tracked BER 主链 |

---

## 快速开始

### 1. 配置数据目录

```bash
# 复制模板
cp /home/shenao/projects/GNSS_RX/matlab/gnss_rx_user_paths.m.example \
   /home/shenao/projects/GNSS_RX/matlab/gnss_rx_user_paths.m
```

在 `gnss_rx_user_paths.m` 中填写实际数据目录：

```matlab
% Windows 主力机（推荐：本地 SSD 分析目录）
GNSS_RX_DATA_DIR = 'E:\MATLAB_code_Gongwei_Local\GNSS_RX_Data_local';

% 或 Linux 本机
GNSS_RX_DATA_DIR = '/home/shenao/GNSS_RX_Data_local';
```

### 2. 同步 MATLAB 代码到 Windows 主力机

`GNSS_RX/matlab/` 是 MATLAB 代码的唯一真相源。
推荐固定采用“两段式同步”：

1. Ubuntu 端同步到 `~/GNSS_RX_matlab_share`
2. Windows 主力机从已挂载网络盘 `Z:`（`\\100.65.171.95\gnss_rx_matlab`）镜像到 `E:\MATLAB_code_Gongwei_Local\GNSS_RX_matlab`

同步脚本会保留共享根目录中的运行期文件，例如 `tx_truth.json`。
采集目录中的 sidecar truth（如 `<capture_stem>_tx_truth.json`）属于数据，不属于 MATLAB 代码镜像，不会由同步脚本搬运。

```bash
# Ubuntu 端：同步到本机共享目录
/home/shenao/projects/GNSS_RX/scripts/sync_matlab.sh \
    ~/GNSS_RX_matlab_share
```

```powershell
# Windows 端：从网络盘同步到本地 MATLAB 工作区
robocopy Z:\ E:\MATLAB_code_Gongwei_Local\GNSS_RX_matlab /MIR
```

若 Ubuntu 主机重启后 `Z:` 断开，先重新挂载，再执行 `robocopy`：

```powershell
net use Z: /delete
net use Z: \\100.65.171.95\gnss_rx_matlab /persistent:yes
dir Z:\
robocopy Z:\ E:\MATLAB_code_Gongwei_Local\GNSS_RX_matlab /MIR
```

若同时需要从 Windows 自动访问 Ubuntu 开发目录，可额外挂载：

```powershell
net use Y: \\100.65.171.95\projects /persistent:yes
```

其中 `Z:` 只用于 `gnss_rx_matlab`，`Y:` 只用于 `projects`。

若 Ubuntu 当前 Tailscale IPv4 变化，先在 Ubuntu 执行 `tailscale ip -4`，再把命令中的 IP 替换为当前值。

同步结果包含：

- `functions/`
- `scripts/`（含所有入口脚本：`ber.m`、`run_capture_analysis.m`、`run_ber_loopback.m`、`run_capture_iq_diagnostic.m`、`run_ber_loopback_chunk_group.m`、`run_ber_loopback_chunk_selection.m`、`run_capture_analysis_chunk_group.m`）
- `README.md`
- `gnss_rx_user_paths.m.example`

每次 Ubuntu 端修改 MATLAB 代码后，统一执行上面的同步命令；随后在主力机 MATLAB 中执行：

```matlab
cd('E:\MATLAB_code_Gongwei_Local\GNSS_RX_matlab')
clear functions
rehash

which ber -all
which run_capture_iq_diagnostic -all
which run_ber_loopback_chunk_selection -all
which run_capture_analysis_chunk_group -all
which run_ber_loopback -all
which run_ber_loopback_chunk_group -all
which load_tx_truth_json -all
```

要求这些路径都指向刚同步的 `GNSS_RX_matlab` 部署目录。

### 3. 在 MATLAB 中运行分析

**Windows 主力机 MATLAB：**

```matlab
cd('E:\MATLAB_code_Gongwei_Local\GNSS_RX_matlab')
result = run_capture_analysis();          % 自动分析最新文件
```

**Linux 本机 MATLAB：**

```matlab
cd('/home/shenao/projects/GNSS_RX/matlab')
result = run_capture_analysis();
```

### 3.1 正式 BER 的 truth 匹配口径

`ber` / `run_ber_loopback.m` 当前的 truth 查找优先级为：

1. 调用前显式设置的 `TX_TRUTH_PATH`
2. `CAPTURE_PATH` 同目录下的 sidecar truth
   例如 `<capture_stem>_tx_truth.json`
3. MATLAB 工作区根目录下的 `tx_truth.json`
4. 脚本内部 fallback truth

正式 BER 验收应优先使用前 3 种 JSON truth 来源；fallback 仅用于诊断。

### 3.2 推荐的正式 BER 数据组织

推荐让每轮采集形成下面的三件套：

```text
<capture_dir>/
  <capture_stem>.sc16
  <capture_stem>.json
  <capture_stem>_tx_truth.json
```

这样在 MATLAB 中通常只需要设置 `CAPTURE_PATH`，`ber` 就会自动优先加载 sidecar truth。

**Windows 主力机 MATLAB：**

```matlab
cd('E:\MATLAB_code_Gongwei_Local\GNSS_RX_matlab')
clear functions
rehash

CAPTURE_PATH = ['E:\MATLAB_code_Gongwei_Local\GNSS_RX_Data_local\2026\2026_03_30\' ...
    '20260330_025519_rawiq_sc16_zeroif_prn1_spread_sr4092000_' ...
    'cf100000000_dur300p0s\20260330_025519_rawiq_sc16_zeroif_' ...
    'prn1_spread_sr4092000_cf100000000_dur300p0s.json'];
BER_MODE = 'tracked_truth';

ber
```

若 sidecar truth 不存在，但工作区根目录下有兼容旧流程的 `tx_truth.json`，`ber` 会自动把它当成 fallback JSON truth。
若两者都不存在，脚本会进入 fallback pattern 模式；该结果不作为正式 BER 结论。

**分析指定文件（stem 路径，stem 在路径中出现两次）：**

```matlab
% Windows 主力机
result = run_capture_analysis( ...
  'E:\MATLAB_code_Gongwei_Local\GNSS_RX_Data_local\2026\2026_03_26\<stem>\<stem>');

% Linux 本机
result = run_capture_analysis( ...
  '/home/shenao/GNSS_RX_Data_local/2026/2026_03_26/<stem>/<stem>');
```

### 4. 启用 MATLAB 离线分析加速

BER 主链可通过 `ACCEL_OPTIONS` 启用 GPU / CPU 并行加速：

```matlab
ACCEL_OPTIONS = struct( ...
    'backend', 'gpu', ...
    'precision', 'single', ...
    'batch_ms', 2000, ...
    'use_parfor', false, ...
    'device_index', []);
ber
```

自动回退模式：

```matlab
ACCEL_OPTIONS = struct('backend', 'auto', 'precision', 'single');
ber
```

说明：

- `backend='gpu'`：必须检测到可用 NVIDIA GPU，否则直接报错
- `backend='auto'`：若无可用 GPU，自动回退到 CPU
- `precision='single'`：优先降低长采集内存压力，推荐用于 `250 s / 1 h`
- `use_parfor=true`：仅在 CPU 路径下用于天然可并行的批量扫描场景
- `track_nav_bits` 的 tracking 主循环在当前版本仍保持 CPU 执行
- GPU 加速不改变 `load_gnss_rx_capture` 的整文件读入行为；对超大 `single` 文件，仍可能在 Step 1 加载阶段因一次性 `fread(..., inf, ...)` 触发 OOM
- 对 `30 min / 45 min / 60 min` 这类长时正式 BER，优先使用 `chunked` 分析路径，而不是依赖 GPU 去硬扛 `single` 大文件加载

长时 `chunked` 正式 BER 入口：

```matlab
batch_result = run_ber_loopback_chunk_group(CAPTURE_DIR);
```

若只想对单个 chunk 跑同一入口：

```matlab
single_chunk_result = run_ber_loopback_chunk_group(CAPTURE_PATH_1);
```

若只想先做 chunked 快速体检，并支持按 chunk 序号挑选：

```matlab
analysis_result = run_capture_analysis_chunk_group(CAPTURE_DIR);
```

```matlab
analysis_result = run_capture_analysis_chunk_group(CAPTURE_DIR, [1 8 15]);
```

若想专门检查“为什么 IQ 散点不对、为什么 Q 看起来偏大”，可直接运行：

```matlab
iq_diag = run_capture_iq_diagnostic(CAPTURE_PATH_1);
```

也支持不传路径，自动诊断最新一组 capture：

```matlab
iq_diag = run_capture_iq_diagnostic();
```

若想把 `2:15` 号 chunk 挨个跑 BER，并打印每段误码率：

```matlab
ber_seq = run_ber_loopback_chunk_selection(CAPTURE_DIR, 2:15);
```

说明：

- `run_ber_loopback_chunk_group(CAPTURE_DIR)` 会逐个 chunk 执行 `tracked_truth` 并汇总 `aggregate_errors / aggregate_bits / aggregate_ber`
- `run_ber_loopback_chunk_group(CAPTURE_PATH_1)` 会退化成“只分析这一段 chunk”
- `run_ber_loopback_chunk_selection(CAPTURE_DIR, 2:15)` 会按顺序对选中的 chunk 单独跑 BER，并返回每段 `errors / total_bits / ber`
- `run_capture_iq_diagnostic(CAPTURE_PATH_1)` 会生成原始 IQ、去均值 + 去相位后的 IQ、按 sample phase 分组的散点图
- 诊断结果默认写入 `<capture_dir>/analysis/<stem>/iq_diagnostic_*.png` 与 `iq_diagnostic_summary.*`
- `run_capture_analysis_chunk_group(CAPTURE_DIR)` 会先打印目录里一共有多少个 chunk，再逐个调用 `run_capture_analysis(...)`
- `run_capture_analysis_chunk_group(CAPTURE_DIR, [1 8 15])` 只分析指定序号的 chunk
- 推荐正式 GPU 配置：

```matlab
ACCEL_OPTIONS = struct( ...
    'backend', 'gpu', ...
    'precision', 'single', ...
    'batch_ms', 2000);
```

---

## 分析流程说明

`run_capture_analysis` 按以下步骤自动执行：

1. **加载**：读取 `.sc16 + .json` 文件对
2. **绘图**：时域、频谱、IQ 散点总览图（快速检查信号质量）
3. **PRN 捕获**：对 `meta.prn_id` 指定的 PRN 执行 Doppler×码相位二维搜索
4. **多星扫描**：对 PRN1~32 全部做批量搜索，确认信号来源
5. **归档**：保存图片和摘要到 `analysis/<stem>/` 目录

---

## 捕获函数说明

### `run_prn_acquisition`（通用，推荐）

从 `meta.prn_id` 读取目标 PRN（1~32），无效时默认 PRN1：

```matlab
acq_result = run_prn_acquisition(samples, meta, cfg);
% 返回 result.target_prn 字段标记实际搜索的 PRN
```

### `run_prn1_acquisition`（向后兼容封装）

强制目标 PRN=1，内部委托给 `run_prn_acquisition`：

```matlab
acq_result = run_prn1_acquisition(samples, meta, cfg);
```

> 新代码建议使用 `run_prn_acquisition`，通过 `meta.prn_id` 指定目标 PRN。

---

## 捕获与跟踪方法解析

这一节面向“想知道代码具体怎么做”的读者。结论先说：

- 捕获采用 `1 ms` 相干相关，加默认 `10 ms` 非相干累加，执行 `Doppler × 码相位` 二维搜索
- 跟踪链确实存在，结构是“码跟踪 + 载波跟踪 + bit 对齐 + 20 ms 比特积分”
- 码跟踪更像 `DLL-like` 的离散采样点调整，而不是标准连续二阶 DLL
- 载波跟踪采用 `FLL-assisted PLL`，但实现是偏简化、偏诊断型的工程版本

### 总体链路

正式 BER 主链可概括为：

```text
acquisition
  -> code tracking
  -> carrier tracking
  -> bit alignment
  -> bit timing stability check
  -> 20 ms bit integration
  -> BER
```

在 `run_ber_loopback_capture(...)` 中，流程是：

1. 先从整段采集中取前 `0.1 s` 做捕获
2. 用捕获得到的粗 Doppler 和粗码相位初始化 tracking
3. 在 tracking 稳定后做导航 bit 恢复与 BER 统计

因此它不是“只做一次捕获然后开环解调”，而是一条简化接收机链路。

### 捕获方法

`run_prn_acquisition(...)` 的捕获逻辑可以拆成 5 步：

1. 按采样率计算每个 `1 ms` C/A 码周期对应多少采样点
2. 取前 `noncoherent_ms` 个 `1 ms` 片段作为搜索窗口
3. 对每个 Doppler 分格进行去载波
4. 与本地 PRN 码做 FFT 循环相关，得到每个码相位上的相关值
5. 对多个 `1 ms` 相关功率做非相干累加，形成二维搜索图

这里要注意“相干”和“非相干”的边界：

- 单个 `1 ms` 内，代码是在复相关层面完成相关，因此这是 `1 ms` 相干积分
- 多个毫秒之间，代码对 `abs(correlation).^2` 求和，因此这是非相干累加

所以当前默认捕获参数下，真实积分结构是：

- 相干积分时间：`1 ms`
- 非相干累加时间：`10 ms`
- 总搜索维度：`Doppler × code phase`

捕获判决不是单纯取最大峰值，而是使用“主峰 / 次峰比”：

- 先找到全局最大峰值
- 再把主峰附近约 `1 chip` 范围屏蔽掉
- 在剩余区域中找次峰
- 若 `second_peak_ratio >= detection_threshold`，则认为捕获成功

这种做法比单看峰值更稳，能更好区分“真峰”与噪声或旁瓣假峰。

### 跟踪方法

`track_nav_bits(...)` 的跟踪主链分成 5 个阶段。

#### 1. 码跟踪

每 `1 ms`，代码都会生成一段去 Doppler 的输入片段，并分别与：

- `prompt` 本地码
- `early` 本地码
- `late` 本地码

做相关。

然后根据 `early / prompt / late` 的幅度关系，决定下一毫秒是否把码指针调整 `-1 sample / +1 sample / 0`。

这说明当前实现虽然遵循 DLL 思想，但它不是经典连续环路滤波器结构，而更像：

- 基于 `early-late` 判决的离散 cursor 调整
- 每次调整量固定为 `1 sample`
- 每隔一定时间，或者锁定度下降时，再做一次局部小范围码相位重搜

这个“局部重搜”只在当前估计点附近扫描 `±code_search_half_span_samples`，目的是避免整段重新 acquisition 的高成本。

#### 2. 载波跟踪

载波跟踪在 prompt 相关序列上完成，分两步：

1. `FLL`：对 `prompt_ms^2` 的相邻相位差求频偏估计，并做滑动平均平滑
2. `PLL`：在 FLL 初步拉稳后，再用比例型 PLL 修正剩余相位误差

这就是典型的 `FLL-assisted PLL` 思路：

- FLL 解决“相位一直旋转、频率还没稳住”的问题
- PLL 解决“频率基本对了，但点云还没贴近实轴”的问题

需要注意的是，这里的 PLL 实现比较简化，只有比例更新，没有完整高阶环路滤波器参数设计，因此更适合作为离线 BER 分析链，而不是严格 textbook 版接收机环路。

#### 3. 初始 bit 对齐

tracking 稳住后，代码不会直接盲判导航 bit，而是借助 truth：

- 在前 `alignment_training_ms` 的训练段上
- 遍历 `20` 种可能的 bit 边界
- 同时搜索 pattern 偏移和极性
- 选择匹配率最高的组合作为初始 bit 对齐结果

因此这里的 bit 恢复是“tracking + truth-assisted alignment”，不是完全盲恢复。

#### 4. bit 时序稳定性检查

初始 bit 对齐不代表整段采集都一直对齐。代码会定期在滑动窗口中比较：

- 当前 bit offset 的积分能量
- 局部最优 bit offset 的积分能量

如果当前边界明显不如局部最优边界，就记录 `bit_timing_watch` 事件，用于诊断 overflow、慢性漂移或重同步问题。

#### 5. 20 ms 比特积分

GPS L1 C/A 导航数据是 `20 ms / bit`。因此在最终判 bit 时，代码会把连续 `20` 个 `1 ms prompt` 相关结果积分成 1 个导航 bit 相关值，再做符号判决。

所以导航比特阶段的有效积分时间是：

- `20 ms / bit`

### 捕获参数表

| 参数 | 默认值 | 含义 | 调大/调小的典型影响 |
|------|--------|------|----------------------|
| `noncoherent_ms` | `10` | 非相干累加毫秒数 | 调大更灵敏但更慢；调小更快但弱信号更难捕获 |
| `doppler_min_hz` | `-10000` | Doppler 搜索下限 | 过窄可能漏检，过宽会增加计算量 |
| `doppler_max_hz` | `10000` | Doppler 搜索上限 | 同上 |
| `doppler_step_hz` | `500` | Doppler 搜索步长 | 更小更精细但更慢；更大更快但粗糙 |
| `detection_threshold` | `2.5` | 主峰/次峰比门限 | 调高更保守，调低更容易误检 |

当前默认值偏向“先跑通、先出结果”。实际联调时，最常改的通常是：

- `noncoherent_ms`
- `doppler_min_hz / doppler_max_hz`
- `doppler_step_hz`

### 跟踪参数表

| 参数 | 默认值 | 含义 | 典型影响 |
|------|--------|------|----------|
| `min_required_ms` | `200` | 至少需要多少 ms 才进入 tracking | 太短会直接报错 |
| `early_late_spacing_samples` | `1` | early / late 与 prompt 的间隔 | 影响码跟踪灵敏度与稳健性 |
| `code_switch_ratio` | `1.015` | 触发 `±1 sample` 码调整的门限 | 越低越敏感，越高越保守 |
| `code_search_interval_ms` | `100` | 周期性局部码重搜间隔 | 越短越积极，越长越省算力 |
| `code_search_half_span_samples` | `8` | 局部码重搜半宽 | 越大越能纠正较大偏移，但开销更大 |
| `code_lock_threshold` | `0.08` | 码锁定质量门限 | 太高易误判失锁，太低则不敏感 |
| `fll_smooth_ms` | `50` | FLL 平滑窗口长度 | 越大越稳，越小响应越快 |
| `pll_gain` | `0.08` | PLL 比例增益 | 越大响应快但更易抖动，越小更稳但更慢 |
| `alignment_training_ms` | `2000` | 初始 bit 对齐训练长度 | 越长越稳但更慢 |
| `bit_timing_check_interval_ms` | `1000` | bit 时序检查周期 | 越短越敏感 |
| `bit_timing_check_span_ms` | `2000` | 每次 bit 时序检查窗口 | 越大统计更稳，越小更灵活 |
| `bit_timing_realign_margin` | `1.05` | 判定局部最优边界更优的门限 | 越大越保守 |
| `window_ber_bits` | `100` | 局部 BER 窗口大小 | 影响 BER 曲线平滑度 |
| `fll_jump_threshold_hz` | `10.0` | FLL 突变判据 | 用于检测 overflow / 失锁起点 |
| `bit_match_rate_threshold` | `0.9` | bit 时序有效性门限 | 越高越严格 |

### 最重要的两个问题

#### 1. 相干积分时间是多少？

分阶段看：

- 捕获阶段：`1 ms` 相干积分
- 捕获阶段默认累加：`10 ms` 非相干累加
- 导航 bit 阶段：`20 ms` 积分形成 1 个 bit

因此如果你问“当前 acquisition 的 coherent integration time 是多少”，答案是：

- `1 ms`

如果你问“当前 acquisition 总共积了多久”，默认答案是：

- `10 × 1 ms` 的非相干累加

#### 2. 是否使用了跟踪环？

答案是“使用了”，但要准确描述：

- 码跟踪：是 `DLL-like` 结构，基于 `early/prompt/late` 做离散 sample 级调整
- 载波跟踪：是 `FLL-assisted PLL`
- bit 级处理：还有额外的 bit 边界检查与失锁质量判定

因此它不是纯 open-loop 流程。

但同时也要看到，它并不是完整 textbook 版的高阶 GNSS tracking loop，而是更偏向：

- 便于离线分析
- 便于 BER 诊断
- 便于观察失锁/重同步事件

的一套简化工程实现。

### 一句话结论

这套 MATLAB 代码整体更像“用于离线 BER 与诊断的简化 GPS L1 C/A 接收机”：

- acquisition 是标准的 FFT 二维搜索
- code tracking 是离散 `DLL-like`
- carrier tracking 是简化的 `FLL + PLL`
- bit 恢复依赖 truth 做监督式对齐

如果你的目标是“理解当前代码到底有没有接收机式 tracking”，答案是明确的：有。

---

## 输出结果

分析产物写入：`<capture_date_dir>/analysis/<stem>/`

| 文件 | 说明 |
|------|------|
| `overview_time.png` | 时域波形图 |
| `overview_spectrum.png` | 频谱图 |
| `iq_scatter.png` | IQ 散点图 |
| `iq_diagnostic_compare.png` | 原始 IQ 与去均值 + 去相位后 IQ 的对比图 |
| `iq_diagnostic_sample_phase.png` | 按 sample phase 分组的 IQ 散点图 |
| `prn<N>_acquisition.png` | 目标 PRN 的二维捕获搜索图 |
| `multi_prn_survey.png` | PRN1~32 次峰比柱状图 |
| `analysis_summary.json` | 分析摘要（JSON） |
| `analysis_summary.mat` | 分析摘要（MAT） |
| `iq_diagnostic_summary.json` | IQ 诊断摘要（JSON） |
| `iq_diagnostic_summary.mat` | IQ 诊断摘要（MAT） |

### 多星捕获对比图（multi_prn_survey.png）

- X 轴：PRN 编号（1~32）
- Y 轴：次峰比（peak / second_peak）
- 绿色柱：捕获成功（次峰比 ≥ 2.5）
- 蓝色柱：未捕获
- 红色虚线：判决门限（默认 2.5）

当接收端收到目标 PRN 信号时，对应柱子应明显高于阈值线；其余 PRN 通常接近 1.0 噪底。

---

## 常用联调流程

从头走完整条链路（无硬件）：

```bash
# Ubuntu 中生成合成数据并同步 MATLAB 代码
cd /home/shenao/projects/GNSS_RX
PYTHONPATH=/home/shenao/projects/gnss_tx/src:src \
    python3 scripts/gen_synthetic_capture.py --snr-db 10 --duration 2
/home/shenao/projects/GNSS_RX/scripts/sync_matlab.sh \
    ~/GNSS_RX_matlab_share
```

```matlab
% MATLAB 中运行分析
run_capture_analysis
```

从真实采集走完整链路：

```bash
PYTHONPATH=src python3 scripts/record_rx.py --config configs/rx_prn1_capture.yaml
/home/shenao/projects/GNSS_RX/scripts/sync_matlab.sh \
    ~/GNSS_RX_matlab_share
```
