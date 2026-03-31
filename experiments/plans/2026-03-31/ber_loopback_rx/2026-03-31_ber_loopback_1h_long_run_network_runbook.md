# 联机 1 h 长时稳定性验证与局域网回传手册

> 创建时间：2026-03-31
> 适用场景：Ubuntu 裸机采集机与 Windows MATLAB 主机在同一局域网；`1 h` 阶段不再使用移动硬盘，而是采后通过局域网回传到 Windows 本地 SSD
> 本文件定位：`1 h` 长时稳定性验证的主手册；总手册只保留摘要与跳转
> 关联文件：
> - `experiments/plans/2026-03-31/ber_loopback_rx/2026-03-31_ber_loopback_end_to_end_joint_runbook.md`
> - `docs/lan_data_sharing_setup.md`
> - `docs/windows_matlab_code_sync_samba.md`

---

## 一、这份手册解决什么问题

`1 h` 长时验证和 `30 s / 100 s / 250 s` 最大的区别，不只是时间更长，而是**采集、回传、分析三件事都会被总数据量放大**。

当前 `1 h @ 4.092 Msps` 的原始 IQ 总量约为：

- 约 `58.9 GB` 十进制
- 约 `54.9 GiB` 二进制

因此，这一阶段默认不再推荐：

- 直接生成单个超大 `.sc16`
- 采集中直接写网络共享目录
- 采后直接在网络盘上跑正式 MATLAB BER

本手册固定采用下面这条主路径：

```text
Ubuntu 本地 chunked 采集
→ 采后确认 120 段 chunk 完整
→ Windows 通过 SSHFS-Win 只读挂载 Ubuntu 数据目录
→ robocopy 镜像到 Windows 本地 SSD
→ MATLAB 从 Windows 本地 SSD 抽查前/中/后 chunk
```

一句话口径：

```text
采集必须先落 Ubuntu 本地磁盘；局域网只负责采后回传；正式 MATLAB 优先从 Windows 本地 SSD 跑。
```

---

## 二、先看这个关键限制

### 2.1 当前机器磁盘空间不足以直接承载完整 1 h

你当前贴出的 `df -h` 显示 `/` 分区可用空间约为 `44G`。

而本轮 `1 h chunked` 总数据量约为 `58.9 GB`，这意味着：

- 即使使用 `chunked`
- 即使每段只有约 `0.49 GB`
- **总落盘量仍然会超过当前 `/` 分区可用空间**

因此，在当前机器状态下，下面两件事必须至少满足其一，才能真正执行 `1 h`：

1. 先释放足够空间，让 `output_base_dir` 所在文件系统可用空间至少达到 `70 GB` 左右
2. 把 `output_base_dir` 切换到 Ubuntu 侧另一个更大的本地磁盘/分区

### 2.2 网络回传不能替代本地落盘空间

这点必须单独强调：

- 本手册推荐的是“采后回传”，不是“边采边搬”
- 因此网络方案**不能**解决“本地磁盘先天不够大”的问题
- 若 `record_rx.py` 输出目录所在分区本身装不下整轮 `1 h` 数据，则必须先处理本地存储容量问题

建议正式执行前先跑：

```bash
DATA_ROOT=/home/$USER/GNSS_RX_Data_local
mkdir -p "$DATA_ROOT"

df -h "$DATA_ROOT"
```

判定口径：

- `Avail` 明显大于 `58.9G` 才可继续
- 更稳妥的口径是：可用空间至少 `70G`

---

## 三、为什么 1 h 必须固定用 chunked

本轮 `1 h` 默认正式策略固定为：

- RX 使用 `chunked`
- `--chunk-duration 30`
- TX 保持当前稳定基线
- TX 覆盖时长大于 RX 总采集时长

原因如下：

- 单文件 `1 h` 太大，不利于长时写盘稳定性
- chunked 后总 chunk 数固定为 `120`
- 每段 `.sc16` 约 `0.49 GB`
- 更适合采后网络回传
- 更适合 MATLAB 抽查前 / 中 / 后几个 chunk

因此，本手册不再把 `single 3600 s` 作为正式方案，只保留 `chunked(30 s)`。

---

## 四、适用前提

执行本手册前，默认同时满足：

- Ubuntu 采集机与 Windows MATLAB 主机在同一局域网
- Windows 本地 SSD 有足够空间，建议至少预留 `70 GB`
- Ubuntu 端可以通过 SSH 被 Windows 访问
- Windows 端允许安装并使用 `WinFsp + SSHFS-Win`
- MATLAB 正式分析仍优先在 Windows 本地环境执行

