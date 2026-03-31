# 2026-03-31 Step 4 GPU Tracking Code Update Results

## 背景

针对 `track_nav_bits.m` 做了 `Step 4 GPU 化与 CPU 回退` 改造后，在 Windows MATLAB 分析机上重新同步代码，并对同一组 `250 s` 样本做了两次复测：

- 正确率优先配置：`backend=gpu, precision=single, batch_ms=2000`
- Step 4 hybrid 配置：`backend=gpu, precision=single, batch_ms=100, dll_gpu_enabled=true`

本次固定使用的采集输入为：

```text
F:\GNSS_RX_Data_local\2026\2026_03_31\20260331_ber250s_localdisk_rawiq_sc16_zeroif_prn1_spread_sr4092000_cf100000000_dur250p0s\20260331_ber250s_localdisk_rawiq_sc16_zeroif_prn1_spread_sr4092000_cf100000000_dur250p0s
```

## 结果 1：正确率优先配置

命令：

```matlab
CAPTURE_PATH = ['F:\GNSS_RX_Data_local\2026\2026_03_31\' ...
    '20260331_ber250s_localdisk_rawiq_sc16_zeroif_prn1_spread_sr4092000_' ...
    'cf100000000_dur250p0s\20260331_ber250s_localdisk_rawiq_sc16_zeroif_' ...
    'prn1_spread_sr4092000_cf100000000_dur250p0s'];
BER_MODE = 'tracked_truth';

clc
clear functions
rehash

ACCEL_OPTIONS = struct( ...
    'backend', 'gpu', ...
    'precision', 'single', ...
    'batch_ms', 2000);

run('scripts/run_ber_loopback.m')
```

关键结果：

- `Step 4 计划后端 = cpu`
- `Step 4 实际后端 = cpu`
- `Step 4 用时 = 21.08 s`
- `BER = 1.20e-03`
- `误码个数 = 15 / 12499`
- `truth 匹配率 = 100.0%`
- `请求后端 = gpu`
- `解析后端 = gpu`
- `加速后端 = cpu`

结论：

- 这是当前代码状态下“正确率最高且可复现”的正式配置
- Step 2 / Step 3 可继续受益于 GPU
- Step 4 仍主要走 CPU，但整体结果稳定

## 结果 2：Step 4 Hybrid 配置

命令：

```matlab
CAPTURE_PATH = ['F:\GNSS_RX_Data_local\2026\2026_03_31\' ...
    '20260331_ber250s_localdisk_rawiq_sc16_zeroif_prn1_spread_sr4092000_' ...
    'cf100000000_dur250p0s\20260331_ber250s_localdisk_rawiq_sc16_zeroif_' ...
    'prn1_spread_sr4092000_cf100000000_dur250p0s'];
BER_MODE = 'tracked_truth';

clc
clear functions
rehash

ACCEL_OPTIONS = struct( ...
    'backend', 'gpu', ...
    'precision', 'single', ...
    'batch_ms', 100, ...
    'dll_gpu_enabled', true);

run('scripts/run_ber_loopback.m')
```

关键结果：

- `Step 4 计划后端 = gpu_hybrid`
- `Step 4 实际后端 = gpu_hybrid`
- `Step 4 用时 = 14.39 s`
- `BER = 4.68e-01`
- `误码个数 = 5853 / 12499`
- `truth 匹配率 = 90.9%`
- `请求后端 = gpu`
- `解析后端 = gpu`
- `加速后端 = gpu_hybrid`

结论：

- 这说明 Step 4 的 hybrid GPU 路径已经真正被命中
- 性能上确实优于 CPU 基准与旧版 `dll_gpu_enabled=true` 路径
- 但正确性显著恶化，当前不能用于正式 BER 结论

## 总结

当前结论应明确分成两条：

- 正式 BER 结论路径：
  - 使用 `backend=gpu, precision=single, batch_ms=2000`
  - 不启用 `dll_gpu_enabled=true`
- Step 4 GPU tracking 实验路径：
  - `dll_gpu_enabled=true, batch_ms=100`
  - 可用于继续调试性能，但当前数值稳定性不足

因此，在本轮代码状态下，推荐把“正确率优先配置”作为默认正式命令，把 `gpu_hybrid` 视为后续算法修正实验，而不是正式配置替代品。
