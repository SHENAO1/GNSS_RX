# 闭环 BER 全链路总手册（TX/RX 一体 ）

> 创建时间：2026-03-31
> 适用场景：从一台全新裸机 Ubuntu 笔记本开始，完成 B210 线缆回环采集，并在主力机 MATLAB 上做正式 BER 分析
> 存放策略：本文件在 `gnss_tx` 与 `GNSS_RX` 各保留一份，内容必须保持一致
> 整合来源：
> - `gnss_tx/experiments/plans/2026-03-29/baremetal_capture/2026-03-29_baremetal_capture_runbook.md`
> - `GNSS_RX/experiments/plans/2026-03-30/ber_loopback_rx/2026-03-30_existing_capture_ber_analysis_runbook.md`
> - `GNSS_RX/experiments/plans/2026-03-28/ber_loopback_rx/2026-03-28_ber_loopback_joint_runbook.md`
> 正式 MATLAB BER 入口：`GNSS_RX/matlab/ber.m`
> 正式 BER 主脚本：`GNSS_RX/matlab/scripts/run_ber_loopback.m`
> 快速体检入口：`GNSS_RX/matlab/scripts/run_capture_analysis.m`

---

## 一、这份总手册解决什么问题

之前的流程分散在 3 份文档里：

- 一份偏“新电脑裸机采集”
- 一份偏“已有样本离线 BER 分析”
- 一份偏“TX/RX 联机执行顺序”

实际执行时，最容易出现的问题不是脚本本身，而是：

- 不知道先看哪份文档
- 不知道 MATLAB 到底应该先跑 `ber` 还是 `run_capture_analysis`
- 不知道 30 s、100 s、250 s、1 h 的目标和口径是否一致
- 不知道新电脑、移动硬盘、主力机三台设备之间的数据怎么流转

本手册把这些内容合并为一条单线流程：

```text
新裸机电脑搭环境
→ TX/RX dry-run
→ 导出 TX truth JSON
→ 同步 MATLAB 工作区
→ 先跑固定旧样本 BER 回归
→ 再做 30 s / 100 s / 250 s / 1 h 联机采集
→ 通过移动硬盘或本地复制把数据交给主力机
→ 在 MATLAB 上用 tracked_truth 做正式 BER
```

一句话口径：

```text
先离线收敛，再联机复验；先 30 s，再 100 s，再 250 s，最后 1 h。
正式 BER 看 ber / tracked_truth；run_capture_analysis 只做快速体检。
```

---

## 二、机器角色与数据流

本轮默认涉及 3 类机器或环境。

### 2.1 裸机 Ubuntu 笔记本

职责：

- 连接两块 B210
- 运行 `gnss_tx/scripts/run_tx.py`
- 运行 `GNSS_RX/scripts/record_rx.py`
- 生成 `.sc16 + .json`
- 导出 `tx_truth.json`

### 2.2 移动硬盘

职责：

- 在采集完成后，从裸机笔记本转运采集数据
- 可选转运 `tx_truth.json`
- 可选作为 Windows 主力机的“临时直读数据盘”

本轮更推荐的实际执行顺序是：

- 采集阶段先把数据写到 Ubuntu 本地固定目录
- 等两台 B210 断开、USB 口空出来以后
- 再把整轮采集目录复制到移动硬盘

### 2.3 主力机 MATLAB

职责：

- 运行 `ber`
- 必要时运行 `run_capture_analysis()`
- 做正式 BER 统计、图形诊断、结果归档

### 2.4 数据流

```text
裸机 Ubuntu
  ├─ gnss_tx/.venv + run_tx.py
  ├─ GNSS_RX/.venv + record_rx.py
  └─ /home/<user>/GNSS_RX_Data_local/<date>/<capture_name>/
       ├─ <capture>.sc16
       ├─ <capture>.json
       └─ <capture>_tx_truth.json
            ↓
      采集完成后复制到移动硬盘
            ↓
      Windows / Linux 主力机
            ↓
      GNSS_RX_matlab / GNSS_RX/matlab
            ↓
      ber → run_ber_loopback.m → tracked_truth BER
```

若裸机笔记本只有两个 USB 3.x 口，且采集时需要同时连接两台 B210，则默认不要在采集过程中再接移动硬盘。推荐口径是：**先本地落盘，后离线转运**。

---

## 三、统一冻结基线

除非本轮实验目标明确要求改参数，否则 3.31 统一冻结以下基线。

| 项目 | 当前冻结值 |
|------|------------|
| TX 设备 | `serial=193982` |
| RX 设备 | `serial=8003272` |
| 中心频率 | `100 MHz` |
| 采样率 | `4.092 Msps` |
| TX 天线口 | `TX/RX` |
| RX 天线口 | `RX2` |
| TX 配置 | `gnss_tx/configs/tx_b210_cable_loopback.yaml` |
| RX 配置 | `GNSS_RX/configs/rx_baremetal.yaml` |
| nav pattern | `1 0 1 1 0 0 1 0` |
| samples_per_chip | `4` |
| TX 默认增益 | `50 dB` |
| RX 默认增益 | `20 dB` |
| truth 文件名 | `tx_truth.json` |
| 正式 BER 模式 | `tracked_truth` |
| `1 h` 推荐采集模式 | `chunked` |
| `1 h` 推荐 chunk 时长 | `30 s` |

当前默认不要同时修改：

- 接线方式
- 中心频率
- 采样率
- nav pattern
- TX truth JSON 来源
- MATLAB BER 入口
- 长时采集模式选择

---

## 四、先看这张判断表

### 4.1 不需要开真实 USRP 的步骤

- 安装系统依赖
- 拉取或拷贝代码
- 创建两边 `.venv`
- 运行 TX/RX `dry-run`
- 导出 `tx_truth.json`
- 同步 MATLAB 工作区
- 用固定旧样本做离线 BER 回归
- 做 `250 s` / `1 h` 命令级 `dry-run`

### 4.2 需要真实 TX/RX 同时参与的步骤

- 新的 `30 s` 联机复验
- `100 s` 联机过渡验证
- `250 s` 正式 BER 验收
- `1 h` 长时稳定性验证

### 4.3 正式 BER 的唯一口径

- 正式 BER 入口：`ber` / `run_ber_loopback.m`
- 正式 BER 模式：`tracked_truth`
- `open_loop_truth`：只作为对照诊断
- `run_capture_analysis()`：只做采后总览、捕获、survey，不作为正式 BER 验收结论

### 4.4 有效样本闸门

只有同时满足以下条件，当前样本才计入正式 BER 验收：

- TX 全程无 underflow，即终端无持续 `U`
- RX 全程无 overflow，即终端无持续 `O`
- MATLAB 日志显示 `TX truth：JSON 模式`
- `BER_MODE='tracked_truth'`

若日志中出现 overflow / underflow，则该样本可以分析，但默认不计入正式收敛样本。

---

## 五、从新电脑开始：裸机 Ubuntu 初始化

本节假设你刚拿到一台新电脑，系统为裸机 Ubuntu。

### 5.1 系统更新

```bash
sudo apt update
sudo apt upgrade -y
```

### 5.2 安装基础依赖

```bash
sudo apt install -y \
    gnuradio \
    python3-gnuradio \
    uhd-host \
    python3-pip \
    python3-venv \
    git \
    rsync \
    usbutils
```

说明：

- `python3-gnuradio` 和 `uhd-host` 必须安装，否则 B210 相关 Python 绑定不可用
- `rsync` 主要用于同步 MATLAB 代码
- `usbutils` 用于 `lsusb -t` 检查是否落在 USB 3.x

### 5.3 下载 UHD 镜像

```bash
sudo uhd_images_downloader
```

这一步必须执行。缺失镜像时，B210 可能无法正常枚举。

### 5.4 初步验证 UHD

此时可以还不插 B210，先确认命令存在。

```bash
uhd_find_devices
```

若尚未插设备，出现 `No UHD Devices Found` 属于正常现象。

---

## 六、获取两个仓库

本手册默认使用以下目录组织：

```text
/home/<user>/projects/
├── gnss_tx
└── GNSS_RX
```

### 6.1 方式 A：有网环境下直接 clone

```bash
mkdir -p ~/projects
cd ~/projects
git clone --branch feat/prn-subset-tx https://github.com/SHENAO1/gnss_tx.git gnss_tx
git clone --branch feat/multi-prn-rx https://github.com/SHENAO1/GNSS_RX.git GNSS_RX
```

### 6.2 方式 B：无网环境下用移动硬盘拷贝

在已有电脑上先把两个仓库完整拷到移动硬盘，然后在新电脑上执行：

```bash
mkdir -p ~/projects
cp -r /media/$USER/<drive_name>/gnss_tx ~/projects/
cp -r /media/$USER/<drive_name>/GNSS_RX ~/projects/
```

若移动硬盘目录名有空格，命令必须加引号，例如：

```bash
cp -r "/media/$USER/Seagate Basic/gnss_tx" ~/projects/
cp -r "/media/$USER/Seagate Basic/GNSS_RX" ~/projects/
```

---

## 七、创建 Python 虚拟环境

这一节是最容易踩坑的地方。

### 7.1 总原则

`gnss_tx` 和 `GNSS_RX` 的真实 B210 路径都依赖系统安装的 GNU Radio / UHD Python 绑定，因此：

```text
必须使用 python3 -m venv --system-site-packages .venv
```

不要使用普通 `venv`，否则运行真实 TX / RX 时很容易看到：

```text
ModuleNotFoundError: No module named 'gnuradio'
```

或：

```text
RuntimeError: GNU Radio UHD bindings are not available.
```

### 7.2 `gnss_tx` 环境