当前默认推荐：

- 数据网络挂载：`SSHFS-Win`
- Windows 本地落地点：`E:\GNSS_RX_Data_local`
- 正式 BER：从 Windows 本地 SSD 路径读取

Samba 只保留为“独占工作站时的备选方案”，不作为本手册默认主路径。

---

## 五、目录约定

本手册固定使用下面这套目录口径。

### 5.1 Ubuntu 源目录

```text
/home/$USER/GNSS_RX_Data_local/<YYYY>/<YYYY_MM_DD>/<capture_group_id>/
```

### 5.2 Windows 本地目标目录

```text
E:\GNSS_RX_Data_local\<YYYY>\<YYYY_MM_DD>\<capture_group_id>\
```

### 5.3 推荐 capture_group_id 规则

为了让 `1 h` 目录可预测、便于 Windows `robocopy`，本手册固定显式指定 `output_stem`：

```bash
RUN_TS=$(date +%Y%m%d_%H%M%S)
CAPTURE_GROUP_ID=${RUN_TS}_ber1h_prn1_spread_sr4p092e6_cf100e6_d3600s
CAPTURE_DIR=/home/$USER/GNSS_RX_Data_local/2026/2026_03_31/$CAPTURE_GROUP_ID
LOCAL_STEM=$CAPTURE_DIR/$CAPTURE_GROUP_ID
```

在这个规则下，chunk 文件名会稳定长成：

```text
<capture_group_id>_chunk0001of0120.sc16
...
<capture_group_id>_chunk0120of0120.sc16
```

说明：

- 这样做的目的是让整轮 `1 h` 的目录名与 chunk 基名前缀固定一致
- chunk 的精确开始时间仍会记录在各自 `.json` 的 `capture_started_at_iso`
- 对 `1 h` 手册而言，可预测目录结构比自动时间戳文件名更适合局域网回传

---

## 六、正式执行前的固定准备

### 6.1 Ubuntu 端固定变量

```bash
DATA_ROOT=/home/$USER/GNSS_RX_Data_local
RUN_TS=$(date +%Y%m%d_%H%M%S)
CAPTURE_GROUP_ID=${RUN_TS}_ber1h_prn1_spread_sr4p092e6_cf100e6_d3600s
CAPTURE_DIR=$DATA_ROOT/2026/2026_03_31/$CAPTURE_GROUP_ID
LOCAL_STEM=$CAPTURE_DIR/$CAPTURE_GROUP_ID

mkdir -p "$CAPTURE_DIR"
printf 'CAPTURE_GROUP_ID=<%s>\n' "$CAPTURE_GROUP_ID"
printf 'CAPTURE_DIR=<%s>\n' "$CAPTURE_DIR"
printf 'LOCAL_STEM=<%s>\n' "$LOCAL_STEM"
```

### 6.2 Ubuntu 端容量检查

```bash
df -h "$DATA_ROOT"
```

若这里显示可用空间仍只有约 `44G`，则**不要继续执行 1 h 正式采集**。

此时只能先做下面之一：

- 删除旧数据，腾出空间
- 把 `DATA_ROOT` 改到 Ubuntu 侧更大磁盘
- 暂时只执行 `250 s`

### 6.3 先做 dry-run

```bash
cd ~/projects/GNSS_RX
source .venv/bin/activate

PYTHONPATH=src python3 scripts/record_rx.py \
    --config configs/rx_baremetal.yaml \
    --duration 3600 \
    --capture-mode chunked \
    --chunk-duration 30 \
    --output-stem "$LOCAL_STEM" \
    --dry-run
```

dry-run 要确认：

- `capture_mode=chunked`
- `chunk_duration_s=30.0`
- 输出路径落在 `$CAPTURE_DIR`
- 首段文件名正确显示为 `_chunk0001of0120`

---

## 七、1 h 正式采集命令

### 7.1 TX 端正式命令

建议 TX 至少覆盖 `3660 s`，留出边界裕量：

```bash
cd ~/projects/gnss_tx
source .venv/bin/activate

sudo chrt -f 50 env PYTHONPATH=src python3 scripts/run_tx.py \
    --config configs/tx_b210_cable_loopback.yaml \
    --tx-gain 50 \
    --amplitude 1.0 \
    --duration 3660
```

### 7.2 RX 端正式命令

