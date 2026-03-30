# GNSS_RX 接收机实现说明

## 目标

`GNSS_RX` 负责录制原始零中频采集数据，并将其交给 MATLAB，对同级
`gnss_tx` 项目发射的单星 GPS L1 C/A 信号执行离线捕获。

v1 链路如下：

```
USRP source -> zero-IF complex samples -> SC16 writer -> JSON sidecar
```

## 为什么选择原始 SC16 + JSON

- `SC16` 符合常见 SDR 样本表示方式，同时能控制文件体积（相比 fc32 减少 50%）。
- JSON 伴随文件免去在 MATLAB 中手动录入 `sample_rate`、`center_freq` 等参数。
- 约定刻意保持最小，后续可以在不破坏第一版 MATLAB 工作流的前提下，逐步扩展到 `SigMF`、`fc32` 或更丰富的实验元数据。

---

## 模块实现说明

### `src/gnss_rx/runtime.py` — 运行时配置

**核心类：`RxRuntimeConfig`（frozen dataclass）**

所有采集参数汇聚于此，字段列表：

| 字段 | 默认值 | 说明 |
|------|--------|------|
| `usrp_addr` | `"type=b200"` | UHD 设备地址字符串，支持 `type=`、`serial=`、`addr=` 等 |
| `center_freq_hz` | `100e6` | 中心频率（Hz） |
| `sample_rate_hz` | `4.092e6` | 采样率（Hz），与 GPS L1 C/A chip rate 4× 对齐 |
| `rx_gain_db` | `20.0` | 接收增益（dB） |
| `bandwidth_hz` | `None` | RF 带宽（Hz），`None` 时 YAML 加载自动取 `sample_rate_hz` |
| `antenna` | `"RX2"` | 天线端口名称 |
| `duration_s` | `2.0` | 录制时长（秒） |
| `output_base_dir` | 共享目录 | 可由 `GNSS_RX_DATA_DIR` 环境变量覆盖 |
| `use_timestamped_stem` | `True` | 是否自动生成时间戳文件名 |
| `output_stem` | `None` | 手动指定文件 stem（优先级高于时间戳） |
| `clock_source` | `"internal"` | UHD 时钟源，双 USRP OTA 时可改为 `"external"` |
| `time_source` | `"internal"` | UHD 时间源 |
| `signal_mode` | `"spread"` | 信号模式，`spread`（扩频）或 `tone`（单音） |
| `prn_id` | `1` | PRN 编号，当前支持 `1~32` |
| `tx_profile_reference` | 相对路径 | 对应发射端配置文件的引用路径（仅记录，不做解析） |

**`validate()` 方法**：对所有字段做范围和逻辑校验，返回 `self`。不合法时抛出 `ValueError`。

**`capture_samples` 属性**：`int(round(sample_rate_hz * duration_s))`，用于 `head` 块截断。

**`load_rx_runtime_config(path)`**：读取 YAML，若 YAML 未显式给出 `bandwidth_hz` 则自动设为 `sample_rate_hz`，再调用 `validate()`。

> [!NOTE]
> 设计说明：为什么缺省将 `bandwidth_hz` 设为 `sample_rate_hz`（而不是默认调大）
>
> - 这是一个“可运行且可预测”的安全默认值。若不显式设置带宽，不同 UHD/驱动版本的默认行为可能不一致。
> - 对当前零中频采集链路，数字可观测频带受采样率限制；把模拟前端带宽无条件调大，通常不会带来同等信息增益。
> - 噪声功率近似随带宽线性增长（`P_n = kTB`），默认调大带宽会抬升噪声底，可能降低后续捕获稳健性。
> - 更宽的前端带宽更容易引入邻道干扰与杂散，增加 acquisition 伪峰或次峰比恶化风险。
> - 因此 v1 默认采用“`bandwidth_hz ~= sample_rate_hz`”作为基线；需要做抗干扰/滤波优化时，再通过 YAML 或 CLI 显式覆盖。

**`apply_overrides(config, **overrides)`**：命令行参数覆盖 YAML 值，仅非 `None` 的字段生效，同步更新 `bandwidth_hz` 联动。

**文件 stem 生成 — `build_timestamped_capture_stem(config, when)`**：

```
<YYYYMMDD_HHMMSS>_rawiq_sc16_zeroif_prn<id>_<mode>_sr<rate>_cf<freq>_dur<dur>s
```