```bash
cd ~/projects/gnss_tx
rm -rf .venv
python3 -m venv --system-site-packages .venv
source .venv/bin/activate
pip install --upgrade pip
pip install -r env/ubuntu/requirements.txt
pip install -e .
python3 -c "from gnuradio import uhd; print(uhd.__file__)"
deactivate
```

正确结果应打印出系统 GNU Radio UHD 绑定路径，例如：

```text
/usr/lib/python3/dist-packages/gnuradio/uhd/__init__.py
```

### 7.3 `GNSS_RX` 环境

推荐直接执行仓库内安装脚本：

```bash
cd ~/projects/GNSS_RX
bash env/ubuntu/setup.sh
```

若需要手动创建，则使用：

```bash
cd ~/projects/GNSS_RX
rm -rf .venv
python3 -m venv --system-site-packages .venv
source .venv/bin/activate
pip install --upgrade pip
pip install -r env/ubuntu/requirements.txt
pip install -e .
python3 -c "from gnuradio import uhd; print(uhd.__file__)"
deactivate
```

---

## 八、插硬件并做裸机侧设备验证

### 8.1 插入两块 B210

把两块 B210 都通过 USB 3.x 连接到裸机笔记本。

### 8.2 枚举设备

```bash
uhd_find_devices
```

预期输出至少应包含：

```text
serial: 193982
serial: 8003272
```

### 8.3 检查 USB 速率

```bash
lsusb -t
```

关注点：

- 两块 B210 都应显示在 `5000M`
- 若显示为 `480M`，说明掉到了 USB 2.0，不适合当前实验
- 两块 B210 落在同一 root hub 上并不一定是问题，只要仍为 USB 3.x

### 8.4 当前基线配置文件

TX 配置：

- `~/projects/gnss_tx/configs/tx_b210_cable_loopback.yaml`

RX 配置：

- `~/projects/GNSS_RX/configs/rx_baremetal.yaml`

当前 `rx_baremetal.yaml` 默认输出根目录为：

```text
/home/shenao/GNSS_RX_Data
```

若你的用户名不是 `shenao`，建议正式采集时通过 CLI 覆盖：

```bash
PYTHONPATH=src python3 scripts/record_rx.py \
    --config configs/rx_baremetal.yaml \
    --output-base-dir /home/<your_user>/GNSS_RX_Data
```

---

## 九、先做 dry-run，不要急着接线

### 9.1 TX 预检

```bash
cd ~/projects/gnss_tx
source .venv/bin/activate
python3 -c "from gnuradio import uhd; print(uhd.__file__)"
PYTHONPATH=src python3 scripts/run_tx.py \
    --config configs/tx_b210_cable_loopback.yaml \
    --tx-gain 50 \
    --amplitude 1.0 \
    --dry-run
deactivate
```

### 9.2 RX 预检

```bash
cd ~/projects/GNSS_RX
source .venv/bin/activate
python3 -c "from gnuradio import uhd; print(uhd.__file__)"
PYTHONPATH=src python3 scripts/record_rx.py \
    --config configs/rx_baremetal.yaml \
    --dry-run
deactivate
```

确认要点：

- `record_rx.py` 输出的 `output_base_dir` 指向本地磁盘
- dry-run 无配置报错
- 能正常打印 UHD 设备发现结果

---

## 十、接线与安全前提

推荐接线：

```text
TX B210 (serial=193982)  TX/RX
            │
      [推荐固定衰减器 20~30 dB]
            │
        [同轴线缆]
            │
RX B210 (serial=8003272) RX2
```

安全说明：

- 当前 TX 配置默认 `tx_gain=50`
- 该配置来自现有 cable loopback 基线
- 若没有衰减器，也不要在本轮擅自继续上调 TX 增益
- 若有固定衰减器，优先保持 TX 不变，只微调 RX 增益

---

## 十一、正式导出 TX truth JSON

truth JSON 不是采集文件，也不是 BER 结果文件，它是 TX 发射前导出的“真值契约”。

正式 BER 对比时，RX MATLAB 侧主要依赖它获取：

- `nav_bits_pattern_pm1`
- `nav_bits_pattern_01`
- `initial_code_phase`
- `initial_nav_epoch`
- `initial_nav_bit_index`
- `samples_per_chip`
- `sample_rate`
- `epochs_per_bit`
- `prn_id`

### 11.1 当前推荐口径：按时间戳绑定 capture 与 sidecar truth

正式 BER 采集前，先固定本轮 `CAPTURE_NAME`，并让 truth 文件与 capture stem 使用同一主名。

下面给出 `250 s` 的标准模板；`30 s`、`100 s`、`1 h` 只需要替换 `CAPTURE_NAME` 与时长：

```bash
CAPTURE_NAME=20260331_ber250s_localdisk_rawiq_sc16_zeroif_prn1_spread_sr4092000_cf100000000_dur250p0s
CAPTURE_DIR=/home/$USER/GNSS_RX_Data_local/2026/2026_03_31/$CAPTURE_NAME
LOCAL_STEM=$CAPTURE_DIR/$CAPTURE_NAME
TRUTH_PATH=$CAPTURE_DIR/${CAPTURE_NAME}_tx_truth.json

mkdir -p "$CAPTURE_DIR"
printf 'CAPTURE_DIR=<%s>\n' "$CAPTURE_DIR"
printf 'LOCAL_STEM=<%s>\n' "$LOCAL_STEM"
printf 'TRUTH_PATH=<%s>\n' "$TRUTH_PATH"
```

本轮在 `shenao` 账户下已实测展开为：

```text
CAPTURE_DIR=</home/shenao/GNSS_RX_Data_local/2026/2026_03_31/20260331_ber250s_localdisk_rawiq_sc16_zeroif_prn1_spread_sr4092000_cf100000000_dur250p0s>
LOCAL_STEM=</home/shenao/GNSS_RX_Data_local/2026/2026_03_31/20260331_ber250s_localdisk_rawiq_sc16_zeroif_prn1_spread_sr4092000_cf100000000_dur250p0s/20260331_ber250s_localdisk_rawiq_sc16_zeroif_prn1_spread_sr4092000_cf100000000_dur250p0s>
TRUTH_PATH=</home/shenao/GNSS_RX_Data_local/2026/2026_03_31/20260331_ber250s_localdisk_rawiq_sc16_zeroif_prn1_spread_sr4092000_cf100000000_dur250p0s/20260331_ber250s_localdisk_rawiq_sc16_zeroif_prn1_spread_sr4092000_cf100000000_dur250p0s_tx_truth.json>
```

这说明 `mkdir -p "$CAPTURE_DIR"` 已成功，后续 TX dry-run 导出 truth 与 RX 正式采集都可以直接沿用这三个变量。

推荐先在 TX 侧做一次 dry-run，把 sidecar truth 直接导出到本轮采集目录：

```bash
cd ~/projects/gnss_tx
source .venv/bin/activate
PYTHONPATH=src python3 scripts/run_tx.py \
    --config configs/tx_b210_cable_loopback.yaml \
    --tx-gain 50 \
    --amplitude 1.0 \
    --dry-run \
    --export-truth-json "$TRUTH_PATH"
deactivate
```

若终端里的 `UHD discovery output` 同时列出 `x300`、两块 `B210`，这通常只是因为当前主机所在网段上还能被 `uhd_find_devices` 扫到一台网络型 X300。它不是本轮实验的绑定目标。

当前真正决定 TX 设备的是配置里的 `usrp_addr`。本轮 `configs/tx_b210_cable_loopback.yaml` 已固定为 `serial=193982`，而且本步骤使用了 `--dry-run`，日志末尾若出现 `Dry run requested. Transmission was not started.`，就说明这里只做了配置加载、设备枚举打印和 truth 导出，并没有真正启动发射，更没有切到 X300 发波。

若手工检查时出现 `TRUTH_PATH=<>`，表示当前 shell 里的 `TRUTH_PATH` 变量是空的。最常见原因是换了一个新终端、重开了 tab，或还没重新执行本节最前面的 4 行变量赋值。此时 `--export-truth-json "$TRUTH_PATH"` 会退化成空参数，因此 dry-run 日志里通常也不会出现 `[INFO] Exported TX truth JSON: ...`。

重新执行本节变量赋值后，只要 `CAPTURE_DIR`、`LOCAL_STEM` 正常展开，`TRUTH_PATH` 也应展开到同一目录下并以 `_tx_truth.json` 结尾。若聊天记录或终端截图里最后一行看起来被截断，通常只是复制/显示被裁切，不代表 shell 报错；以重新执行 `printf 'TRUTH_PATH=<%s>\n' "$TRUTH_PATH"` 的完整输出为准。

这样本轮目录最终应至少包含：

```text
<capture_dir>/
  <capture_stem>.sc16
  <capture_stem>.json
  <capture_stem>_tx_truth.json
```

**若本轮计划通过移动硬盘转运采集数据到主力机，推荐到这里为止，后续直接把整个 `<capture_dir>` 拷走即可。此时 `11.2` 和 `11.3` 都可以跳过**，因为它们只是把 `tx_truth.json` 额外写到 MATLAB 工作区根目录，属于兼容旧流程的 fallback，不是移动硬盘方案的主路径。

`11.1` 的正确状态可以按下面判断：

- `printf 'TRUTH_PATH=<%s>\n' "$TRUTH_PATH"` 能打印出完整绝对路径，且以 `_tx_truth.json` 结尾
- 重新运行本节 dry-run 后，日志里出现 `[INFO] Exported TX truth JSON: ...`
- 执行 `ls -l "$TRUTH_PATH"` 能看到该 JSON 文件已经落盘