```bash
cd ~/projects/GNSS_RX
source .venv/bin/activate

sudo chrt -f 50 env PYTHONPATH=src python3 scripts/record_rx.py \
    --config configs/rx_baremetal.yaml \
    --duration 3600 \
    --capture-mode chunked \
    --chunk-duration 30 \
    --output-stem "$LOCAL_STEM"
```

说明：

- 这里显式使用 `--output-stem "$LOCAL_STEM"`，避免 `rx_baremetal.yaml` 中默认 `output_base_dir` 与本手册目录约定不一致
- 正式 `1 h` 不建议继续依赖配置文件默认输出目录

---

## 八、采后本地完整性检查

### 8.1 先数 chunk 数量

```bash
find "$CAPTURE_DIR" -maxdepth 1 -type f -name '*.sc16' | wc -l
find "$CAPTURE_DIR" -maxdepth 1 -type f -name '*.json' | wc -l
ls -lh "$CAPTURE_DIR" | sed -n '1,20p'
```

判定口径：

- `.sc16` 应为 `120`
- chunk `.json` 应为 `120`
- 目录中不应缺前段、中段、后段

### 8.2 固定导出 `tx_truth.json`

对 chunked `1 h`，推荐在 `CAPTURE_DIR` 内放一个**统一命名的** truth 文件：

```bash
cd ~/projects/gnss_tx
source .venv/bin/activate

PYTHONPATH=src python3 scripts/run_tx.py \
    --config configs/tx_b210_cable_loopback.yaml \
    --tx-gain 50 \
    --amplitude 1.0 \
    --dry-run \
    --export-truth-json "$CAPTURE_DIR/tx_truth.json"
```

这样做的原因是：

- chunk 文件名带 `_chunkNNNNof0120`
- `ber` 分析单个 chunk 时，更容易稳定命中 `capture_dir/tx_truth.json` 这个 fallback truth
- 不要求为 `120` 个 chunk 各自生成单独 `*_tx_truth.json`

### 8.3 truth 文件检查

```bash
ls -lh "$CAPTURE_DIR"/tx_truth.json
```

到这一步，Ubuntu 源目录中至少应具备：

- `120` 个 `.sc16`
- `120` 个 `.json`
- `1` 个 `tx_truth.json`

---

## 九、局域网回传到 Windows 本地 SSD

### 9.1 为什么默认用“Windows 拉取到本地”

本手册主推 `Windows 拉取到本地`，而不是 `Ubuntu 推送到 Windows`，原因是：

- 回传动作由分析机主导，更容易和本地盘符、目标 SSD 路径保持一致
- `robocopy` 自带重试与续跑能力，更适合几十 GB 的目录镜像
- 不把网络抖动引入采集阶段
- Windows 端最终直接得到正式分析所需的本地路径

### 9.2 Windows 端挂载 Ubuntu 数据目录

默认沿用 `docs/lan_data_sharing_setup.md` 的 `SSHFS-Win` 路径。

推荐挂载整个数据根目录，而不是仓库根目录：

```powershell
net use Z: \\sshfs\<UBUNTU_USER>@<UBUNTU_IP>\home\<UBUNTU_USER>\GNSS_RX_Data_local /persistent:yes
net use
dir Z:\
```

成功后，`Z:` 根目录下应至少能看到：

```text
2026
```

### 9.3 Windows 端镜像到本地 SSD

固定使用“本轮目录级别”的 `robocopy`，不要直接对整个 `2026_03_31` 父目录做 `/MIR`：

```powershell
$CaptureGroupId = "<capture_group_id>"
$Src  = "Z:\2026\2026_03_31\$CaptureGroupId"
$Dest = "E:\GNSS_RX_Data_local\2026\2026_03_31\$CaptureGroupId"

New-Item -ItemType Directory -Force -Path $Dest | Out-Null
robocopy $Src $Dest /MIR /Z /R:3 /W:5 /MT:8
```

这样做的原因是：

- `/MIR` 只作用于单轮目录，避免误删同日期下其他实验目录
- `/Z` 支持大文件回传时的断点续跑
- `/R:3 /W:5` 避免网络轻微抖动时无限重试
- `/MT:8` 在多数 Windows 本地 SSD 上已经够用，不建议盲目开太大

### 9.4 Windows 端复制完成后的文件数检查

```powershell
Get-ChildItem "$Dest" -Filter *.sc16 | Measure-Object
Get-ChildItem "$Dest" -Filter *.json | Measure-Object
Test-Path "$Dest\\tx_truth.json"
```

判定口径：

