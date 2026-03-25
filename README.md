# GNSS_RX

`GNSS_RX` 是现有 `gnss_tx` 发射机工作区的配套接收机项目。

它的 v1 目标刻意保持精简：

- 从兼容 UHD 的 USRP 采集单通道零中频记录
- 存储原始交织的 `SC16` IQ 样本
- 生成 MATLAB 可直接读取的 JSON 伴随文件，避免手工重复录入参数
- 支持对已发射的 `GPS L1 C/A PRN1` 信号进行离线捕获

## 项目范围

本仓库并不实现完整的 GNSS 接收机，目前聚焦于：

- 空口单星信号录制
- 面向离线验证的原始文件采集
- 与 `gnss_tx` 在协议层面的对齐

当前发射端 / 接收端约定如下：

- `center_freq_hz = 100e6`
- `sample_rate_hz = 4.092e6`
- `signal_mode = spread`
- `prn_id = 1`
- 文件输出：`/mnt/hgfs/GongXiangDocument/GNSS_RX_Data/<YYYY>/<YYYY-MM-DD>/<stem>.sc16` + `<stem>.json`

默认 stem 命名格式为：

`<YYYYMMDD_HHMMSS>_rawiq_sc16_zeroif_prn<id>_<signal_mode>_sr<sample_rate_hz>_cf<center_freq_hz>_dur<duration_s>s`

## 首次配置

### 1. 设置数据根目录（必须）

复制路径模板，填入本地实际路径：

```bash
cp matlab/gnss_rx_user_paths.m.example matlab/gnss_rx_user_paths.m
# 用编辑器打开 matlab/gnss_rx_user_paths.m，将 GNSS_RX_DATA_DIR 改为实际数据目录
```

该目录存放 `.sc16 + .json` 采集文件对，MATLAB 和 Python 均从此处读写数据。

Python 侧等效方式（或修改 `configs/` 中的 `output_base_dir` 字段）：

```bash
export GNSS_RX_DATA_DIR=/your/data/path
```

### 2. 同步 MATLAB 代码到共享文件夹（仅 MATLAB 运行在宿主机时需要）

```bash
./scripts/sync_matlab.sh /mnt/hgfs/GongXiangDocument/GNSS_RX_matlab
```

宿主机 MATLAB 打开对应的 Windows 路径（如 `C:\VMwareVirtualMachines\GongXiangDocument\GNSS_RX_matlab`）即可使用。每次在 VM 中修改 MATLAB 代码后重新运行此命令。

### 3. 目录布局约定

`gnss_tx` 和 `GNSS_RX` 应为兄弟目录，`tx_profile_reference` 使用相对路径 `../gnss_tx/` 引用 TX 配置：

```
projects/
├── gnss_tx/
└── GNSS_RX/
```

---

## 快速开始

对当前接收配置做一次 dry-run：

```bash
PYTHONPATH=src python3 scripts/record_rx.py --dry-run
```

录制一段短时零中频采集：

```bash
PYTHONPATH=src python3 scripts/record_rx.py \
  --config configs/rx_prn1_capture.yaml \
  --duration 2
```

运行测试集：

```bash
PYTHONPATH=src python3 -m unittest discover -s tests -v
```

## 软件回环验证（无需硬件）

在天线或线缆回环到位之前，可以用合成信号来验证捕获算法是否正确工作。

### 第一步：生成合成 PRN1 采集文件

```bash
cd /home/shen/projects/GNSS_RX
PYTHONPATH=/home/shen/projects/gnss_tx/src:src \
  python3 scripts/gen_synthetic_capture.py \
    --config configs/rx_prn1_sn193982.yaml \
    --snr-db 10 \
    --duration 2
```

脚本会在共享目录下生成一对文件（stem 末尾带 `_synthetic` 标签），格式与真实 USRP 采集完全一致。

可选参数：

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `--snr-db` | 10 | 信噪比（dB），降低到 0 或 -5 可测试算法鲁棒性 |
| `--duration` | 2.0 | 信号时长（秒） |
| `--amplitude` | 1.0 | BPSK 幅度 |
| `--output-base-dir` | 配置文件中读取 | 覆盖输出根目录 |

### 第二步：MATLAB 离线分析

在 MATLAB 中运行（自动分析共享目录下最新文件）：

```matlab
result = run_capture_analysis();
```

### 预期结果

- **多星搜索图**（`multi_prn_survey.png`）：PRN1 柱子明显高于红色阈值线（次峰比 ≥ 2.5），PRN2~32 接近 1.0（噪底）
- **捕获结果**：`detected = true`，控制台打印 `捕获结果：成功`

若 PRN1 柱子未超过阈值，可尝试提高 `--snr-db`（如 20）或增加非相干累加时长 `--duration 5`。

### 后续硬件验证（线缆回环）

天线到位后，推荐先做有线回环（无需对准方向）：

```
TX/RX 端口 → 30~50 dB SMA 衰减器 → RX2 端口
```

预期与软件回环结果一致：PRN1 捕获成功，其余 PRN 无明显峰值。

---

## 目录结构

- `configs/`：接收端 YAML 配置，包括共享目录导出根路径
- `docs/`：采集链路与实验流程说明
- `matlab/`：宿主机 MATLAB 离线加载、绘图与 PRN1 acquisition 工作区
- `scripts/`：CLI 入口脚本
- `src/gnss_rx/`：运行时配置、元数据、GNU Radio 组装和写文件逻辑
- `tests/`：单元测试与轻量集成测试
- `results/`：采集输出目录
- `experiments/`：接收实验记录与日志