若以上 3 条都满足，说明本轮 sidecar truth 已准备完成。下一步不要去做 `11.2/11.3`，而是继续进入后续 RX 正式采集步骤，让 `.sc16`、`.json`、`_tx_truth.json` 三个文件最终落在同一个 `<capture_dir>` 下，后面整目录一起拷贝到移动硬盘。

### 11.2 兼容旧流程：裸机 Linux 本地保存到 MATLAB 工作区根目录

```bash
cd ~/projects/gnss_tx
source .venv/bin/activate
PYTHONPATH=src python3 scripts/run_tx.py \
    --config configs/tx_b210_cable_loopback.yaml \
    --tx-gain 50 \
    --amplitude 1.0 \
    --dry-run \
    --export-truth-json ~/projects/GNSS_RX/matlab/tx_truth.json
deactivate
```

### 11.3 若主力机为 Windows 且使用 VMware 共享目录

```bash
cd ~/projects/gnss_tx
source .venv/bin/activate
PYTHONPATH=src python3 scripts/run_tx.py \
    --config configs/tx_b210_cable_loopback.yaml \
    --tx-gain 50 \
    --amplitude 1.0 \
    --dry-run \
    --export-truth-json /mnt/hgfs/GongXiangDocument/GNSS_RX_matlab/tx_truth.json
deactivate
```

这条路径继续保留，但当前只建议作为兼容旧流程的 fallback truth，不再推荐作为正式 BER 的首选 truth 来源。

### 11.4 完成标志

- `<capture_stem>_tx_truth.json` 已成功生成，或兼容旧流程的根目录 `tx_truth.json` 已成功生成
- dry-run 摘要中的 `nav_pattern`、`initial_nav_epoch`、`initial_nav_bit_index` 与当前基线一致
- 后续 MATLAB 正式 BER 日志能看到 `TX truth：JSON 模式`

---

## 十二、同步 MATLAB 工作区

### 12.1 同步入口

唯一推荐同步方式：在 Ubuntu 端执行 `sync_matlab.sh`，把 `GNSS_RX/matlab/` 镜像到一个**实际存在且可写**的目标目录。

```bash
cd ~/projects/GNSS_RX
bash ./scripts/sync_matlab.sh <MATLAB_WORKSPACE_DIR>
```

常见目标目录示例：

- VMware 共享目录：`/mnt/hgfs/GongXiangDocument/GNSS_RX_matlab`
- 移动硬盘挂载点：`/media/$USER/<drive_name>/GNSS_RX_matlab`
- Ubuntu 本机临时目录：`$HOME/GNSS_RX_matlab`

若这里直接运行 `./scripts/sync_matlab.sh ...` 出现“权限不够”，通常只是脚本暂时没有执行位；优先改用 `bash ./scripts/sync_matlab.sh ...` 即可继续。

若目标写成 `/mnt/hgfs/...` 却报 `mkdir: 无法创建目录 "/mnt/hgfs": 权限不够`，优先按“该机没有 VMware 共享目录挂载”处理。此时不要继续硬用 `/mnt/hgfs/...`，而应改成这台 Ubuntu 当前真实存在的可写目录；如果本轮走移动硬盘转运，推荐直接改成 `/media/$USER/<drive_name>/GNSS_RX_matlab`。

同步内容包括：

- `functions/`
- `scripts/`
- `README.md`
- `architecture.drawio`
- `gnss_rx_user_paths.m.example`
- 根目录快捷入口 `ber.m`

注意：

- `GNSS_RX/matlab/` 才是源码真相源
- `GNSS_RX_matlab/` 只是主力机部署镜像，不应手工改代码
- `sync_matlab.sh` 只同步 MATLAB 代码与受管入口文件
- 采集目录中的 sidecar truth 属于数据，不属于 MATLAB 代码镜像，不会随这个脚本一起复制

### 12.2 为什么要先同步

因为正式 BER 现在以：

- `ber`
- `run_ber_loopback.m`

为主入口，若主力机 MATLAB 还在用旧部署副本，就会出现：

- 路径指向旧函数
- `ber` 不存在
- `run_ber_loopback.m` 与仓库当前逻辑不一致

### 12.3 在 MATLAB 中确认已加载新版本

进入主力机 MATLAB 后，先执行：

```matlab
which ber -all
which run_ber_loopback -all
which run_prn_acquisition -all
which recover_nav_bits -all
which gnss_rx_resolve_accel_options -all
```

要求这些路径都指向本轮刚同步的工作区。

---

## 十三、先做离线固定样本 BER 回归

这一步不需要真实 TX/RX 同时开机。

目标不是重采，而是先验证：

- MATLAB 环境通
- `ber` 入口通
- `run_ber_loopback.m` 主链通
- truth 自动匹配口径通
- `tracked_truth` 判决通

### 13.1 固定回归样本

当前历史基线样本：

```text
C:\VMwareVirtualMachines\GongXiangDocument\GNSS_RX_Data\2026\2026_03_28\20260328_142122_rawiq_sc16_zeroif_prn1_spread_sr4092000_cf100000000_dur30p0s
```

本轮回归时建议显式指定 `CAPTURE_PATH`，不要依赖“自动选最新文件”。

### 13.2 Windows 主力机正式 BER 示例

```matlab
cd('C:\VMwareVirtualMachines\GongXiangDocument\GNSS_RX_matlab')
clear functions
rehash

CAPTURE_PATH = ['C:\VMwareVirtualMachines\GongXiangDocument\GNSS_RX_Data\2026\' ...
    '2026_03_28\20260328_142122_rawiq_sc16_zeroif_prn1_spread_sr4092000_' ...
    'cf100000000_dur30p0s\20260328_142122_rawiq_sc16_zeroif_prn1_spread_' ...
    'sr4092000_cf100000000_dur30p0s'];
BER_MODE = 'tracked_truth';

ber
```

### 13.3 Linux 主力机正式 BER 示例

```matlab
cd('/home/shenao/projects/GNSS_RX/matlab')
clear functions
rehash

CAPTURE_PATH = ['/mnt/hgfs/GongXiangDocument/GNSS_RX_Data/2026/' ...
    '2026_03_28/20260328_142122_rawiq_sc16_zeroif_prn1_spread_sr4092000_' ...
    'cf100000000_dur30p0s/20260328_142122_rawiq_sc16_zeroif_prn1_spread_' ...
    'sr4092000_cf100000000_dur30p0s'];
BER_MODE = 'tracked_truth';

run('scripts/run_ber_loopback.m')
```

### 13.4 快速体检入口只作为补充

若你只想先快速确认样本能否加载、捕获和 survey，可运行：

```matlab
result = run_capture_analysis(CAPTURE_PATH);
```

但必须明确：

- `run_capture_analysis()` 不是正式 BER 入口
- 它不替代 `ber`
- 它适合先看“采集文件有没有信号、PRN 捕获是否成功、总览图是否异常”

### 13.5 当前最低通过标准

- 日志显示 `TX truth：JSON 模式`
- 日志进入 `=== Step 4: tracked BER 主链 ===`
- `BER_MODE='tracked_truth'`
- `tracked BER` 有效输出

若固定 30 s 样本都无法收敛，应先停在这里排软件链，而不是马上重采。

---

## 十四、联机 30 s 复验

这是第一轮真实 TX/RX 同时参与的实验。

### 14.1 启动规则

- TX 先启动
- RX 后启动
- TX 发射时长必须长于 RX 采集时长
- 30 s 采集时，TX 推荐给 `60 s`

### 14.2 TX 端命令

```bash
cd ~/projects/gnss_tx
source .venv/bin/activate
PYTHONPATH=src python3 scripts/run_tx.py \
    --config configs/tx_b210_cable_loopback.yaml \
    --tx-gain 50 \
    --amplitude 1.0 \
    --duration 60
```

### 14.3 RX 端命令

TX 启动稳定后约 5 秒，再开 RX：

```bash
cd ~/projects/GNSS_RX
source .venv/bin/activate

CAPTURE_NAME=20260331_ber30s_localdisk_rawiq_sc16_zeroif_prn1_spread_sr4092000_cf100000000_dur30p0s
CAPTURE_DIR=/home/$USER/GNSS_RX_Data_local/2026/2026_03_31/$CAPTURE_NAME
LOCAL_STEM=$CAPTURE_DIR/$CAPTURE_NAME
TRUTH_PATH=$CAPTURE_DIR/${CAPTURE_NAME}_tx_truth.json

mkdir -p "$CAPTURE_DIR"
printf 'LOCAL_STEM=<%s>\n' "$LOCAL_STEM"
printf 'TRUTH_PATH=<%s>\n' "$TRUTH_PATH"

PYTHONPATH=src python3 scripts/record_rx.py \
    --config configs/rx_baremetal.yaml \
    --duration 30 \
    --capture-mode single \
    --output-stem "$LOCAL_STEM"
```

### 14.4 文件量级

`30 s @ 4.092 Msps` 的 `.sc16` 大约为：

- 约 `0.49 GB` 十进制
- 约 `0.46 GiB` 二进制

### 14.5 MATLAB 复验口径

这轮分析时，`CAPTURE_PATH` 应切到“刚刚新采集的 30 s 样本”，不要继续分析旧基线文件。

### 14.6 完成标志

- 新的 30 s 采集成功生成
- TX 无 underflow
- RX 无 overflow
- MATLAB 上 `tracked_truth` BER 低误码
- 连续 3 份新 30 s 样本都稳定

---

## 十五、联机 100 s 过渡验证

这一步是 30 s 到 250 s 的过渡桥，不建议跳过。

目的：

