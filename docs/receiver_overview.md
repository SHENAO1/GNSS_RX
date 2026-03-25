# GNSS_RX 接收机概览

## 目标

`GNSS_RX` 负责录制原始零中频采集数据，并将其交给 MATLAB，对同级
`gnss_tx` 项目发射的 PRN1 信号执行离线捕获。

v1 链路如下：

`USRP source -> zero-IF complex samples -> SC16 writer -> JSON sidecar`

## 为什么选择原始 SC16 + JSON

- `SC16` 符合常见 SDR 样本表示方式，同时能控制文件体积。
- JSON 伴随文件可以免去在 MATLAB 中手动重复录入 `sample_rate`、
  `center_freq` 等相关参数。
- 这个约定被刻意保持得很小，后续工具可以在不破坏第一版 MATLAB
  工作流的前提下，逐步扩展到 `SigMF`、`fc32` 或更丰富的实验元数据。

## 当前已实现能力

当前代码已经实现了一个可运行的接收端采集链，重点在“把空口原始观测稳定录下来并交给 MATLAB”，而不是完整导航解算。已经具备的能力包括：

- 单通道 USRP/UHD 零中频采集
- 通过 GNU Radio flowgraph 将复数基带样本限制到固定采集时长
- 将采集结果写成原始交织 `SC16` IQ 文件
- 为同一次采集生成配套 JSON sidecar
- 默认导出到 VMware 共享目录，便于宿主机 MATLAB 直接读取
- 自动生成带时间戳和关键采集参数标签的文件 stem
- 在 CLI 中提供 dry-run、设备发现输出和 MATLAB 交接摘要

从当前实现来看，它更像是一个“GNSS 原始采集与交接工具”，而不是完整意义上的 GNSS 接收机。

## 当前未实现能力

当前代码明确没有覆盖以下能力：

- 不实现完整 GNSS 接收机链路
- 不做导航电文解码
- 不做实时 acquisition、tracking 或解算
- 不提供多 PRN、多星或多通道接收
- 当前元数据和运行时校验只支持 `PRN1`
- 不包含 MATLAB 算法本体，MATLAB 端只是假定会读取 `.sc16 + .json`

不过当前仓库现在已经预留并实现了一套独立的 `matlab/` 工作区，用于宿主机侧的离线加载、基础绘图和 `PRN1` acquisition；它仍然不属于实时接收机链的一部分。

## 当前文件约定

- `/mnt/hgfs/GongXiangDocument/GNSS_RX_Data/<YYYY>/<YYYY-MM-DD>/<stem>.sc16`
  - 小端序交织 `int16`
  - 样本顺序：`I0,Q0,I1,Q1,...`
- `<stem>.json`
  - `sample_format`
  - `complex_layout`
  - `sample_rate_hz`
  - `center_freq_hz`
  - `duration_s`
  - `samples_captured`
  - `rx_gain_db`
  - `bandwidth_hz`
  - `antenna`
  - `usrp_addr`
  - `zero_if`
  - `signal_mode`
  - `prn_id`
  - `tx_profile_reference`

默认 stem 结构为：

`<YYYYMMDD_HHMMSS>_rawiq_sc16_zeroif_prn<id>_<signal_mode>_sr<sample_rate_hz>_cf<center_freq_hz>_dur<duration_s>s`

## 模块职责分析

当前实现主要由以下几个模块组成，它们的边界比较清晰：

- `scripts/record_rx.py`
  - CLI 入口
  - 读取 YAML 配置并叠加命令行覆盖
  - 打印 dry-run 计划、UHD 设备发现输出和 MATLAB 交接摘要
  - 在正式采集前检查 UHD 设备是否可用
  - 启动 flowgraph、关闭 sink，并在结束后写出 JSON 元数据
- `src/gnss_rx/runtime.py`
  - 定义 `RxRuntimeConfig`
  - 对采样率、时长、带宽、PRN、输出路径策略等参数做校验
  - 负责默认共享目录路径、日期分层目录和自动 stem 生成
  - 负责将运行时配置格式化成采集报告和 MATLAB 交接摘要
- `src/gnss_rx/flowgraph.py`
  - 负责创建 UHD `usrp_source`
  - 设置中心频率、采样率、增益、带宽、天线、时钟源和时间源
  - 组装 `USRP source -> head -> Sc16CaptureSink`
  - `head` 用于按照 `capture_samples` 自动截断采样长度
- `src/gnss_rx/writer.py`
  - 将 `complex64` 复数样本裁剪到 `[-1, 1]`
  - 转换为交织的 little-endian `int16`
  - 通过 `Sc16CaptureSink` 持续写出原始 `.sc16`
