# GNSS_RX MATLAB 工作区

这个目录提供 `GNSS_RX` 的 MATLAB 离线分析链，负责读取接收端导出的
`.sc16 + .json` 采集文件，完成快速可视化、`PRN1` 捕获和结果归档。

## 功能介绍

当前 MATLAB 工作区包含以下能力：

- 自动加载一组 `GNSS_RX` 采集文件：`.sc16 + .json`
- 自动解析采集根目录，支持用户本地配置、环境变量和默认路径
- 绘制基础图像：时域、频谱、IQ 散点
- 运行带 Doppler 搜索的离线 `PRN1` 捕获
- 运行 `PRN1~32` 多星对比搜索，快速确认是否真的抓到目标星
- 将图片和摘要结果保存到采集日期目录下的 `analysis/<stem>/`

## 目录结构

- `scripts/run_capture_analysis.m`
  MATLAB 入口脚本。运行时会自动把 `functions/` 加入路径。
- `functions/load_gnss_rx_capture.m`
  加载 `.sc16 + .json`，组装复数基带样本和元数据。
- `functions/gnss_rx_resolve_data_dir.m`
  统一解析采集数据根目录。
- `functions/plot_capture_overview.m`
  生成时域图、频谱图和 IQ 散点图。
- `functions/run_prn1_acquisition.m`
  对 PRN1 做 Doppler + code phase 搜索。
- `functions/run_multi_prn_survey.m`
  对 PRN1~32 做批量搜索，生成多星对比结果。
- `functions/save_analysis_artifacts.m`
  保存图片、`.json` 摘要和 `.mat` 结果。
- `gnss_rx_user_paths.m.example`
  用户本地路径配置模板，用于指定实际数据目录。

## Ubuntu 同步到共享目录

如果你在 Ubuntu 虚拟机里修改了 `GNSS_RX/matlab/` 下的代码，想同步到共享目录
`/mnt/hgfs/GongXiangDocument/GNSS_RX_matlab/`，推荐使用 `rsync`。

首次同步前，可先确保目标目录存在：

```bash
mkdir -p /mnt/hgfs/GongXiangDocument/GNSS_RX_matlab
```

同步新增和修改过的文件：

```bash
rsync -av /home/shen/projects/GNSS_RX/matlab/ /mnt/hgfs/GongXiangDocument/GNSS_RX_matlab/
```

如果希望把目标目录中已经删除的旧文件也一起清掉，使用镜像同步：

```bash
rsync -av --delete /home/shen/projects/GNSS_RX/matlab/ /mnt/hgfs/GongXiangDocument/GNSS_RX_matlab/
```

同步前如果只想查看差异，可以先运行：

```bash
diff -rq /home/shen/projects/GNSS_RX/matlab /mnt/hgfs/GongXiangDocument/GNSS_RX_matlab
```

同步完成后，Windows 宿主机就可以从共享目录直接打开最新版本的 MATLAB 脚本。

## 数据目录配置

`run_capture_analysis.m` 不再要求手工修改脚本里的路径，而是通过
`gnss_rx_resolve_data_dir()` 按以下优先级解析：

1. `matlab/gnss_rx_user_paths.m`
2. 环境变量 `GNSS_RX_DATA_DIR`
3. 平台默认路径

推荐做法是复制模板文件并填写你本地实际的数据目录：

```bash
cp /home/shen/projects/GNSS_RX/matlab/gnss_rx_user_paths.m.example \
  /home/shen/projects/GNSS_RX/matlab/gnss_rx_user_paths.m
```

然后在 `gnss_rx_user_paths.m` 中设置：

```matlab
GNSS_RX_DATA_DIR = 'C:\VMwareVirtualMachines\GongXiangDocument\GNSS_RX_Data';
```

Linux 下也可以写成：

```matlab
GNSS_RX_DATA_DIR = '/mnt/hgfs/GongXiangDocument/GNSS_RX_Data';
```

## 快速开始

1. 确认 `GNSS_RX_Data` 目录中已经有接收端导出的 `.sc16 + .json` 文件对。
2. 如有需要，先同步 `matlab/` 到共享目录。
3. 配置 `gnss_rx_user_paths.m` 或设置 `GNSS_RX_DATA_DIR`。
4. 在 MATLAB 中打开 `scripts/run_capture_analysis.m` 并运行：

```matlab
run_capture_analysis
```

不传参时，脚本会自动分析数据目录下最新的一组有效采集。

如果你想分析指定采集，也可以传入 stem 路径或 `.json` 路径。

**路径结构说明**

每次采集的文件存放在以 stem 命名的子目录里：

```
GNSS_RX_Data/2026/<YYYY_MM_DD>/<stem>/<stem>.sc16
                                      <stem>.json
```

因此传入 stem 路径时，需要包含子目录名和文件名（**stem 出现两次**）：

**Windows 宿主机 MATLAB（VMware 共享目录）：**

```matlab
run_capture_analysis('C:\VMwareVirtualMachines\GongXiangDocument\GNSS_RX_Data\2026\2026_03_25\20260325_090729_rawiq_sc16_zeroif_prn1_spread_sr4092000_cf150000000_dur2p0s\20260325_090729_rawiq_sc16_zeroif_prn1_spread_sr4092000_cf150000000_dur2p0s')
```

**Linux VM 中的 MATLAB（或本地 Linux）：**

```matlab
run_capture_analysis('/mnt/hgfs/GongXiangDocument/GNSS_RX_Data/2026/2026_03_25/20260325_090729_rawiq_sc16_zeroif_prn1_spread_sr4092000_cf150000000_dur2p0s/20260325_090729_rawiq_sc16_zeroif_prn1_spread_sr4092000_cf150000000_dur2p0s')
```

也可以直接传入 `.json` 文件路径（效果相同）：

```matlab
run_capture_analysis('C:\...\20260325_090729_..._dur2p0s\20260325_090729_..._dur2p0s.json')
```

> **注意**：传入路径时必须与 MATLAB 实际运行的操作系统路径格式匹配。
> 在 Windows 宿主机 MATLAB 中使用 Linux 路径（`/mnt/hgfs/...`）会导致文件找不到的错误。

## 输出结果

默认情况下，分析产物会写入：

`<capture_date_dir>/analysis/<stem>/`

当前版本会保存以下文件：

- `overview_time.png`
- `overview_spectrum.png`
- `iq_scatter.png`
- `prn1_acquisition.png`
- `multi_prn_survey.png`
- `analysis_summary.json`
- `analysis_summary.mat`

## 多星捕获对比图

`multi_prn_survey.png` 是一张 PRN1~32 的次峰比柱状图：

- X 轴：PRN 编号（1~32）
- Y 轴：次峰比（peak / second_peak），超过红色阈值线表示捕获成功
- 绿色柱：捕获成功
- 蓝色柱：未捕获
- 红色虚线：判决门限，默认 2.5

当接收端真正收到 PRN1 信号时，PRN1 对应的柱子应明显高于阈值线，其余
PRN 通常接近 1.0 附近的噪底水平。

## 说明

- 默认采集根目录仍兼容 VMware 共享目录路径。
- `find_latest_capture.m` 会自动跳过 `analysis/` 目录，只从原始采集目录中找最新文件。
- 捕获搜索支持 PRN1~32，单 PRN 详细结果来自 `run_prn1_acquisition.m`，多星对比来自 `run_multi_prn_survey.m`。
