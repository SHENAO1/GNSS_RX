function result = run_prn_acquisition(samples, meta, cfg)
%RUN_PRN_ACQUISITION 对一段基带 IQ 样本执行 GPS L1 C/A 指定 PRN 信号捕获搜索。
%
%   通用化版本，支持 PRN 1~32 中的任意一颗。目标 PRN 从 meta.prn_id 中读取，
%   若 meta.prn_id 无效或不存在，则默认搜索 PRN 1（向后兼容）。
%
%   算法与 run_prn1_acquisition 完全相同（非相干累加 + FFT 循环相关）。
%
%   输入：
%     samples  —— 复数基带样本列向量（已归一化到 [-1, 1]）
%     meta     —— 元数据结构体，须包含 prn_id 和 sample_rate_hz 字段
%     cfg      —— 可选配置结构体（各字段说明见 ensure_acq_defaults）
%
%   输出：result 结构体，包含捕获结论、峰值位置、多普勒估计和搜索图数据

if nargin < 3
    cfg = struct();
end
cfg = ensure_acq_defaults(cfg);

% 从元数据中读取目标 PRN 编号；无效时默认 PRN 1（向后兼容）。
if isfield(meta, 'prn_id') && isnumeric(meta.prn_id) && meta.prn_id >= 1 && meta.prn_id <= 32
    target_prn = double(meta.prn_id);
else
    target_prn = 1;
end

% 验证输入样本非空。
if isempty(samples)
    error('GNSS_RX:EmptySamples', '输入样本为空，无法进行捕获搜索。');
end

% 采样率决定了每 1 ms（一个 C/A 码周期）内有多少个采样点。
sample_rate_hz   = double(meta.sample_rate_hz);
samples_per_code = round(sample_rate_hz / 1000);

if samples_per_code <= 0 || abs(sample_rate_hz / 1000 - samples_per_code) > 1e-6
    error('GNSS_RX:UnsupportedSampleRate', ...
        '采样率 %.6f Hz 无法整除 1 ms 码周期，请使用 1.023 MHz 整数倍采样率。', ...
        sample_rate_hz);
end

% 去除 DC 偏置。
samples = samples - mean(samples);

% 计算实际可用的 1 ms 片段数。
available_ms       = floor(numel(samples) / samples_per_code);
num_noncoherent_ms = min(cfg.noncoherent_ms, available_ms);
if num_noncoherent_ms < 1
    error('GNSS_RX:InsufficientData', '样本数不足 1 ms，无法进行捕获搜索。');
end

% 截取用于搜索的样本段。
search_samples = samples(1:(num_noncoherent_ms * samples_per_code));

% 生成 Doppler 搜索频率网格。
doppler_bins_hz = cfg.doppler_min_hz : cfg.doppler_step_hz : cfg.doppler_max_hz;

% 生成目标 PRN 的 C/A 码并做 FFT，用于频域循环相关。
local_code     = build_sampled_ca_code(target_prn, samples_per_code, sample_rate_hz);
local_code_fft = fft(local_code);

% 生成时间轴，用于构造去 Doppler 复指数。
t = (0 : samples_per_code - 1)' ./ sample_rate_hz;

% 初始化二维搜索图：行 = Doppler 格，列 = 码相位（采样点）。
search_map = zeros(numel(doppler_bins_hz), samples_per_code);

for doppler_idx = 1:numel(doppler_bins_hz)
    fd = doppler_bins_hz(doppler_idx);
    carrier = exp(-1j * 2 * pi * fd * t);
    accumulated_power = zeros(1, samples_per_code);

    for ms_idx = 1:num_noncoherent_ms
        sample_offset = (ms_idx - 1) * samples_per_code;
        segment = search_samples(sample_offset + 1 : sample_offset + samples_per_code);
        mixed = segment .* carrier;
        correlation = ifft(fft(mixed) .* conj(local_code_fft));
        accumulated_power = accumulated_power + abs(correlation(:)).' .^ 2;
    end

    search_map(doppler_idx, :) = accumulated_power;
end

% 找全局最大值（最佳 Doppler + 码相位）。
[peak_value, peak_linear_idx] = max(search_map(:));
[best_doppler_idx, best_code_idx] = ind2sub(size(search_map), peak_linear_idx);
best_doppler_hz = doppler_bins_hz(best_doppler_idx);

% 次峰比计算（排除主峰附近一个码片宽度）。
masked_map = search_map;
chip_exclusion = max(1, round(samples_per_code / 1023));
excl_idx = mod((best_code_idx - 1 - chip_exclusion) : (best_code_idx - 1 + chip_exclusion), ...
               samples_per_code) + 1;
masked_map(:, excl_idx) = 0;
second_peak = max(masked_map(:));