- `.sc16` 数量为 `120`
- `.json` 数量为 `120`
- `tx_truth.json` 存在

---

## 十、Windows 本地 MATLAB 抽查方案

### 10.1 只从 Windows 本地 SSD 路径分析

正式 BER 与抽查 BER 默认都从：

```text
E:\GNSS_RX_Data_local\2026\2026_03_31\<capture_group_id>\
```

读取，不再推荐直接对 `Z:` 网络盘运行正式 `ber`。

### 10.2 固定抽查前 / 中 / 后三个 chunk

假设：

```matlab
CAPTURE_GROUP_ID = '20260331_190530_ber1h_prn1_spread_sr4p092e6_cf100e6_d3600s';
CAPTURE_DIR = fullfile('E:\GNSS_RX_Data_local\2026\2026_03_31', CAPTURE_GROUP_ID);
```

则固定抽查：

- 前段：`chunk0001of0120`
- 中段：`chunk0060of0120`
- 后段：`chunk0120of0120`

```matlab
CAPTURE_PATH_1   = fullfile(CAPTURE_DIR, [CAPTURE_GROUP_ID '_chunk0001of0120']);
CAPTURE_PATH_60  = fullfile(CAPTURE_DIR, [CAPTURE_GROUP_ID '_chunk0060of0120']);
CAPTURE_PATH_120 = fullfile(CAPTURE_DIR, [CAPTURE_GROUP_ID '_chunk0120of0120']);

exist([CAPTURE_PATH_1 '.sc16'], 'file')
exist([CAPTURE_PATH_1 '.json'], 'file')
exist(fullfile(CAPTURE_DIR, 'tx_truth.json'), 'file')
```

### 10.3 MATLAB 正式抽查口径

固定顺序：

1. 先抽查 `chunk0001of0120`
2. 再抽查 `chunk0060of0120`
3. 最后抽查 `chunk0120of0120`

若这三段都满足：

- TX 无 underflow
- RX 无 overflow
- truth 加载正常
- tracked BER 稳定

再决定是否继续扩大抽查范围。

### 10.4 MATLAB 运行示例

```matlab
cd('E:\MATLAB_code_Gongwei_Local\GNSS_RX_matlab')
clear functions
rehash

CAPTURE_GROUP_ID = '20260331_190530_ber1h_prn1_spread_sr4p092e6_cf100e6_d3600s';
CAPTURE_DIR = fullfile('E:\GNSS_RX_Data_local\2026\2026_03_31', CAPTURE_GROUP_ID);
CAPTURE_PATH = fullfile(CAPTURE_DIR, [CAPTURE_GROUP_ID '_chunk0001of0120']);

BER_MODE = 'tracked_truth';
run('scripts/run_ber_loopback.m')
```

---

## 十一、不推荐但允许的 fallback

### 11.1 fallback A：网络盘直读

允许场景：

- 只想快速确认某个 chunk 能否被 MATLAB 正常打开
- 只想做 `run_capture_analysis` 或一次小范围 `ber` spot-check

不推荐原因：

- 网络盘稳定性和吞吐不如 Windows 本地 SSD
- 长时抽查很容易把“网络读盘问题”误判成“算法问题”
- 不适合作为正式 BER 结论路径

因此，这条路径只能用于**临时抽查**，不能作为本手册的正式主推荐方案。

### 11.2 fallback B：移动硬盘

允许场景：

- 局域网链路不可用
- SSHFS-Win 或 Samba 当前无法挂载
- Windows 本地网络权限暂时受限

一旦走到这里，请直接回到总手册的“移动硬盘转移流程”，不要在本手册里再重复维护一套相同步骤。

---

## 十二、最终验收口径

本手册执行成功，至少应满足：

1. Ubuntu 端 `1 h chunked` 采集完成，无 overflow
2. Ubuntu 源目录中 `120` 个 `.sc16` 和 `120` 个 `.json` 完整存在
3. `CAPTURE_DIR/tx_truth.json` 已成功导出
4. Windows 能通过 `SSHFS-Win` 挂载 Ubuntu 数据目录
5. `robocopy` 能把本轮整目录复制到 Windows 本地 SSD
6. Windows 本地目录抽查前 / 中 / 后 3 个 chunk 时，三件套与 truth 均可读取
7. MATLAB 从 Windows 本地 SSD 路径运行 `run_ber_loopback.m` 正常

如果第 1 步之前就发现 `df -h "$DATA_ROOT"` 可用空间明显不足，则本轮 `1 h` 不应启动。