- 验证“本地落盘 + 采后复制”流程
- 验证系统负载拉长后仍无 overflow / underflow
- 避免一上来就把 250 s 或 1 h 的问题混在一起

### 15.1 TX 端命令

```bash
cd ~/projects/gnss_tx
source .venv/bin/activate
PYTHONPATH=src python3 scripts/run_tx.py \
    --config configs/tx_b210_cable_loopback.yaml \
    --tx-gain 50 \
    --amplitude 1.0 \
    --duration 120
```

### 15.2 RX 端命令

推荐显式写本地输出 stem：

```bash
cd ~/projects/GNSS_RX
source .venv/bin/activate

CAPTURE_NAME=20260331_ber100s_localdisk_rawiq_sc16_zeroif_prn1_spread_sr4092000_cf100000000_dur100p0s
CAPTURE_DIR=/home/$USER/GNSS_RX_Data_local/2026/2026_03_31/$CAPTURE_NAME
LOCAL_STEM=$CAPTURE_DIR/$CAPTURE_NAME
TRUTH_PATH=$CAPTURE_DIR/${CAPTURE_NAME}_tx_truth.json

mkdir -p "$CAPTURE_DIR"
printf 'LOCAL_STEM=<%s>\n' "$LOCAL_STEM"
printf 'TRUTH_PATH=<%s>\n' "$TRUTH_PATH"

PYTHONPATH=src python3 scripts/record_rx.py \
    --config configs/rx_baremetal.yaml \
    --duration 100 \
    --capture-mode single \
    --output-stem "$LOCAL_STEM"
```

### 15.3 文件量级

`100 s @ 4.092 Msps` 的 `.sc16` 大约为：

- 约 `1.64 GB` 十进制
- 约 `1.52 GiB` 二进制

### 15.4 完成标志

- 100 s 成功写入本地磁盘
- TX 无 underflow
- RX 无 overflow
- 后续复制和 MATLAB 分析都正常

---

## 十六、联机 250 s 正式 BER 验收

`250 s` 是当前正式 BER 验收区间。

### 16.1 为什么不建议直接写共享目录

历史经验已经表明，长时采集若直接写：

```text
/mnt/hgfs/...
```

更容易把共享目录写盘抖动和主机负载混进来，增加 overflow 风险。

因此 250 s 统一推荐流程是：

```text
先写裸机本地磁盘
→ 采集结束
→ 再复制到共享目录或移动硬盘
→ 再给主力机 MATLAB 分析
```

若笔记本只有两个 USB 3.x 口，并且这两个口都被两台 B210 占用，则采集阶段不要强行插入移动硬盘。默认先写入：

```text
/home/$USER/GNSS_RX_Data_local/...
```

待采集结束后，再断开一台 B210 或释放 USB 口，把本轮 `<capture_dir>` 整目录复制到移动硬盘。

### 16.2 若要进一步降低被抢占风险

对于 250 s 及以上长时实验，推荐提高进程调度优先级：

```bash
sudo chrt -f 50 env PYTHONPATH=src python3 <script> ...
```

### 16.3 TX 端命令

```bash
cd ~/projects/gnss_tx
source .venv/bin/activate
sudo chrt -f 50 env PYTHONPATH=src python3 scripts/run_tx.py \
    --config configs/tx_b210_cable_loopback.yaml \
    --tx-gain 50 \
    --amplitude 1.0 \
    --duration 300
```

### 16.4 RX 端命令

```bash
cd ~/projects/GNSS_RX
source .venv/bin/activate

CAPTURE_NAME=20260331_ber250s_localdisk_rawiq_sc16_zeroif_prn1_spread_sr4092000_cf100000000_dur250p0s
CAPTURE_DIR=/home/$USER/GNSS_RX_Data_local/2026/2026_03_31/$CAPTURE_NAME
LOCAL_STEM=$CAPTURE_DIR/$CAPTURE_NAME
TRUTH_PATH=$CAPTURE_DIR/${CAPTURE_NAME}_tx_truth.json
TRANSFER_DIR=/home/$USER/GNSS_RX_Transfer/2026/2026_03_31/$CAPTURE_NAME

mkdir -p "$CAPTURE_DIR"
mkdir -p "$TRANSFER_DIR"
printf 'LOCAL_STEM=<%s>\n' "$LOCAL_STEM"
printf 'TRUTH_PATH=<%s>\n' "$TRUTH_PATH"
printf 'TRANSFER_DIR=<%s>\n' "$TRANSFER_DIR"

sudo chrt -f 50 env PYTHONPATH=src python3 scripts/record_rx.py \
    --config configs/rx_baremetal.yaml \
    --duration 250 \
    --capture-mode single \
    --output-stem "$LOCAL_STEM"
```

### 16.5 采后固定收尾流程

采集结束后，统一固定按下面 3 步执行，不建议跳步。

#### 第 1 步：先检查本地落盘

```bash
ls -lh "$CAPTURE_DIR"
```

本轮 `250 s` 已实测到的正常状态为：

- `.sc16` 已成功生成
- `.json` 已成功生成
- 当前目录量级约 `3.9G`，与 `250 s @ 4.092 Msps` 的预期一致

#### 第 2 步：固定补导或覆盖导出 `*_tx_truth.json`

无论 `11.1` 是否已经执行过，采后都推荐**再执行一次**下面这条 dry-run 导出命令，把 sidecar truth 固定写回当前 `CAPTURE_DIR`：

```bash
cd ~/projects/gnss_tx
source .venv/bin/activate

CAPTURE_NAME=20260331_ber250s_localdisk_rawiq_sc16_zeroif_prn1_spread_sr4092000_cf100000000_dur250p0s
CAPTURE_DIR=/home/$USER/GNSS_RX_Data_local/2026/2026_03_31/$CAPTURE_NAME
TRUTH_PATH=$CAPTURE_DIR/${CAPTURE_NAME}_tx_truth.json

PYTHONPATH=src python3 scripts/run_tx.py \
    --config configs/tx_b210_cable_loopback.yaml \
    --tx-gain 50 \
    --amplitude 1.0 \
    --dry-run \
    --export-truth-json "$TRUTH_PATH"
```

这样做的目的不是重新发射，而是确保本轮目录下**必定**存在与当前 `CAPTURE_NAME` 绑定的 sidecar truth。

#### 第 3 步：确认三件套后再复制

先确认：

```bash
ls -lh "$CAPTURE_DIR"
```

同目录下应同时存在：

- `<capture_stem>.sc16`
- `<capture_stem>.json`
- `<capture_stem>_tx_truth.json`

确认无误后，若此时**已经插上移动硬盘**，推荐直接复制整个 `<capture_dir>`，不要再手工拆成三条文件复制命令。

推荐命令如下：

```bash
DRIVE_NAME=<drive_name>
DRIVE_ROOT="/media/$USER/$DRIVE_NAME"
DEST_PARENT="$DRIVE_ROOT/GNSS_RX_Data_local/2026/2026_03_31"
DEST_DIR="$DEST_PARENT/$CAPTURE_NAME"

printf 'DRIVE_ROOT=<%s>\n' "$DRIVE_ROOT"
printf 'DEST_DIR=<%s>\n' "$DEST_DIR"

mkdir -p "$DEST_PARENT"
cp -av "$CAPTURE_DIR" "$DEST_PARENT"/
sync
ls -lh "$DEST_DIR"
```

本轮 `ls /media/$USER` 已实测为：

```text
Seagate Basic
```

因此当前可直接写成：

```bash
DRIVE_ROOT="/media/$USER/Seagate Basic"
DEST_PARENT="$DRIVE_ROOT/GNSS_RX_Data_local/2026/2026_03_31"
DEST_DIR="$DEST_PARENT/$CAPTURE_NAME"

mkdir -p "$DEST_PARENT"
cp -av "$CAPTURE_DIR" "$DEST_PARENT"/
sync
ls -lh "$DEST_DIR"
```

复制完成后，`$DEST_DIR` 下应继续同时包含：

- `<capture_stem>.sc16`
- `<capture_stem>.json`
- `<capture_stem>_tx_truth.json`

若当前还**没有**插上移动硬盘，才退回到先复制到本机 `TRANSFER_DIR` 的旧流程：

```bash
cp -v "$(dirname "$LOCAL_STEM")"/*.json "$TRANSFER_DIR"/
cp -v "$(dirname "$LOCAL_STEM")"/*.sc16 "$TRANSFER_DIR"/
cp -v "$TRUTH_PATH" "$TRANSFER_DIR"/
ls -lh "$TRANSFER_DIR"
```

额外说明：

- 若 `record_rx.py` 是通过 `sudo chrt -f 50 ...` 启动，生成的 `.sc16/.json` 可能显示为 `root:root` 属主
- 只要文件权限仍是可读的（例如 `-rw-r--r--`），后续 `ls`、`cp`、移动硬盘转运通常仍可继续
- 若后面确实遇到权限问题，再单独执行 `sudo chown -R $USER:$USER "$CAPTURE_DIR"` 修正属主

### 16.6 文件量级

`250 s @ 4.092 Msps` 的 `.sc16` 大约为：

- 约 `4.09 GB` 十进制
- 约 `3.81 GiB` 二进制

### 16.6.1 移动硬盘回到 Windows 后的 MATLAB 验证命令

当移动硬盘重新插回 Windows 主力 MATLAB 分析机后，推荐先不要直接跑 `ber`，而是先在 MATLAB 命令行里完成下面这组验证。

先确认 Windows 端 MATLAB 代码目录：