示例：`20260325_143000_rawiq_sc16_zeroif_prn1_spread_sr4092000_cf100000000_dur2p0s`

浮点数字段通过 `format_capture_tag()` 压缩：整数去小数点，小数将 `.` 替换为 `p`、负号替换为 `m`。

**输出路径 — `resolve_output_stem_path()`**：

```
<output_base_dir>/<YYYY>/<YYYY_MM_DD>/<stem>/<stem>
```

stem 在路径中出现两次（目录名 + 文件 stem），这是设计约定。

**`resolve_capture_paths()`**：返回 `(stem.sc16, stem.json)` 元组。

---

### `src/gnss_rx/writer.py` — SC16 写文件模块

**`complex_to_sc16_interleaved(samples)`**：

1. 将输入强制转为 `np.complex64`
2. 实部/虚部各自 `clip` 到 `[-1.0, 1.0]`
3. 乘以 `SC16_SCALE = 32767.0` 并四舍五入
4. 交织排列为 `[I0, Q0, I1, Q1, ...]`，dtype `int16`

**`write_sc16_file(path, samples)`**：一次性将全部样本转换后以 little-endian `int16` 写盘，用于合成数据生成。返回写入的样本数。

**`Sc16CaptureSink(gr.sync_block)`**：GNU Radio sink 块，在 flowgraph 运行期间流式写文件：

- `__init__`: 打开文件（`wb` 模式），在 GNU Radio 可用时注册为 `sync_block`（输入信号 `np.complex64`，无输出信号）。
- `work(input_items, output_items)`: 每次被调度时接收一批样本，调用 `complex_to_sc16_interleaved()` 转换后写盘，累加 `samples_written` 计数。
- `close()`: 刷新并关闭文件句柄（flowgraph 停止后由 `record_rx.py` 显式调用）。

---

### `src/gnss_rx/flowgraph.py` — GNU Radio 流图

**设备检测辅助函数**：

- `uhd_find_devices_output()`: 运行 `uhd_find_devices` 子进程，返回 stdout + stderr 合并字符串。
> [!TIP]
> `stdout`（standard output）是标准输出，通常承载正常结果；`stderr`（standard error）是标准错误输出，通常承载告警与错误信息。
- `is_uhd_device_available()`: 解析上述输出，判断是否有可用设备（过滤 `"no uhd devices found"` 字样）。

**`create_usrp_source(config)`**：

调用 `uhd.usrp_source()`，参数来自 `RxRuntimeConfig`：

- OTW 格式 `sc16`（过空口传输格式），CPU 格式 `fc32`（Python 侧处理格式）
- 通道 `[0]`（单通道）
- 设置中心频率、采样率、增益、天线、带宽（若有）
- 设置时钟源和时间源（兼容新旧 UHD API 的 `TypeError` 差异）

**`ZeroIfCaptureTopBlock(gr.top_block)`**：

```
usrp_source -> blocks.head(sizeof_gr_complex, capture_samples) -> Sc16CaptureSink
```

- `source`: 由 `create_usrp_source()` 创建，或由测试注入 mock source
- `head`: 截断到精确的 `capture_samples` 个样本后自动停止流图
- `writer_sink`: `Sc16CaptureSink` 实例

支持依赖注入（`source_block` / `writer_sink` 参数），便于单元测试绕开硬件。

**`build_capture_top_block(config, output_path, source_block)`**：工厂函数，返回 `(tb, sink)` 元组。

---

### `src/gnss_rx/metadata.py` — 捕获元数据

**`CaptureMetadata`（frozen dataclass）**：

记录一次采集的完整交接信息，字段：

| 字段 | 说明 |
|------|------|
| `sample_format` | 固定 `"sc16"` |
| `complex_layout` | 固定 `"iq_int16_interleaved_le"` |
| `sample_rate_hz` | 实际采样率 |
| `center_freq_hz` | 中心频率 |
| `duration_s` | 录制时长 |
| `samples_captured` | 实际写入样本数（来自 sink） |
| `rx_gain_db` | 接收增益 |
| `bandwidth_hz` | RF 带宽（可为 null） |
| `antenna` | 天线端口 |
| `usrp_addr` | 设备地址 |
| `zero_if` | 始终为 `true` |
| `signal_mode` | `"spread"` 或 `"tone"` |
| `prn_id` | PRN 编号 |
| `tx_profile_reference` | 对应发射端配置路径 |
| `data_file` | 仅文件名，不含路径 |