if isempty(second_peak) || second_peak <= 0
    second_peak_ratio = inf;
else
    second_peak_ratio = peak_value / second_peak;
end

mean_floor  = mean(search_map(:));
peak_metric = peak_value / max(mean_floor, eps);
detected    = second_peak_ratio >= cfg.detection_threshold;

result = struct();
result.detected                = logical(detected);
result.target_prn              = target_prn;
result.peak_value              = peak_value;
result.peak_metric             = peak_metric;
result.second_peak_ratio       = second_peak_ratio;
result.best_doppler_hz         = best_doppler_hz;
result.best_code_phase_samples = best_code_idx - 1;
result.doppler_bins_hz         = doppler_bins_hz;
result.code_phase_samples      = 0 : (samples_per_code - 1);
result.search_map              = search_map;
result.num_noncoherent_ms      = num_noncoherent_ms;
result.samples_per_code        = samples_per_code;
end


function cfg = ensure_acq_defaults(cfg)
if ~isfield(cfg, 'noncoherent_ms') || isempty(cfg.noncoherent_ms)
    cfg.noncoherent_ms = 10;    % 非相干累加毫秒数（10 ms 为当前默认）
end
if ~isfield(cfg, 'doppler_min_hz') || isempty(cfg.doppler_min_hz)
    cfg.doppler_min_hz = -10000;
end
if ~isfield(cfg, 'doppler_max_hz') || isempty(cfg.doppler_max_hz)
    cfg.doppler_max_hz = 10000;
end
if ~isfield(cfg, 'doppler_step_hz') || isempty(cfg.doppler_step_hz)
    cfg.doppler_step_hz = 500;
end
if ~isfield(cfg, 'detection_threshold') || isempty(cfg.detection_threshold)
    cfg.detection_threshold = 2.5;
end
end


function sampled_code = build_sampled_ca_code(prn_id, samples_per_code, sample_rate_hz)
%BUILD_SAMPLED_CA_CODE 将指定 PRN 的 C/A 码重采样到 samples_per_code 个采样点。
chip_rate_hz = 1.023e6;
chip_count   = 1023;
chip_indices = floor((0 : samples_per_code - 1) * chip_rate_hz / sample_rate_hz);
chip_indices = mod(chip_indices, chip_count) + 1;
ca_code      = generate_ca_code(prn_id);
sampled_code = ca_code(chip_indices).';
end


function code = generate_ca_code(prn_id)
%GENERATE_CA_CODE 按 GPS ICD IS-GPS-200 标准生成指定 PRN 的 C/A 码（+1/-1 格式）。
G2_TAPS = [
     2,  6;   %  PRN 1
     3,  7;   %  PRN 2
     4,  8;   %  PRN 3
     5,  9;   %  PRN 4
     1,  9;   %  PRN 5
     2, 10;   %  PRN 6
     1,  8;   %  PRN 7
     2,  9;   %  PRN 8
     3, 10;   %  PRN 9
     2,  3;   %  PRN 10
     3,  4;   %  PRN 11
     5,  6;   %  PRN 12
     6,  7;   %  PRN 13
     7,  8;   %  PRN 14
     8,  9;   %  PRN 15
     9, 10;   %  PRN 16
     1,  4;   %  PRN 17
     2,  5;   %  PRN 18
     3,  6;   %  PRN 19
     4,  7;   %  PRN 20
     5,  8;   %  PRN 21
     6,  9;   %  PRN 22
     1,  3;   %  PRN 23
     4,  6;   %  PRN 24
     5,  7;   %  PRN 25
     6,  8;   %  PRN 26
     7,  9;   %  PRN 27
     8, 10;   %  PRN 28
     1,  6;   %  PRN 29
     2,  7;   %  PRN 30
     3,  8;   %  PRN 31
     4,  9;   %  PRN 32
];
if prn_id < 1 || prn_id > size(G2_TAPS, 1)
    error('GNSS_RX:UnsupportedPrn', 'PRN %d 不在支持范围 1~%d 内。', prn_id, size(G2_TAPS, 1));
end
tap_a = G2_TAPS(prn_id, 1);
tap_b = G2_TAPS(prn_id, 2);
g1   = true(1, 10);
g2   = true(1, 10);
code = zeros(1, 1023);
for idx = 1:1023
    g1_out    = g1(10);
    g2_out    = xor(g2(tap_a), g2(tap_b));
    code(idx) = xor(g1_out, g2_out);
    g1_fb = xor(g1(3), g1(10));
    g2_fb = xor(xor(xor(xor(xor(g2(2), g2(3)), g2(6)), g2(8)), g2(9)), g2(10));
    g1 = [g1_fb, g1(1:9)];
    g2 = [g2_fb, g2(1:9)];
end
code = 1 - 2 * double(code);
end