```matlab
CODE_ROOT = 'E:\MATLAB_code_Gongwei_Local\GNSS_RX_matlab';
cd(CODE_ROOT)
addpath(pwd)
addpath(fullfile(pwd, 'functions'))
addpath(fullfile(pwd, 'scripts'))
rehash

which ber -all
which run_ber_loopback -all
which run_prn_acquisition -all
which recover_nav_bits -all
which gnss_rx_resolve_accel_options -all
```

本轮已实测通过，下面这组输出就表示“代码侧验证通过，可以继续往下执行”：

```text
E:\MATLAB_code_Gongwei_Local\GNSS_RX_matlab\ber.m
E:\MATLAB_code_Gongwei_Local\GNSS_RX_matlab\scripts\run_ber_loopback.m
E:\MATLAB_code_Gongwei_Local\GNSS_RX_matlab\functions\run_prn_acquisition.m
E:\MATLAB_code_Gongwei_Local\GNSS_RX_matlab\functions\recover_nav_bits.m
E:\MATLAB_code_Gongwei_Local\GNSS_RX_matlab\functions\gnss_rx_resolve_accel_options.m
```

只要 `which ... -all` 全部指向 `E:\MATLAB_code_Gongwei_Local\GNSS_RX_matlab\...`，就说明：

- MATLAB 已经加载到本轮正确代码副本
- 不再受旧目录或网络盘 `Z:` 干扰
- 可以继续执行下面的“移动硬盘盘符确认”和“采集三件套验证”

若不确定移动硬盘当前在 Windows 上的盘符，可以先在 MATLAB 中执行：

```matlab
system('powershell -NoProfile -Command "Get-Volume | Select DriveLetter, FileSystemLabel | Format-Table -AutoSize"')
```

假设移动硬盘当前盘符为 `F:`，则继续执行：

```matlab
CAPTURE_DIR = ['F:\GNSS_RX_Data_local\2026\2026_03_31\' ...
    '20260331_ber250s_localdisk_rawiq_sc16_zeroif_prn1_spread_sr4092000_' ...
    'cf100000000_dur250p0s'];

CAPTURE_STEM = fullfile(CAPTURE_DIR, ...
    '20260331_ber250s_localdisk_rawiq_sc16_zeroif_prn1_spread_sr4092000_cf100000000_dur250p0s');

dir(CAPTURE_DIR)
exist([CAPTURE_STEM '.sc16'], 'file')
exist([CAPTURE_STEM '.json'], 'file')
exist([CAPTURE_STEM '_tx_truth.json'], 'file')
truth = load_tx_truth_json([CAPTURE_STEM '_tx_truth.json']);
disp(truth.prn_id)
disp(truth.sample_rate)
```

本轮已实测通过，出现下面这类结果就表示“采集三件套 + sidecar truth 验证通过”：

```text
ans =

     2

ans =

     2

ans =

     2

     1

     4092000
```

其中含义为：

- 前面 3 个 `ans = 2` 表示：
  - `[CAPTURE_STEM '.sc16']` 存在
  - `[CAPTURE_STEM '.json']` 存在
  - `[CAPTURE_STEM '_tx_truth.json']` 存在
- `disp(truth.prn_id)` 输出 `1`，说明读取到的 truth 对应 `PRN 1`
- `disp(truth.sample_rate)` 输出 `4092000`，说明 truth 中的采样率与本轮基线一致

只要你看到的是这一类结果，就说明：

- Windows 已能正常读取移动硬盘上的本轮采集目录
- sidecar truth 与本轮文件名绑定正确
- 可以继续进入下面的正式 `ber` 步骤

这一步的目标不是先出 BER 数值，而是先确认：

- MATLAB 已从 `E:\MATLAB_code_Gongwei_Local\GNSS_RX_matlab` 加载到正确代码
- 移动硬盘上的 `250 s` 目录确实能被 Windows 正常读到
- `.sc16`、`.json`、`_tx_truth.json` 三件套齐全
- `load_tx_truth_json(...)` 能正常解析 sidecar truth

以上都通过后，再进入后面的正式 `ber` 步骤。

### 16.6.2 验证通过后的正式 `ber` 命令

当 `which ... -all`、`exist(...)`、`load_tx_truth_json(...)` 都通过后，默认按 **GPU 加速优先** 的版本执行正式 BER：

推荐先单独完成一次“GPU 启动检查”，再运行 `ber`：

```matlab
parallel.gpu.enableCUDAForwardCompatibility(true);
gpuDeviceCount
g = gpuDevice;
disp(g.Name)
disp(g.ComputeCapability)
```

只要这组命令能正常返回设备对象，就说明本轮 MATLAB 已经完成 GPU 绑定，可以继续把 `ACCEL_OPTIONS` 设为 GPU。

本轮已实测通过，实际输出为：

```text
ans =

     1

警告: 将重新编译 GPU 库，因为您的设备比库更新。编译可能需要几分钟时间。

NVIDIA GeForce RTX 5060
12.0
```

这组结果的含义是：

- `gpuDeviceCount = 1`：MATLAB 已检测到 1 块可见 GPU
- `gpuDevice` 能成功返回设备对象：说明启用 `parallel.gpu.enableCUDAForwardCompatibility(true)` 后，GPU 已可被当前 MATLAB 会话实际使用
- `NVIDIA GeForce RTX 5060`：当前绑定到的 GPU 设备名称
- `12.0`：该卡的 `ComputeCapability`
- “将重新编译 GPU 库”警告：属于 forward compatibility 模式下的预期现象，首次绑定新架构 GPU 时可能需要额外编译时间；只要后续没有报错中断，就不视为失败

因此，本轮这组输出应判定为：

```text
GPU 启动检查通过，可以继续按 GPU 版本运行 ber
```

```matlab
CODE_ROOT = 'E:\MATLAB_code_Gongwei_Local\GNSS_RX_matlab';
cd(CODE_ROOT)
addpath(pwd)
addpath(fullfile(pwd, 'functions'))
addpath(fullfile(pwd, 'scripts'))
clear functions
rehash

parallel.gpu.enableCUDAForwardCompatibility(true);
ACCEL_OPTIONS = struct( ...
    'backend', 'gpu', ...
    'precision', 'single', ...
    'batch_ms', 2000);

DRIVE = 'F:';  % 按当前移动硬盘实际盘符替换
CAPTURE_STEM = [DRIVE '\GNSS_RX_Data_local\2026\2026_03_31\' ...
    '20260331_ber250s_localdisk_rawiq_sc16_zeroif_prn1_spread_sr4092000_' ...
    'cf100000000_dur250p0s\20260331_ber250s_localdisk_rawiq_sc16_zeroif_' ...
    'prn1_spread_sr4092000_cf100000000_dur250p0s'];

CAPTURE_PATH = CAPTURE_STEM;
BER_MODE = 'tracked_truth';

ber
```

本轮 GPU 相关背景如下：

```matlab
gpuDevice
```

本轮实测中，`gpuDeviceCount` 返回 `1`，说明 MATLAB 能看到 GPU；但 `gpuDevice` 报错提示该卡的 `compute capability 12.0` 高于当前 MATLAB 内置 CUDA 库原生支持范围，因此需要先启用：

```matlab
parallel.gpu.enableCUDAForwardCompatibility(true)
```

也就是说，上面正式 `ber` 命令里的这两行：

```matlab
parallel.gpu.enableCUDAForwardCompatibility(true);
ACCEL_OPTIONS = struct('backend', 'gpu', 'precision', 'single', 'batch_ms', 2000);
```

就是本轮默认推荐的 GPU 版本。

结合当前 MATLAB 代码实现，可把”GPU 真正参与了哪些环节”理解为：

- `run_prn_acquisition`：会在 GPU 路径下调用 `compute_search_map_gpu(...)`，用 `gpuArray + FFT/IFFT` 完成捕获搜索
- `recover_nav_bits`：会在 `gpu_enabled=true` 时，把批量相关求和放到 GPU 上执行
- tracking 主链（A 类 GPU，`gpu_enabled=true` 时自动激活）：
  - `estimate_initial_bit_alignment`：20 种 bit 边界 × pattern_len × 极性 的打分矩阵，GPU 批量计算
  - `check_bit_timing_stability`：每个窗口内 20 个偏移量的 bit 积分，GPU 向量化
  - `integrate_bits_from_prompt`：20ms 积分 reshape+sum，GPU 执行
- tracking DLL 主循环（B 类 GPU，需额外设置 `dll_gpu_enabled=true`）：
  - `track_code_phase_ms`：批处理段矩阵 GPU 矩阵乘，然后 CPU 串行更新 cursor
  - 默认**关闭**，需在 BER 验证通过后才推荐开启（见第二十五节）

因此本轮判断”GPU 已生效”的标准，不是要求所有步骤都显示 GPU，而是看：

- `gpuDevice` 能否正常返回设备对象
- `ACCEL_OPTIONS.backend='gpu'` 后，日志中的 `resolved=gpu`
- 日志中能打印出 `GPU 设备：[index] name`
- Step 4 日志显示 `Step 4 实际后端：gpu`

代码更新后（tracking 主链 A 类 GPU 已激活），`backend=gpu` 时 Step 4 的预期日志格式如下：

```text
加速配置：requested=gpu, resolved=gpu, precision=single, batch_ms=2000, parfor=0
GPU 设备：[1] NVIDIA GeForce RTX 5060
=== Step 2: GPS L1 C/A 捕获 ===
Step 2 后端：gpu（precision=single）
捕获成功！Doppler = 0.0 Hz，码相位 = 2954 samples，次峰比 = 105.54
TX truth：JSON 模式（capture sidecar truth）
=== Step 3: open-loop truth 基线 ===
Step 3 后端：gpu（precision=single, batch_ms=2000）
=== Step 4: tracked BER 主链 ===
Step 4 后端：gpu
tracked BER：1.20e-03，匹配率：100.0%，bit 偏移：15 ms，pattern 偏移：7 bit
Step 4 用时：XX.XX s
Step 4 实际后端：gpu
========================================
  BER：         1.20e-03
  总发送比特数：12499
  误码个数：    15
  truth 匹配率：100.0%
  加速后端：    gpu
========================================
```

