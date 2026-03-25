# 接收实验流程

## 推荐顺序

1. `Tone bring-up`
   - 在 `gnss_tx` 端发射单音
   - 在 `GNSS_RX` 中录制 2 秒
   - 确认 MATLAB 或快速 FFT 能看到窄峰
2. `Spread capture`
   - 将发射机切回 `spread`
   - 使用相同的零中频配置录制
3. `MATLAB acquisition`
   - 加载 `.sc16 + .json`
   - 搜索 `PRN1`
   - 运行 `matlab/scripts/run_capture_analysis.m`
   - 检查生成的时域图、频谱图、IQ 散点图和 acquisition 图
4. `Archive results`
   - 记录共享目录中的采集日期目录与文件 stem
   - 记录发射端配置引用
   - 记录捕获结果与截图文件名

## 首次成功的判据

接收端的第一个里程碑不是导航解码，而是：

- 采集文件能够正确加载
- PRN1 能产生明显的捕获峰值
- 其他 PRN 不会出现同等级的峰值

## 建议的文件命名

当前实现默认将采集结果存放到 VMware 共享目录：

`/mnt/hgfs/GongXiangDocument/GNSS_RX_Data/<YYYY>/<YYYY_MM_DD>/`

文件 stem 不再建议手工命名，而是由程序自动生成，默认格式为：

`<YYYYMMDD_HHMMSS>_rawiq_sc16_zeroif_prn<id>_<signal_mode>_sr<sample_rate_hz>_cf<center_freq_hz>_dur<duration_s>s`

例如：

- `20260323_190530_rawiq_sc16_zeroif_prn1_spread_sr4092000_cf100000000_dur2p0s`
- `20260323_191200_rawiq_sc16_zeroif_prn1_tone_sr4092000_cf100000000_dur2p0s`

同一次采集生成的 `.sc16` 和 `.json` 会自动共享同一个 stem，因此 MATLAB 端应始终成对读取共享目录中的同名文件。

## MATLAB 分析步骤

推荐在宿主机 MATLAB 中按以下步骤操作：

1. 确认 `GNSS_RX/matlab/gnss_rx_user_paths.m` 已填写实际数据目录，或设置了 `GNSS_RX_DATA_DIR`
2. 打开 `GNSS_RX/matlab/scripts/run_capture_analysis.m`
3. 直接运行 `run_capture_analysis`
   - 若不传参，脚本会自动寻找共享目录下最新的一组 `.sc16 + .json`
   - 若传入 stem 或 `.json` 路径，则会分析指定采集
4. 查看以下输出：
   - `overview_time.png`
   - `overview_spectrum.png`
   - `iq_scatter.png`
   - `prn1_acquisition.png`
   - `multi_prn_survey.png`
   - `analysis_summary.json`
   - `analysis_summary.mat`

默认分析结果会保存到：

`<capture_date_dir>/analysis/<stem>/`
