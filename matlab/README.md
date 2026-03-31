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

---

## 架构图

| 文件 | 说明 |
|------|------|
| `architecture.drawio` | `run_capture_analysis` 主链：加载、总览、PRN 捕获、多星扫描、归档 |
| `ber_loopback.drawio` | `run_ber_loopback` 诊断链：truth 读取、open-loop 基线、tracked BER 主链 |

---

## 快速开始

### 1. 配置数据目录

```bash
# 复制模板
cp /home/shen/projects/GNSS_RX/matlab/gnss_rx_user_paths.m.example \
   /home/shen/projects/GNSS_RX/matlab/gnss_rx_user_paths.m
```

在 `gnss_rx_user_paths.m` 中填写实际数据目录：

```matlab
% Windows 宿主机（VMware 共享目录）
GNSS_RX_DATA_DIR = 'C:\VMwareVirtualMachines\GongXiangDocument\GNSS_RX_Data';

% 或 Linux 本机
GNSS_RX_DATA_DIR = '/mnt/hgfs/GongXiangDocument/GNSS_RX_Data';
```

### 2. 同步 MATLAB 代码到宿主机（MATLAB 在 Windows 时）

`GNSS_RX/matlab/` 是 MATLAB 代码的唯一真相源。
`/mnt/hgfs/GongXiangDocument/GNSS_RX_matlab` 仅作为宿主机 MATLAB 的部署镜像，不应手工修改。
同步脚本会保留共享根目录中的运行期文件，例如 `tx_truth.json`。
采集目录中的 sidecar truth（如 `<capture_stem>_tx_truth.json`）属于数据，不属于 MATLAB 代码镜像，不会由同步脚本搬运。

```bash
# 推荐：通过脚本镜像同步整个工作区
/home/shen/projects/GNSS_RX/scripts/sync_matlab.sh \
    /mnt/hgfs/GongXiangDocument/GNSS_RX_matlab
```

同步结果包含：

- `functions/`
- `scripts/`
- `README.md`
- 根目录快捷入口脚本 `ber.m`

每次 Ubuntu 端修改 MATLAB 代码后，统一执行上面的同步命令；随后在主力机 MATLAB 中执行：

```matlab
which ber -all
which run_ber_loopback -all
which load_tx_truth_json -all
```

要求这些路径都指向刚同步的 `GNSS_RX_matlab` 部署目录。

### 3. 在 MATLAB 中运行分析

**Windows 宿主机 MATLAB：**

```matlab
cd('C:\VMwareVirtualMachines\GongXiangDocument\GNSS_RX_matlab')
result = run_capture_analysis();          % 自动分析最新文件
```

**Linux 本机 MATLAB：**

```matlab
cd('/home/shen/projects/GNSS_RX/matlab')
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

**Windows 宿主机 MATLAB：**

```matlab
cd('C:\VMwareVirtualMachines\GongXiangDocument\GNSS_RX_matlab')
clear functions
rehash

CAPTURE_PATH = ['F:\GNSS_RX_Data_baremetal\2026\2026_03_30\' ...
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
% Windows 宿主机
result = run_capture_analysis( ...
  'C:\VMwareVirtualMachines\GongXiangDocument\GNSS_RX_Data\2026\2026_03_26\<stem>\<stem>');

% Linux VM
result = run_capture_analysis( ...
  '/mnt/hgfs/GongXiangDocument/GNSS_RX_Data/2026/2026_03_26/<stem>/<stem>');
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

## 输出结果

分析产物写入：`<capture_date_dir>/analysis/<stem>/`

| 文件 | 说明 |
|------|------|
| `overview_time.png` | 时域波形图 |
| `overview_spectrum.png` | 频谱图 |
| `iq_scatter.png` | IQ 散点图 |
| `prn<N>_acquisition.png` | 目标 PRN 的二维捕获搜索图 |
| `multi_prn_survey.png` | PRN1~32 次峰比柱状图 |
| `analysis_summary.json` | 分析摘要（JSON） |
| `analysis_summary.mat` | 分析摘要（MAT） |

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
cd /home/shen/projects/GNSS_RX
PYTHONPATH=/home/shen/projects/gnss_tx/src:src \
    python3 scripts/gen_synthetic_capture.py --snr-db 10 --duration 2
/home/shen/projects/GNSS_RX/scripts/sync_matlab.sh \
    /mnt/hgfs/GongXiangDocument/GNSS_RX_matlab
```

```matlab
% MATLAB 中运行分析
run_capture_analysis
```

从真实采集走完整链路：

```bash
PYTHONPATH=src python3 scripts/record_rx.py --config configs/rx_prn1_capture.yaml
/home/shen/projects/GNSS_RX/scripts/sync_matlab.sh \
    /mnt/hgfs/GongXiangDocument/GNSS_RX_matlab
```