关键判断：

- GPU 配置已生效：日志显示 `requested=gpu, resolved=gpu`
- GPU 已参与 Step 2 / Step 3：捕获与 open-loop 相关计算走 GPU 路径
- Step 4 tracking 三个子函数（bit 对齐打分 / bit 稳定性检查 / bit 积分）现在走 GPU 路径
- `Step 4 实际后端：gpu` 是本轮新增的日志行，验证 tracking 链实际使用了 GPU
- `BER = 1.20e-03`、`truth 匹配率 = 100.0%` 应与之前 CPU 基线完全一致（Phase A 改动不引入数值近似）
- sidecar truth 已正确命中：日志显示 `TX truth：JSON 模式（capture sidecar truth）`

> **注意**：若使用 `backend=cpu`，Step 4 日志将显示 `Step 4 后端：cpu` 和 `Step 4 实际后端：cpu`，这是正常的 CPU 路径。

本轮末尾还出现过：

```text
警告: 将图例条目限制为 50 个。
```

这属于绘图阶段的 legend 数量提示，不影响 BER 数值本身，也不影响本轮结果判定。

若你不想承担 forward compatibility 的额外不确定性，则继续保持 CPU 也完全可行；当前代码默认就是：

```matlab
ACCEL_OPTIONS = struct();
```

也就是 `requested=cpu, resolved=cpu, precision=double, batch_ms=2000, parfor=0`。

额外说明：

- 从本轮起，若你把 `ACCEL_OPTIONS.backend` 设为 `'auto'`，但 GPU 初始化失败，代码会自动回退到 CPU 并打印回退原因
- 若你显式设为 `'gpu'`，则仍保持严格模式，GPU 初始化失败时直接报错

这一步的预期现象是：

- `ber` 能正常启动，不报“未找到函数”或“找不到采集文件”
- 日志中优先使用 capture sidecar truth
- BER 计算开始进入 acquisition / tracking / bit recovery 流程

若你希望先做一次更稳妥的显式检查，也可以在 `ber` 前先执行：

```matlab
disp(CAPTURE_PATH)
exist([CAPTURE_PATH '.json'], 'file')
exist([CAPTURE_PATH '.sc16'], 'file')
exist([CAPTURE_PATH '_tx_truth.json'], 'file')
```

### 16.7 正式验收目标

- 恢复总比特数 `>= 1e4`
- 总 BER 保持低误码
- 无长时间失锁区间
- TX 无 underflow
- RX 无 overflow

---

## 十七、联机 1 h 长时稳定性验证

### 17.1 统一口径

1 h 阶段默认正式策略固定为：

- RX 使用 `chunked`
- `--chunk-duration 30`
- TX 保持当前稳定基线
- TX 发射覆盖时长必须大于 RX 总采集时长

### 17.2 为什么默认 `chunked`

因为 `1 h` 原始 IQ 总体量约：

- 约 `58.9 GB` 十进制
- 约 `54.9 GiB` 二进制

对单文件、单次写盘、后续转移和分析都更不友好。

而 `chunked` 下：

- 总时长 `3600 s`
- chunk 时长 `30 s`
- 总 chunk 数 `120`
- 每段 `.sc16` 约 `0.49 GB`

这样更适合：

- 采集中途检查
- 采后搬运
- 逐段复盘

### 17.3 先做 dry-run

先检查 chunked 方案：

```bash
cd ~/projects/GNSS_RX
source .venv/bin/activate
PYTHONPATH=src python3 scripts/record_rx.py \
    --config configs/rx_baremetal.yaml \
    --duration 3600 \
    --capture-mode chunked \
    --chunk-duration 30 \
    --dry-run
```

再保留一个 single 方案做备选 dry-run，仅供确认接口还可用：

```bash
cd ~/projects/GNSS_RX
source .venv/bin/activate
PYTHONPATH=src python3 scripts/record_rx.py \
    --config configs/rx_baremetal.yaml \
    --duration 3600 \
    --capture-mode single \
    --dry-run
```

### 17.4 TX 端正式命令

建议 TX 至少覆盖 `3660 s`，留出前后边界裕量：

```bash
cd ~/projects/gnss_tx
source .venv/bin/activate
sudo chrt -f 50 env PYTHONPATH=src python3 scripts/run_tx.py \
    --config configs/tx_b210_cable_loopback.yaml \
    --tx-gain 50 \
    --amplitude 1.0 \
    --duration 3660
```

### 17.5 RX 端正式命令

```bash
cd ~/projects/GNSS_RX
source .venv/bin/activate

sudo chrt -f 50 env PYTHONPATH=src python3 scripts/record_rx.py \
    --config configs/rx_baremetal.yaml \
    --duration 3600 \
    --capture-mode chunked \
    --chunk-duration 30
```

### 17.6 1 h 阶段的分析建议

1 h 阶段不建议一上来就尝试把所有 chunk 直接拼成一个“单次正式 BER 结论”。

更稳妥的做法是：

1. 先确认 chunked 采集本身全程无 overflow
2. 先抽查前、中、后几个 chunk 做 `ber`
3. 若抽查稳定，再决定是否做更大范围离线汇总

---

## 十八、移动硬盘转移流程

本节适用于：

- 从裸机 Ubuntu 把采集数据带回主力机
- 或把数据临时放到可移动介质再分析

本轮默认口径：

- 采集时先把数据写到 Ubuntu 本地目录 `~/GNSS_RX_Data_local/`
- 采集完成后，再把目标轮次目录复制到移动硬盘
- 不要求在 TX/RX 正在运行时同时挂着移动硬盘

### 18.1 找到移动硬盘挂载点

```bash
lsblk
ls /media/$USER/
```

### 18.2 推荐复制方式

假设本轮目录是：

```bash
CAPTURE_NAME=20260331_ber250s_localdisk_rawiq_sc16_zeroif_prn1_spread_sr4092000_cf100000000_dur250p0s
CAPTURE_DIR=/home/$USER/GNSS_RX_Data_local/2026/2026_03_31/$CAPTURE_NAME
```

则推荐复制方式为：

```bash
mkdir -p /media/$USER/<drive_name>/GNSS_RX_Data_local/2026/2026_03_31
cp -av "$CAPTURE_DIR" /media/$USER/<drive_name>/GNSS_RX_Data_local/2026/2026_03_31/
sync
```

若目录名含空格，例如 `Seagate Basic`：

```bash
mkdir -p "/media/$USER/Seagate Basic/GNSS_RX_Data_local/2026/2026_03_31"
cp -av "$CAPTURE_DIR" "/media/$USER/Seagate Basic/GNSS_RX_Data_local/2026/2026_03_31/"
sync
```

### 18.3 建议一起转移的文件

- 对应轮次的整目录 `<capture_dir>/`
- 其中应同时包含 `.sc16`、`.json`、`_tx_truth.json`
- 若需要复盘，还可额外保存 TX / RX 终端日志

---

## 十九、主力机 MATLAB 正式 BER 分析

本节是全手册最关键的“结论出口”。

### 19.1 统一原则

- 正式 BER 用 `ber`
- 正式 BER 模式用 `tracked_truth`
- 默认显式指定 `CAPTURE_PATH`
- 默认让 `ber` 自动优先匹配 capture sidecar truth
- 根目录 `GNSS_RX_matlab/tx_truth.json` 只作为兼容旧流程的 fallback

### 19.2 Windows 主力机：推荐方案

推荐先把移动硬盘数据复制到本地 SSD，再分析。

推荐目录结构：

```text
C:\VMwareVirtualMachines\GongXiangDocument\
├── GNSS_RX_matlab\
└── GNSS_RX_Data_baremetal\
```

若要让“自动找最新采集”也能工作，可在：

`GNSS_RX_matlab\gnss_rx_user_paths.m`

中写：

```matlab
GNSS_RX_DATA_DIR = 'C:\VMwareVirtualMachines\GongXiangDocument\GNSS_RX_Data_baremetal';
```

#### Windows 正式 BER 示例：本地 SSD 版本

```matlab
cd('C:\VMwareVirtualMachines\GongXiangDocument\GNSS_RX_matlab')
clear functions
rehash

CAPTURE_PATH = ['C:\VMwareVirtualMachines\GongXiangDocument\GNSS_RX_Data_baremetal\2026\' ...
    '2026_03_31\20260331_ber250s_localdisk_rawiq_sc16_zeroif_prn1_spread_' ...
    'sr4092000_cf100000000_dur250p0s\20260331_ber250s_localdisk_rawiq_' ...
    'sc16_zeroif_prn1_spread_sr4092000_cf100000000_dur250p0s'];
BER_MODE = 'tracked_truth';

ber
```

### 19.3 Windows 主力机：移动硬盘直读方案

此方案保留完整命令，但默认不推荐。

适用场景：

- 临时快速复盘
- 本地 SSD 空间不足
- 只想先验证某一份文件能否跑通

注意事项：

- 分析过程中不要拔出移动硬盘
- 若盘符变化，必须同步改路径
- 速度与稳定性通常不如先拷到本地 SSD

假设移动硬盘盘符为 `F:`，则：