**`build_capture_metadata(config, *, samples_captured, data_path)`**：从 config + 实测 samples_captured 组装 metadata。

**`write_metadata_json(path, metadata)`**：`json.dumps(asdict(metadata), indent=2, sort_keys=True)` 写 UTF-8 文件。字段按字母排序，便于 diff 和人工核查。

---

### `src/gnss_rx/utils/io.py` — I/O 工具

**`load_yaml_file(path)`**：`yaml.safe_load` 加载，校验顶层为 `dict` 结构，空文件返回 `{}`。

---

### `scripts/record_rx.py` — 采集入口 CLI

**命令行参数**：

| 参数 | 说明 |
|------|------|
| `--config` | YAML 配置文件路径（默认 `configs/rx_prn1_capture.yaml`） |
| `--prn-id` | 覆盖目标 PRN 编号（支持 1~32） |
| `--center-freq` | 覆盖中心频率（Hz） |
| `--sample-rate` | 覆盖采样率（Hz） |
| `--rx-gain` | 覆盖接收增益（dB） |
| `--bandwidth` | 覆盖 RF 带宽（Hz） |
| `--duration` | 覆盖录制时长（秒） |
| `--output-base-dir` | 覆盖输出根目录 |
| `--output-stem` | 手动指定文件 stem（跳过自动时间戳） |
| `--dry-run` | 仅打印计划，不启动 USRP |

**执行流程**：

1. 加载 YAML 配置 → 叠加 CLI 覆盖 → 校验
2. 打印采集报告（所有参数、输出路径）
3. 运行 `uhd_find_devices`，打印原始输出
4. 打印 MATLAB 交接摘要（MATLAB 需要的关键字段列表）
5. 若 `--dry-run`：退出（返回 0）
6. 检查 UHD 绑定和设备可用性；不可用则退出（返回 1）
7. 创建输出目录，构建并运行 flowgraph
8. 关闭 sink，写 JSON 元数据

---

### `scripts/gen_synthetic_capture.py` — 合成数据生成器

在无硬件条件下生成与真实采集格式完全一致的 `.sc16 + .json` 文件对，用于验证 MATLAB 捕获算法。

**信号生成流程**：

1. 调用 `gnss_tx.signal.spreader.GpsL1CaBpskGenerator(prn_id=1, samples_per_chip, amplitude)` 生成纯净 PRN1 BPSK 基带信号（仅 I 支路，Q 恒为 0）；当前合成脚本仍固定使用 PRN1
2. 叠加复数 AWGN：`noise_power = signal_power / snr_linear`，实部虚部各为 `N(0, noise_power/2)`
3. 输出文件 stem 末尾追加 `_synthetic` 标签，与真实采集区分
4. 调用 `write_sc16_file()` 落盘，构建 `CaptureMetadata`（`usrp_addr="synthetic"`, `antenna="synthetic"`），写 JSON

**依赖**：需要将 `gnss_tx/src` 加入 `PYTHONPATH`。

---

### `matlab/` — 离线分析工作区

**入口：`scripts/run_capture_analysis.m`**

自动把 `functions/` 加入 MATLAB path，按以下顺序执行：

1. `gnss_rx_resolve_data_dir()` — 解析数据根目录（优先级：`gnss_rx_user_paths.m` > `GNSS_RX_DATA_DIR` 环境变量 > 平台默认路径）
2. `find_latest_capture(root)` — 递归搜索最新 `.sc16`（跳过 `analysis/` 子目录）
3. `load_gnss_rx_capture(path)` — 读取 `.json` 元数据，按交织 `int16` 方式加载 `.sc16`，转换为 `complex64` 基带样本
4. `plot_capture_overview(samples, meta, paths, cfg)` — 生成时域图、频谱图（65536 点 FFT）和 IQ 散点图
5. `run_prn1_acquisition(samples, meta, cfg)` — 带 Doppler 搜索的 PRN1 捕获（搜索范围 ±10 kHz，步长 500 Hz，10 ms 非相干累加）
6. `run_multi_prn_survey(samples, meta, cfg)` — PRN1~32 批量搜索，返回次峰比数组
7. `plot_multi_prn_survey(survey, paths, cfg)` — 绘制多星次峰比柱状图
8. `save_analysis_artifacts(meta, paths, figures, acq_result, cfg)` — 保存 PNG、JSON 摘要、MAT 结果到 `<date_dir>/analysis/<stem>/`

**捕获判决**：次峰比（peak / second_peak）≥ 2.5（`detection_threshold`）视为捕获成功。