- `src/gnss_rx/metadata.py`
  - 构建 MATLAB 交接所需的最小元数据集合
  - 把 JSON 与 `.sc16` 保持同 stem 输出
  - `data_file` 只写文件名，不把绝对路径塞进协议字段
- `matlab/`
  - 宿主机 MATLAB 离线分析工作区
  - 包含入口脚本、文件加载函数、基础绘图函数、`PRN1` acquisition 函数和结果保存函数
  - 只消费 `.sc16 + .json`，不改动 Python 采集链

## 运行数据流

当前代码的执行链路可以概括为：

1. CLI 读取 `configs/rx_prn1_capture.yaml`
2. 命令行参数按需覆盖 YAML 中的中心频率、采样率、增益、时长和输出根目录
3. `runtime.py` 校验参数，并根据当前时间生成共享目录下的目标路径
4. `record_rx.py` 打印采集配置和 MATLAB 交接摘要
5. `flowgraph.py` 创建 UHD source，输出 `fc32` 复数样本
6. `head` 根据 `sample_rate_hz * duration_s` 控制总采样点数
7. `writer.py` 把 `fc32` 样本转换成 `sc16` 并落盘
8. 采集完成后，`metadata.py` 写出同 stem 的 `.json`

从数据类型角度看，当前实现是“UHD/GNU Radio 内部用 `fc32`，导出文件使用 `sc16`”。

## 当前默认协议

当前默认协议和路径策略已经在代码中固化：

- 默认共享目录根路径：`/mnt/hgfs/GongXiangDocument/GNSS_RX_Data`
- 导出目录层级：`<YYYY>/<YYYY-MM-DD>/`
- 默认 stem 组成：
  - 时间戳
  - `rawiq`
  - `sc16`
  - `zeroif`
  - `prn<id>`
  - `signal_mode`
  - `sr<sample_rate_hz>`
  - `cf<center_freq_hz>`
  - `dur<duration_s>s`
- JSON 关键字段：
  - `sample_format`
  - `complex_layout`
  - `sample_rate_hz`
  - `center_freq_hz`
  - `duration_s`
  - `samples_captured`
  - `rx_gain_db`
  - `bandwidth_hz`
  - `antenna`
  - `usrp_addr`
  - `zero_if`
  - `signal_mode`
  - `prn_id`
  - `tx_profile_reference`
  - `data_file`

这说明当前仓库已经隐含定义了一套“接收端到 MATLAB 的文件交接协议”。

## MATLAB 交接说明

MATLAB 应当：

1. 读取 JSON 伴随文件
2. 按交织 `int16` 方式加载 `.sc16` 文件
3. 转换为复数基带
4. 在启用频率搜索的情况下运行 PRN1 捕获

频率搜索仍然很重要，因为 v1 不假定发射端与接收端共享参考时钟。

当前仓库中的 `matlab/scripts/run_capture_analysis.m` 已经把这条链串起来：它可以自动寻找最新采集文件或接收指定 stem，完成加载、基础绘图、离线 `PRN1` acquisition，并把分析结果保存到采集日期目录下的 `analysis/<stem>/`。

## 当前验证状态

现有测试已经覆盖了当前实现中的几个关键边界：

- `runtime` 测试验证了：
  - `capture_samples` 的计算
  - YAML 加载后带宽的默认推导
  - 共享目录日期分层路径生成
  - 时间戳 stem 的格式
  - `output_stem` 手动覆盖兼容行为
- `record_rx` 测试验证了：
  - dry-run 会打印采集配置
  - dry-run 会打印最终输出路径
  - dry-run 会打印 MATLAB 交接摘要
- `writer` 测试验证了：
  - 复数样本到 `SC16` 的顺序与裁剪逻辑
  - little-endian 交织写盘格式
- `metadata` 测试验证了：
  - JSON sidecar 中关键字段完整存在
- `flowgraph` 测试验证了：
  - 在 GNU Radio 可用时，top block 能从向量源采集并写出样本

这些测试说明当前实现重点验证的是“采集协议和导出正确性”，而不是信号处理算法本身。

## 后续扩展点

如果后面继续演进，这个仓库当前的结构比较适合沿着以下方向扩展：

- 增加 MATLAB 侧加载脚本或 Python 对等校验工具
- 扩展 `PRN1` 之外的 PRN 支持
- 增加 `SigMF` 或更丰富的实验元数据
- 在不破坏主录制路径的前提下增加预览、实时频谱或在线 acquisition 分支
- 引入更强的结果归档与实验记录机制