```matlab
cd('C:\VMwareVirtualMachines\GongXiangDocument\GNSS_RX_matlab')
clear functions
rehash

CAPTURE_PATH = ['F:\GNSS_RX_Data_baremetal\2026\2026_03_31\' ...
    '20260331_ber250s_localdisk_rawiq_sc16_zeroif_prn1_spread_sr4092000_' ...
    'cf100000000_dur250p0s\20260331_ber250s_localdisk_rawiq_sc16_zeroif_' ...
    'prn1_spread_sr4092000_cf100000000_dur250p0s'];
BER_MODE = 'tracked_truth';

ber
```

若你希望让“自动找最新采集”直接指向移动硬盘，也可以写：

```matlab
GNSS_RX_DATA_DIR = 'F:\GNSS_RX_Data_baremetal';
```

#### Windows 直读现有目录示例：`20260330_025519...dur300p0s`

如果你手头已经有下面这类目录，并且目录里至少有同名的 `.json` 与 `.sc16`：

```text
F:\GNSS_RX_Data_baremetal\2026\2026_03_30\
  20260330_025519_rawiq_sc16_zeroif_prn1_spread_sr4092000_cf100000000_dur300p0s\
    20260330_025519_rawiq_sc16_zeroif_prn1_spread_sr4092000_cf100000000_dur300p0s.json
    20260330_025519_rawiq_sc16_zeroif_prn1_spread_sr4092000_cf100000000_dur300p0s.sc16
    20260330_025519_rawiq_sc16_zeroif_prn1_spread_sr4092000_cf100000000_dur300p0s_tx_truth.json
```

则在 MATLAB 中推荐直接传 stem 路径：

```matlab
cd('C:\VMwareVirtualMachines\GongXiangDocument\GNSS_RX_matlab')
clear functions
rehash

CAPTURE_PATH = ['F:\GNSS_RX_Data_baremetal\2026\2026_03_30\' ...
    '20260330_025519_rawiq_sc16_zeroif_prn1_spread_sr4092000_' ...
    'cf100000000_dur300p0s\20260330_025519_rawiq_sc16_zeroif_' ...
    'prn1_spread_sr4092000_cf100000000_dur300p0s'];
BER_MODE = 'tracked_truth';
```

若同目录下还有 `<capture_stem>_tx_truth.json`，则此时直接执行：

```matlab
ber
```

脚本会优先把它识别为本轮 sidecar truth。

若 sidecar truth 不存在，但 `GNSS_RX_matlab` 根目录下有兼容旧流程的 `tx_truth.json`，`ber` 也仍可继续跑；只是该 truth 已降级为 fallback。

若当前只有 `.json + .sc16`，还没有与该轮 TX 参数一致的 truth JSON，则先做二选一：

- 只想确认样本能否加载、能否捕获：运行 `result = run_capture_analysis(CAPTURE_PATH);`
- 想继续跑完整 BER 链路用于诊断：可直接执行 `ber`，但日志会回退到 `TX truth：fallback 模式`，该结果默认不作为正式 BER 验收结论

补充说明：

- `CAPTURE_PATH` 也可以直接写成 `.json` 或 `.sc16` 文件路径，不一定非要 stem
- 正式 BER 验收时，仍以日志出现 `TX truth：JSON 模式` 为准
- 如果 sidecar truth 与 `GNSS_RX_matlab` 根目录 `tx_truth.json` 同时存在，当前默认优先使用 sidecar truth
- 只有在 sidecar truth 缺失时，`ber` 才会回退到 `GNSS_RX_matlab` 根目录下的 `tx_truth.json`

### 19.4 Linux 主力机正式 BER 示例

若主力机本身就是 Linux，并且 MATLAB 直接在 Linux 上运行：

```matlab
cd('/home/shenao/projects/GNSS_RX/matlab')
clear functions
rehash

CAPTURE_PATH = ['/home/shenao/GNSS_RX_Data_baremetal/2026/2026_03_31/' ...
    '20260331_ber250s_localdisk_rawiq_sc16_zeroif_prn1_spread_sr4092000_' ...
    'cf100000000_dur250p0s/20260331_ber250s_localdisk_rawiq_sc16_zeroif_' ...
    'prn1_spread_sr4092000_cf100000000_dur250p0s'];
BER_MODE = 'tracked_truth';

run('scripts/run_ber_loopback.m')
```

### 19.5 可选加速配置

#### 推荐：GPU 加速（Step 2 + Step 3 + tracking A 类子函数）

```matlab
parallel.gpu.enableCUDAForwardCompatibility(true);  % RTX 5060 等新架构 GPU 需要
ACCEL_OPTIONS = struct( ...
    'backend', 'gpu', ...
    'precision', 'single', ...
    'batch_ms', 2000);
```

`gpu_enabled=true` 时，以下子函数自动走 GPU 路径（Phase A，已默认激活）：

- `estimate_initial_bit_alignment`：bit 对齐打分矩阵
- `check_bit_timing_stability`：bit 稳定性检查积分
- `integrate_bits_from_prompt`：20ms bit 积分

#### 可选：同时开启 DLL 批处理 GPU 路径（Phase B，需先完成 BER 一致性验证）

```matlab
parallel.gpu.enableCUDAForwardCompatibility(true);
ACCEL_OPTIONS = struct( ...
    'backend', 'gpu', ...
    'precision', 'single', ...
    'batch_ms', 100, ...
    'dll_gpu_enabled', true);
```

> 注意：`dll_gpu_enabled=true` 引入批次内 cursor 近似，建议先按第二十五节做 CPU vs GPU BER 对比验证再开启。推荐先用 `batch_ms=100` 验证通过后，再逐步提高至 500。

#### 若希望自动回退（GPU 不可用时降 CPU）

```matlab
ACCEL_OPTIONS = struct('backend', 'auto', 'precision', 'single');
```

#### 若希望强制 CPU（基准对比用）

```matlab
ACCEL_OPTIONS = struct('backend', 'cpu', 'precision', 'double');
```

### 19.6 采后快速体检命令

如需先看 overview / acquisition / survey，可执行：

```matlab
result = run_capture_analysis(CAPTURE_PATH);
```

再次强调：

- 这是快速体检
- 不是正式 BER 统计

---

## 二十、如何解读正式 BER 结果

建议按以下顺序读结果。

### 20.1 先看 `BER`

这是第一结论位。

### 20.2 再看 `truth 匹配率`

若太低，优先怀疑 truth mismatch 或 bit timing 歧义，而不是先怀疑单纯误码。

### 20.3 再看 `ambiguity_flag`

若为 `true`，说明最优对齐和次优对齐过近，当前结论不够稳。

### 20.4 再结合图和事件

重点看：

- `Tracked 误码位置`
- 局部 BER
- `Tracking 状态`
- `reacq_events`

### 20.5 当前推荐判读口径

- `BER` 很低且 `truth 匹配率` 很高：可计入有效样本
- 前半段好、后半段突然坏：优先怀疑 overflow 或时间连续性破坏
- `match_rate < 55%`：更像 truth mismatch 或 timing ambiguity
- `ambiguity_flag = true`：暂不下最终结论，先排对齐问题

---

## 二十一、正式验收标准

### 21.1 固定 30 s 样本

- `tracked_truth` BER `< 1e-3`
- `ambiguity_flag = false`
- tracking 曲线整体平稳

### 21.2 新的 30 s 联机复验

- 连续 `3` 次低误码
- TX 无 underflow
- RX 无 overflow

### 21.3 `100 s`

- 本地落盘 + 采后复制流程打通
- 无 overflow / underflow
- MATLAB 分析结果稳定

### 21.4 `250 s`

- 恢复总比特数 `>= 1e4`
- 总 BER 保持低误码
- 无长时间失锁区间

### 21.5 `1 h`

- `chunked` 方案 dry-run 正常
- 长时采集全程无 overflow / underflow
- 抽查多个 chunk 的 BER 稳定

---

## 二十二、失败时优先怎么排

### 22.1 若 `ber` 找不到

优先检查：

```matlab
which ber -all
which run_ber_loopback -all
```

以及是否刚执行过：

```bash
./scripts/sync_matlab.sh ...
```

### 22.2 若日志显示 fallback truth

说明当前没有正确加载 `tx_truth.json`。先修 truth 来源，再谈正式 BER。

### 22.3 若 TX 有 `U`

说明存在 underflow。优先：

- 降低系统干扰
- 提升调度优先级
- 保持 TX/RX 基线不变，不先乱改 truth 或 MATLAB 脚本

### 22.4 若 RX 有 `O`

说明存在 overflow。优先：

- 先本地落盘，不要直写共享目录
- 检查 USB 3.x
- 检查磁盘吞吐
- 检查是否需要 `sudo chrt -f 50`

### 22.5 若固定 30 s 都不收敛

排查顺序：

1. MATLAB 是否仍在跑旧文件
2. `ber` / `run_ber_loopback.m` 是否为新版本
3. `TX truth：JSON 模式` 是否成立
4. tracking 曲线是否稳定
5. 真值字段是否与 TX dry-run 摘要一致

不要一上来就：

- 改 nav pattern
- 盲目改增益
- 直接跳去做更长采集

---

## 二十三、最终最短执行路径

如果你今天的目标只是“把整条链跑通并拿到可信 BER”，最短路径如下：

1. 新裸机 Ubuntu 安装依赖
2. 获取 `gnss_tx` 和 `GNSS_RX`
3. 创建两边 `.venv --system-site-packages`
4. `uhd_find_devices` + `lsusb -t` 验证硬件
5. TX / RX `dry-run`
6. 导出 `tx_truth.json`
7. 同步 MATLAB 工作区
8. 先跑固定旧样本的 `ber`
9. 新采 `30 s`
10. 再做 `100 s`
11. 正式做 `250 s`
12. 需要长稳验证时再做 `1 h chunked`