---

## 数据格式约定

### `.sc16` 文件

- 格式：原始二进制，无文件头
- 数据类型：little-endian signed int16
- 排列：`I0, Q0, I1, Q1, ...`（交织）
- 量化范围：`[-32767, 32767]`，对应归一化 `[-1.0, 1.0]`

### `.json` sidecar 文件

```json
{
  "antenna": "RX2",
  "bandwidth_hz": 4092000.0,
  "center_freq_hz": 100000000.0,
  "complex_layout": "iq_int16_interleaved_le",
  "data_file": "20260325_143000_rawiq_sc16_zeroif_prn7_spread_sr4092000_cf100000000_dur2p0s.sc16",
  "duration_s": 2.0,
  "prn_id": 7,
  "rx_gain_db": 20.0,
  "sample_format": "sc16",
  "sample_rate_hz": 4092000.0,
  "samples_captured": 8184000,
  "signal_mode": "spread",
  "tx_profile_reference": "../gnss_tx/configs/tx_b210_visible_spectrum.yaml",
  "usrp_addr": "type=b200",
  "zero_if": true
}
```

### 输出路径结构

```
<output_base_dir>/
└── <YYYY>/
    └── <YYYY_MM_DD>/
        └── <stem>/
            ├── <stem>.sc16
            └── <stem>.json
```

stem 命名示例：
```
20260325_143000_rawiq_sc16_zeroif_prn7_spread_sr4092000_cf100000000_dur2p0s
```

---

## 运行数据流

```
[CLI] record_rx.py
   │  读取 YAML → apply_overrides() → validate()
   │  resolve_capture_paths() → (data_path, metadata_path)
   │  打印采集报告 + MATLAB 交接摘要
   │
   ├─[dry-run] 退出
   │
   └─[正式采集]
       │
       ├── build_capture_top_block()
       │     create_usrp_source()         → uhd.usrp_source(fc32, sc16, ch=0)
       │     blocks.head(capture_samples) → 截断采样数量
       │     Sc16CaptureSink(data_path)   → 流式写 .sc16
       │
       ├── tb.run()                        → GNU Radio 调度运行直到 head 截断
       ├── sink.close()                    → 刷盘
       │
       └── build_capture_metadata()
           write_metadata_json()           → 写 .json
```

## 当前已实现能力

- 单通道 USRP/UHD 零中频采集
- 通过 GNU Radio flowgraph 将复数基带样本限制到固定采集时长
- 将采集结果写成原始交织 SC16 IQ 文件
- 为同一次采集生成配套 JSON sidecar
- 默认导出到 VMware 共享目录，便于宿主机 MATLAB 直接读取
- 自动生成带时间戳和关键采集参数标签的文件 stem
- CLI 提供 dry-run、设备发现输出和 MATLAB 交接摘要
- 无硬件合成信号生成（gen_synthetic_capture.py），用于算法验证
- MATLAB 离线分析链：加载、绘图、PRN1 详细捕获、多星搜索、结果归档

## 当前未实现能力

- 不实现完整 GNSS 接收机链路（无 tracking、无导航解算）
- 不做实时 acquisition 或多 PRN 并行采集
- 当前元数据、文件命名和运行时校验支持 `PRN1~32`
- MATLAB 的单 PRN 详细二维捕获入口仍固定为 `PRN1`
- 不包含 MATLAB 算法本体的在线推断部分

## 验证覆盖

| 测试文件 | 验证内容 |
|----------|----------|
| `test_runtime.py` | capture_samples 计算、YAML 加载带宽默认推导、路径生成格式、stem 格式、output_stem 覆盖 |
| `test_record_rx.py` | dry-run 打印采集配置、路径和 MATLAB 摘要 |
| `test_writer.py` | complex→SC16 顺序与裁剪、little-endian 交织写盘格式 |
| `test_metadata.py` | JSON sidecar 关键字段完整性 |
| `test_flowgraph.py` | GNU Radio 可用时 top block 从向量源采集并写出样本 |
| `test_runtime.py` | 参数校验边界（负增益、空天线、非法 PRN 等） |

## 后续扩展点

- 将 MATLAB 的单 PRN 详细二维捕获入口从 `PRN1` 泛化到任意目标 PRN
- 增加 SigMF 或更丰富的实验元数据
- 在不破坏主录制路径的前提下增加预览、实时频谱或在线 acquisition 分支
- 引入更强的结果归档与实验记录机制
