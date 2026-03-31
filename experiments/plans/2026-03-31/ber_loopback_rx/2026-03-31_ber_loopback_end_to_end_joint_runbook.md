# 闭环 BER 全链路总手册（TX/RX 一体版）

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

- 从裸机笔记本转运采集数据
- 可选转运 `tx_truth.json`
- 可选作为 Windows 主力机的“临时直读数据盘”

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
  ├─ tx_truth.json
  └─ <capture>.sc16 + <capture>.json
            ↓
        移动硬盘
            ↓
      Windows / Linux 主力机
            ↓
      GNSS_RX_matlab / GNSS_RX/matlab
            ↓
      ber → run_ber_loopback.m → tracked_truth BER
```

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

`tx_truth.json` 不是采集文件，也不是 BER 结果文件，它是 TX 发射前导出的“真值契约”。

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

### 11.1 裸机 Linux 本地保存版本

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

### 11.2 若主力机为 Windows 且使用 VMware 共享目录

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

### 11.3 完成标志

- `tx_truth.json` 已成功生成
- dry-run 摘要中的 `nav_pattern`、`initial_nav_epoch`、`initial_nav_bit_index` 与当前基线一致
- 后续 MATLAB 正式 BER 日志能看到 `TX truth：JSON 模式`

---

## 十二、同步 MATLAB 工作区

### 12.1 同步入口

唯一推荐同步方式：

```bash
cd ~/projects/GNSS_RX
./scripts/sync_matlab.sh /mnt/hgfs/GongXiangDocument/GNSS_RX_matlab
```

同步内容包括：

- `functions/`
- `scripts/`
- `README.md`
- `architecture.drawio`
- `gnss_rx_user_paths.m.example`
- 根目录快捷入口 `ber.m`

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
- `tx_truth.json` 加载通
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

TX_TRUTH_PATH = 'C:\VMwareVirtualMachines\GongXiangDocument\GNSS_RX_matlab\tx_truth.json';
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

TX_TRUTH_PATH = '/home/shenao/projects/GNSS_RX/matlab/tx_truth.json';
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
PYTHONPATH=src python3 scripts/record_rx.py \
    --config configs/rx_baremetal.yaml \
    --duration 30 \
    --capture-mode single
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
LOCAL_STEM=/home/$USER/GNSS_RX_Data_local/2026/2026_03_31/$CAPTURE_NAME/$CAPTURE_NAME

mkdir -p "$(dirname "$LOCAL_STEM")"
printf 'LOCAL_STEM=<%s>\n' "$LOCAL_STEM"

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
LOCAL_STEM=/home/$USER/GNSS_RX_Data_local/2026/2026_03_31/$CAPTURE_NAME/$CAPTURE_NAME
TRANSFER_DIR=/home/$USER/GNSS_RX_Transfer/2026/2026_03_31/$CAPTURE_NAME

mkdir -p "$(dirname "$LOCAL_STEM")"
mkdir -p "$TRANSFER_DIR"
printf 'LOCAL_STEM=<%s>\n' "$LOCAL_STEM"
printf 'TRANSFER_DIR=<%s>\n' "$TRANSFER_DIR"

sudo chrt -f 50 env PYTHONPATH=src python3 scripts/record_rx.py \
    --config configs/rx_baremetal.yaml \
    --duration 250 \
    --capture-mode single \
    --output-stem "$LOCAL_STEM"
```

### 16.5 采后复制

推荐优先用 `cp`：

```bash
cp -v "$(dirname "$LOCAL_STEM")"/*.json "$TRANSFER_DIR"/
cp -v "$(dirname "$LOCAL_STEM")"/*.sc16 "$TRANSFER_DIR"/
ls -lh "$TRANSFER_DIR"
```

### 16.6 文件量级

`250 s @ 4.092 Msps` 的 `.sc16` 大约为：

- 约 `4.09 GB` 十进制
- 约 `3.81 GiB` 二进制

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

### 18.1 找到移动硬盘挂载点

```bash
lsblk
ls /media/$USER/
```

### 18.2 推荐复制方式

```bash
cp -r ~/GNSS_RX_Data /media/$USER/<drive_name>/GNSS_RX_Data_baremetal
sync
```

若目录名含空格，例如 `Seagate Basic`：

```bash
cp -r ~/GNSS_RX_Data "/media/$USER/Seagate Basic/GNSS_RX_Data_baremetal"
sync
```

### 18.3 建议一起转移的文件

- `GNSS_RX_Data_baremetal/`
- 对应轮次的 `tx_truth.json`
- 若需要复盘，还可额外保存 TX / RX 终端日志

---

## 十九、主力机 MATLAB 正式 BER 分析

本节是全手册最关键的“结论出口”。

### 19.1 统一原则

- 正式 BER 用 `ber`
- 正式 BER 模式用 `tracked_truth`
- 默认显式指定 `CAPTURE_PATH`
- 默认显式指定 `TX_TRUTH_PATH`

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

TX_TRUTH_PATH = 'C:\VMwareVirtualMachines\GongXiangDocument\GNSS_RX_matlab\tx_truth.json';
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

TX_TRUTH_PATH = 'C:\VMwareVirtualMachines\GongXiangDocument\GNSS_RX_matlab\tx_truth.json';
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

### 19.4 Linux 主力机正式 BER 示例

若主力机本身就是 Linux，并且 MATLAB 直接在 Linux 上运行：

```matlab
cd('/home/shenao/projects/GNSS_RX/matlab')
clear functions
rehash

TX_TRUTH_PATH = '/home/shenao/projects/GNSS_RX/matlab/tx_truth.json';
CAPTURE_PATH = ['/home/shenao/GNSS_RX_Data_baremetal/2026/2026_03_31/' ...
    '20260331_ber250s_localdisk_rawiq_sc16_zeroif_prn1_spread_sr4092000_' ...
    'cf100000000_dur250p0s/20260331_ber250s_localdisk_rawiq_sc16_zeroif_' ...
    'prn1_spread_sr4092000_cf100000000_dur250p0s'];
BER_MODE = 'tracked_truth';

run('scripts/run_ber_loopback.m')
```

### 19.5 可选加速配置

如果想启用 MATLAB 离线分析加速：

```matlab
ACCEL_OPTIONS = struct( ...
    'backend', 'gpu', ...
    'precision', 'single', ...
    'batch_ms', 2000, ...
    'use_parfor', false, ...
    'device_index', []);
```

若希望自动回退：

```matlab
ACCEL_OPTIONS = struct('backend', 'auto', 'precision', 'single');
```

若希望强制 CPU：

```matlab
ACCEL_OPTIONS = struct('backend', 'cpu', 'precision', 'double');
```

注意：

- 当前 tracking 主循环在 v1 仍保持 CPU
- GPU 更适合 open-loop 相关的批量扫描部分

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