---

## 二十四、全流程验收清单

- [ ] 裸机 Ubuntu 系统依赖安装完成
- [ ] `uhd_images_downloader` 已执行
- [ ] 两个仓库已放到同一台裸机电脑
- [ ] `gnss_tx/.venv` 使用 `--system-site-packages`
- [ ] `GNSS_RX/.venv` 使用 `--system-site-packages`
- [ ] `uhd_find_devices` 枚举到 `serial=193982` 和 `serial=8003272`
- [ ] `lsusb -t` 显示两块 B210 运行在 `5000M`
- [ ] TX dry-run 正常
- [ ] RX dry-run 正常
- [ ] `tx_truth.json` 已导出
- [ ] MATLAB 工作区已同步
- [ ] 主力机 MATLAB 能找到 `ber`
- [ ] 固定旧样本的 `tracked_truth` 已跑通
- [ ] 新的 `30 s` 采集无 `U` / `O`
- [ ] `100 s` 采集无 `U` / `O`
- [ ] `250 s` 采集无 `U` / `O`
- [ ] `1 h` 默认采用 `chunked`
- [ ] 正式 BER 结论基于 `tracked_truth`
- [ ] `run_capture_analysis()` 仅作为快速体检使用

---

## 二十五、tracking 主链 GPU 加速：测试与验证步骤

本节对应代码改动：`matlab/functions/track_nav_bits.m`（Phase A + B）和 `matlab/scripts/run_ber_loopback.m`（Phase C 日志更新）。

### 25.1 改动概述

| Phase | 子函数 | 触发条件 | 说明 |
| --- | --- | --- | --- |
| A1 | `integrate_bits_from_prompt` | `gpu_enabled=true` | 20ms reshape+sum → GPU |
| A2 | `estimate_initial_bit_alignment` | `gpu_enabled=true` | 打分矩阵批量 GPU 计算 |
| A3 | `check_bit_timing_stability` | `gpu_enabled=true` | 窗口 bit 积分 GPU 向量化 |
| B | `track_code_phase_ms` | `dll_gpu_enabled=true` | DLL 批处理 GPU 矩阵乘（有近似，默认关闭） |
| C | `run_ber_loopback.m` 日志 | 无条件 | Step 4 日志从硬编码 `cpu` 改为动态读取后端 |

Phase A 无数值近似，结果应与 CPU 完全一致。Phase B 批次内 cursor 近似，BER 不保证 bit 精确一致，但不应影响整体 BER 量级。

### 25.2 Step 1：环境准备（代码同步）

若在 Linux 主力机上直接修改了仓库，直接用；若在 Windows 上需要从 Ubuntu 侧同步：

```bash
cd ~/projects/GNSS_RX
bash ./scripts/sync_matlab.sh <MATLAB_WORKSPACE_DIR>
```

然后在 MATLAB 中重新加载：

```matlab
cd('<MATLAB_WORKSPACE_DIR>')
clear functions
rehash

which track_nav_bits -all
which gnss_rx_resolve_accel_options -all
which run_ber_loopback -all
```

三个函数都应指向本轮同步后的目录。

### 25.3 Step 2：GPU 设备确认

```matlab
parallel.gpu.enableCUDAForwardCompatibility(true);
gpuDeviceCount
g = gpuDevice;
disp(g.Name)
disp(g.ComputeCapability)
```

预期：`gpuDeviceCount >= 1`，`gpuDevice` 正常返回设备对象。若报错则说明 GPU 不可用，后续只做 CPU 路径验证。

### 25.4 Step 3：Phase A 验证（CPU vs GPU 结果对比）

使用现有固定样本，先跑 CPU 基准，再跑 GPU，对比 BER 数值和 bit 偏移。

```matlab
% ── CPU 基准 ──────────────────────────────────────────
CAPTURE_PATH = '<你的 CAPTURE_PATH>';  % 替换为实际路径
BER_MODE = 'tracked_truth';
ACCEL_OPTIONS = struct('backend', 'cpu', 'precision', 'double');

run('scripts/run_ber_loopback.m')
% 记录：BER_cpu、bit_offset_ms_cpu、pattern_offset_cpu、polarity_cpu
```

```matlab
% ── GPU Phase A（不开 DLL GPU）─────────────────────────
ACCEL_OPTIONS = struct('backend', 'gpu', 'precision', 'single', 'batch_ms', 2000);
parallel.gpu.enableCUDAForwardCompatibility(true);

run('scripts/run_ber_loopback.m')
% 记录：BER_gpu_A、bit_offset_ms_gpu、pattern_offset_gpu、polarity_gpu
```

验证通过标准：

- `BER_cpu` 与 `BER_gpu_A` 数值完全相同（或误差 < 1e-6）
- `bit_offset_ms`、`pattern_offset`、`polarity` 三个值完全一致
- `Step 4 实际后端：gpu` 出现在日志中
- BER 统计块出现 `加速后端：    gpu`

### 25.5 Step 4：Phase A 用时对比

查看两次运行的 `Step 4 用时` 打印行，记录：

```text
CPU：Step 4 用时：XX.XX s
GPU Phase A：Step 4 用时：XX.XX s
```

Phase A 的 GPU 收益主要来自 `estimate_initial_bit_alignment` 的打分矩阵（约 20 × pattern_len × 2 次打分），对于 30s 样本效果较小，对于 250s 以上长样本效果更明显。

### 25.6 Step 5：Phase B 验证（DLL GPU，batch_ms=100）

仅在 Step 3 验证通过（Phase A GPU 与 CPU 结果一致）后执行本步。

```matlab
% ── DLL GPU，batch_ms=100 ──────────────────────────────
parallel.gpu.enableCUDAForwardCompatibility(true);
ACCEL_OPTIONS = struct( ...
    'backend', 'gpu', ...
    'precision', 'single', ...
    'batch_ms', 100, ...
    'dll_gpu_enabled', true);

run('scripts/run_ber_loopback.m')
% 记录：BER_dll_gpu、bit_offset_ms、pattern_offset、Step 4 用时
```

验证通过标准：

- `bit_offset_ms`、`pattern_offset`、`polarity` 与 CPU 基准一致（这三个值不受 DLL 近似影响）
- `BER_dll_gpu` 与 CPU 基准在同一量级（允许个位数 bit 差异，不应相差 10 倍以上）
- Step 4 用时应明显低于 CPU 基准（预期 2–5×加速）

若通过，再做 `batch_ms=500` 版本：

```matlab
ACCEL_OPTIONS = struct( ...
    'backend', 'gpu', ...
    'precision', 'single', ...
    'batch_ms', 500, ...
    'dll_gpu_enabled', true);

run('scripts/run_ber_loopback.m')
```

### 25.7 Step 6：250s 正式样本完整验证

在长样本（250s）上重复 Step 3 和 Step 5，记录用时对比。

```matlab
% 设置 250s 样本路径
CAPTURE_PATH = '<250s CAPTURE_PATH>';  % 替换为实际路径
BER_MODE = 'tracked_truth';

% CPU 基准
ACCEL_OPTIONS = struct('backend', 'cpu');
run('scripts/run_ber_loopback.m')

% GPU Phase A
ACCEL_OPTIONS = struct('backend', 'gpu', 'precision', 'single', 'batch_ms', 2000);
run('scripts/run_ber_loopback.m')

% GPU Phase A + B（若 Step 5 已验证通过）
ACCEL_OPTIONS = struct('backend', 'gpu', 'precision', 'single', 'batch_ms', 500, 'dll_gpu_enabled', true);
run('scripts/run_ber_loopback.m')
```

### 25.8 预期日志格式（代码更新后）

无论 CPU 还是 GPU，Step 4 现在都会额外打印两行：

```text
=== Step 4: tracked BER 主链 ===
Step 4 后端：<resolved_backend>
tracked BER：X.XXe-XX，匹配率：XXX.X%，bit 偏移：XX ms，pattern 偏移：X bit
Step 4 用时：XX.XX s
Step 4 实际后端：<cpu 或 gpu>
```

BER 统计摘要新增一行：

```text
========================================
  BER 统计结果
========================================
  模式：        tracked_truth
  truth 模式：  ...
  总发送比特数：XXXXX
  误码个数：    XX
  BER：         X.XXe-XX
  bit 偏移：    XX ms
  pattern 偏移：X bit
  极性：        +1
  truth 匹配率：XXX.X%
  加速后端：    <cpu 或 gpu>
  捕获 Doppler：X.X Hz
  次峰比：      XX.XX
========================================
```

### 25.9 失败排查

| 现象 | 可能原因 | 处理方式 |
| --- | --- | --- |
| `Step 4 实际后端：cpu`（但 `ACCEL_OPTIONS.backend='gpu'`） | GPU 初始化失败或代码未同步 | 检查 `gpuDevice` 是否正常；重新 `clear functions` + `rehash` |
| Phase A GPU 与 CPU BER 不一致 | `precision='single'` 引入 bit 级舍入 | 改为 `precision='double'` 对比；若仍不一致报 bug |
| Phase B GPU `bit_offset_ms` 与 CPU 不一致 | 不可能，`bit_offset_ms` 来自 `estimate_initial_bit_alignment`（Phase A），不受 DLL 近似影响 | 确认 Phase A 已先单独验证通过 |
| Phase B GPU BER 明显偏高 | `batch_ms` 过大，批次内 cursor 漂移超过阈值 | 降低 `batch_ms`（先试 50，再 100） |
| `gpuDevice` 报错 | 新架构 GPU 未启用 forward compatibility | 先执行 `parallel.gpu.enableCUDAForwardCompatibility(true)` |
