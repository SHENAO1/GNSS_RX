import sys

new_content = """# GNSS_RX 文档目录

欢迎来到 **GNSS_RX (GNSS Receiver)** 的核心文档空间。本目录存放系统的设计说明、架构解析和实验操作流程文档。这里以文档形式记录项目的各个层次，虽然不直接执行代码，但每篇文档都对应一组可复现的入口命令，帮助你从理论理解平滑过渡到动手实践。

---

## 📚 文档索引

为了帮助你快速找到所需信息，请参考以下分类索引。建议依据任务需求选择阅读。

- **[receiver_overview.md](receiver_overview.md)**
  > **核心概念与实现说明**  
  > 接收机实现说明，适合在看代码前深刻理解 Python 包结构、GNU Radio 流图和 MATLAB 离线分析链之间的映射关系。
- **[experiment_workflow.md](experiment_workflow.md)**
  > **操作指南与实验清单**  
  > 详细的实验操作顺序说明，适合真正开始跑一遍硬件采集和数据分析时作为实验清单（Checklist）使用。
- **[tx_rx_end_to_end_signal_chain.drawio](tx_rx_end_to_end_signal_chain.drawio)**
  > **宏观端到端流程**  
  > 跨发端与收端的端到端信号链图。覆盖输入数字流、扩频、UHD 发射与接收、`SC16`/`JSON` 落盘、以及后续的 MATLAB 捕获与误码率 (BER) 分析。
- **[system_architecture.drawio](system_architecture.drawio)**
  > **收端系统架构概览**  
  > 系统总体架构图，直观可视化了“配置 -> 采集 -> 落盘 -> MATLAB -> BER 分析”的整体闭环关系。
- **模块级架构图**
  > **深入代码级别的理解**  
  > - Python 核心模块图：位于 `../src/gnss_rx/*.drawio`。适合按 `runtime`, `flowgraph`, `writer`, `metadata`, `utils` 逐个剖析实现逻辑。
  > - MATLAB 分析图：位于 `../matlab/architecture.drawio` 与 `../matlab/ber_loopback.drawio`。这是 MATLAB 主分析链与 BER 诊断链的专业图纸。

---

## 📡 端到端信号流详解（含数据类型）

> **参考视图：** `tx_rx_end_to_end_signal_chain.drawio`  
> 信号在这个闭环系统中经历了从生成到发射、再到捕捉的完整变换。

### 一、 发端生成 (TX 阶段)

**1. 发端初始输入**
- **核心输入参数**：`PRN ID / PRN 子集`、预定义的导航电文（`nav bits`）、以及射频参数如采样率、中心频率和增益。
- **配置与来源**：主要通过 `configs/tx_*.yaml` 结合 `scripts/run_tx.py` 的参数覆盖机制动态生成。

**2. 扩频与基带生成 (算法链)**
- **PRN 码生成**：遵循 GPS L1 C/A 标准，1 毫秒为一周期，包含 1023 个码片 (chips)。
- **导航比特映射**：原始比特被归一化到 $[-1, +1]$ 空间。
- **基带 BPSK 调制**：
  - 扩频操作：$s[k] = d[k] \times c[k]$，其中 $d[k]$ 是导航数据，$c[k]$ 是伪随机扩频码，$s[k]$ 直接映射为 BPSK 基带复数符号。
  - 信号解析：复基带可表达为 $x[k] = A \cdot s[k] \cdot e^{j\phi}$。理想零中频下通常认定 $\phi \approx 0$，即信号能量集中在 I 轴（$I = \pm A, Q \approx 0$）。工程上保留成对IQ复数，以应对之后的混频、滤波和USRP驱动接口。

**3. 发射缓冲与 GNU Radio/UHD 互联**
- **基带回放缓冲池**：构造大段可循环（replay）基带复数IQ样本缓冲。
- **GNU Radio 发射流图**：`vector_source_c -> usrp_sink`。
  - **`vector_source_c`**：向量数据源模块，`c` 表示 Complex 流。流式输出预生成的复数 IQ（默认格式 `complex64/fc32`）。
  - **`usrp_sink`**：接收基带并下发至 SDR。结合缓冲区的循环设置（repeat），保障连续无缝辐射。
- **UHD 核心配置项**：`set_samp_rate`, `set_center_freq`, `set_gain`, `set_bandwidth`, `set_antenna`。

### 二、 硬件链路与空口传输 (RF 阶段)

**4. 硬件发射与射频传播**
- 本系统中 USRP 担任发射节点，将数字 IQ 通过射频前端转为模拟高频 RF 信号送出。
- **链路模式**：
  - **线缆回环**：通过衰减器直接相连，环境干净。
  - **OTA (Over-The-Air)**：空口传输，真实暴漏在多径、遮挡、外部干扰、收发机频偏等物理限制下，极大考验系统鲁棒性。

### 三、 接收采集与数据落盘 (RX 阶段)

**5. 接收采集信号处理流水线**
> 流水线架构：`usrp_source -> head -> Sc16CaptureSink`

这条轻量级 GNU Radio 流图是可靠采集并持久化射频数据的核心数据传输泵。

- **① `usrp_source` — 硬件源点**
  - **职责**：驱动接收机（如 B210）做 ADC 采样与数字下变频（DDC），源源不断产出 `fc32`（Float Complex 32-bit）格式复数基带。
  - **控制**：读取 `RxRuntimeConfig` 获取中心频率、增益和天线口。
  - **样本形态**：每个样本包含 I（实部）+ Q（虚部），各 4 字节单精度浮点，整体共 8 字节/样本。

- **② `head` — 高可靠采样网关**
  - **职责**：硬性阻断无休止的采集动作，保护存储资源。
  - **阈值**：截取样本数 $N = \text{sample\_rate\_hz} \times \text{duration\_s}$（例如：4 MHz 下记录 2 秒即 8,000,000 个样本块），满载即停机。

- **③ `Sc16CaptureSink` — 智能落盘引擎 (自研)**
  - **流程**：将 Float 数据高效转换为磁盘友好的 Short 整型。
    1. 分解源输入，硬性限幅 $I, Q \in [-1.0, 1.0]$ 以防破音卷绕。
    2. 数学放缩：乘以 $32767$（即全幅态推入 int16 极值范围）。
    3. 内存交织：对齐为 `[I₀, Q₀, I₁, Q₁, I₂, Q₂, ...]`。
    4. 小端序 (LE) 字节码落盘。
  - **输出形态**：生成紧凑的文件格式 `SC16`（Signed Complex 16-bit）。单个样本为 2 字节+2 字节，总共 4 字节/样本，落盘尺寸减半，大幅节约磁盘 I/O。

- **④ 元数据落盘 (Sidecar JSON)**
  - 除了 `.sc16` 裸数据，采集框架还会自动落盘配套的 `.json` 描述文件。
  - 核心包含：`sample_rate_hz`, `center_freq_hz`, `prn_id/prn_ids`, `all_prns`, 以及数据分块尺寸（chunk）等重放信息。

### 四、 本地计算与数据恢复 (MATLAB 阶段)

**6. 离线基带处理与误码率 (BER) 测试**
- **数据加载**：利用 `load_gnss_rx_capture` 函数透明读取 `.sc16 + .json` 复合体。
- **粗精捕获**：调用 `run_prn_acquisition` 单星捕获 和 `run_multi_prn_survey` 多星扫描 寻找可视卫星并测算多普勒与码相位。
- **BER 解算**：借由 `run_ber_loopback` 闭环测试框架，加载本地真值 `tx_truth.json` 的参考导航电文。完成最终的载波追踪、帧同步解调并按比特计算验证 BER 参数。

---

## 📊 数据类型与格式参考矩阵

系统流转跨越 Python 算法层、GNU Radio 中间件、UHD 驱动层以及 MATLAB 统计层，不同环节采用了适应场景的最优数据格式。

| 业务阶段 | 承载数据内容 / 文件名 | 类型与格式定义 | 备注与用途 |
| :--- | :--- | :--- | :--- |
| **信源** | 纯净 PRN CA 码 | `int8` 取值 $\{-1, +1\}$ | 扩频计算的最简整数形式 |
| **信源** | 纯净导航数据比特 | `int8` 取值 $\{-1, +1\}$ | 用于扩频调制前的编码 |
| **TX 引擎** | 发送基带信号内存池 | `complex64` (`fc32` 标准) | 即 Float Complex，32位实部/虚部，计算动态强 |
| **UHD/RF** | 主机到 USRP 的线缆级传输 | `sc16` (Short Complex 16-bit) | 物理传输首选，有效缩减线缆 USB/Ethernet 的 带宽压力 |
| **RX 引擎** | 二进制落盘捕获文件 `.sc16` | `iq_int16_interleaved_le` | I/Q 交织打平，小端 `int16` |
| **RX 引擎** | 元数据描述文件 `.json` | 标准 JSON 文件文本存放 | 通用字典格式，MATLAB 可内置解析读取 |
| **测试** | 循环验证真值 `tx_truth.json` | 标准 JSON 文件文本存放 | 记录生成端的绝对相位和PRN等参数快照 |
| **可视化** | MATLAB 测试分析报告 | `png` 图表 + `.mat/.json` 数据 | 用于论文、测试报告和迭代复查的回看依据 |

> **深入理解**: 
> - **`fc32`** 常用于主机 CPU 层面的内部（Python/GNU Radio）标量与向量计算。原因在于浮点数具备无需担心溢出的动态范围并且被数学算法友好包容。
> - **`sc16`** 则是数据出海（写缓存、写盘、传外部硬件）的首选。在基带限定好量限的前提下，直接砍掉约50%的庞大体积负载。

---

## 🚀 核心命令与复现指南

在此无需编写代码，只要用配置驱动就能快速复现实验。由于脚本众多，可以先作预跑自检验证，再做真实捕获。

**1. 预执行自检 (Dry-Run)**
> 验证 Python 环境、配置文件结构与硬件驱动包是否正常衔接，没有任何实际信号发射与设备占用。
```bash
cd /home/shen/projects/GNSS_RX
PYTHONPATH=src python3 scripts/record_rx.py --dry-run
```

**2. 真实硬件信号采集**
> 利用实际 USRP 插口，依据指定的捕获特征配置清单执行真实的射频波形采集。
```bash
cd /home/shen/projects/GNSS_RX
PYTHONPATH=src python3 scripts/record_rx.py --config configs/rx_prn1_capture.yaml
```

**3. 合成数据发生器模拟 (无硬件离线开发模式)**
> 即使目前手上没有射频 SDR 设备，依靠内部模拟器也可以强行打通到后续的 MATLAB 分析。
```bash
cd /home/shen/projects/GNSS_RX
PYTHONPATH=/home/shen/projects/gnss_tx/src:src \
  python3 scripts/gen_synthetic_capture.py \
  --snr-db 10 \
  --duration 2
```

**4. 启动 MATLAB 信号解算工作流**
> 前端捕获完成后，切入你的 MATLAB 工作空间或启动 MATLAB 引擎，执行以下指令载入数据分析流程。
```matlab
% 在 MATLAB 统领命令栏执行
run_capture_analysis
```

---

## 📖 最佳阅读与学习路径

如果你是本工程的新鲜血液，建议按如下次序进行熟悉：

1. **第一站：总览大局**。请务必优先通读 **`receiver_overview.md`**。先搞清楚我们的软件接收机由哪些模块组成、它采用了什么样的数据流设计思路。
2. **第二站：跟着动起手来**。阅读 **`experiment_workflow.md`**，照猫画虎跑一次，熟悉采集链路、落盘格式和 MATLAB 的输出表现，通过实践增强概念。
3. **第三站：分而治之，各个击破**。当大体框架已经熟练于心后，如果在开发中遇到问题或者需要做二次创新，就可以返回到各个子模块路径（例如 `src/` 或 `matlab/` 下的 README 进行微观级的研究）。
"""

with open('/home/shen/projects/GNSS_RX/docs/README.md', 'w') as f:
    f.write(new_content)
