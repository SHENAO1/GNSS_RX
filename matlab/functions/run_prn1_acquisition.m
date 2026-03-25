function result = run_prn1_acquisition(samples, meta, cfg)
%RUN_PRN1_ACQUISITION 执行一个简化版的 PRN1 离线捕获搜索。

if nargin < 3
    cfg = struct();
end
cfg = ensure_acq_defaults(cfg);

if ~isfield(meta, 'prn_id') || meta.prn_id ~= 1
    error('GNSS_RX:UnsupportedPrn', 'This MATLAB workflow currently supports PRN1 only.');
end

sample_rate_hz = double(meta.sample_rate_hz);
% 采样率必须能整齐落到 1 ms 码周期上，这样首版实现才能直接做循环相关搜索。
samples_per_code = round(sample_rate_hz / 1000);
if samples_per_code <= 0 || abs(sample_rate_hz / 1000 - samples_per_code) > 1e-6
    error('GNSS_RX:UnsupportedSampleRate', ...
        'Sample rate %.6f does not map cleanly to 1 ms code periods.', sample_rate_hz);
end

% 去除 DC 偏置（消除 USRP 本振泄漏对相关的影响）
samples = samples - mean(samples);

available_ms = floor(numel(samples) / samples_per_code);
num_noncoherent_ms = min(cfg.noncoherent_ms, available_ms);
if num_noncoherent_ms < 1
    error('GNSS_RX:InsufficientData', 'At least 1 ms of samples is required for acquisition.');
end

% 首版使用“多毫秒非相干累加 + Doppler 分档 + FFT 循环相关”的结构。
search_samples = samples(1:(num_noncoherent_ms * samples_per_code));
doppler_bins_hz = cfg.doppler_min_hz:cfg.doppler_step_hz:cfg.doppler_max_hz;
local_code = build_sampled_prn1_code(samples_per_code, sample_rate_hz);
local_code_fft = fft(local_code);
t = (0:samples_per_code - 1)' ./ sample_rate_hz;

search_map = zeros(numel(doppler_bins_hz), samples_per_code);
for doppler_idx = 1:numel(doppler_bins_hz)
    fd = doppler_bins_hz(doppler_idx);
    carrier = exp(-1j * 2 * pi * fd * t);
    accumulated_power = zeros(1, samples_per_code);

    for ms_idx = 1:num_noncoherent_ms
        sample_offset = (ms_idx - 1) * samples_per_code;
        segment = search_samples(sample_offset + 1:sample_offset + samples_per_code);
        % 先去 Doppler，再与本地 C/A 码做循环相关，最后做非相干功率累加。
        mixed = segment .* carrier;
        correlation = ifft(fft(mixed) .* conj(local_code_fft));
        accumulated_power = accumulated_power + abs(correlation(:)).' .^ 2;
    end

    search_map(doppler_idx, :) = accumulated_power;
end

[peak_value, peak_linear_idx] = max(search_map(:));
[best_doppler_idx, best_code_idx] = ind2sub(size(search_map), peak_linear_idx);
best_doppler_hz = doppler_bins_hz(best_doppler_idx);

masked_map = search_map;
% 在主峰附近挖掉一个小窗口，再找次峰，用于构造首版的峰值判决指标。
% 用循环取模确保 code_phase=0 或末尾时排除窗口能正确绕回。
chip_exclusion = max(1, round(samples_per_code / 1023));
excl_idx = mod((best_code_idx - 1 - chip_exclusion):(best_code_idx - 1 + chip_exclusion), samples_per_code) + 1;
masked_map(:, excl_idx) = 0;
second_peak = max(masked_map(:));

if isempty(second_peak) || second_peak <= 0
    second_peak_ratio = inf;
else
    second_peak_ratio = peak_value / second_peak;
end

mean_floor = mean(search_map(:));
peak_metric = peak_value / max(mean_floor, eps);
detected = second_peak_ratio >= cfg.detection_threshold;

result = struct();
result.detected = logical(detected);
result.peak_value = peak_value;
result.peak_metric = peak_metric;
result.second_peak_ratio = second_peak_ratio;
result.best_doppler_hz = best_doppler_hz;
result.best_code_phase_samples = best_code_idx - 1;
result.doppler_bins_hz = doppler_bins_hz;
result.code_phase_samples = 0:(samples_per_code - 1);
result.search_map = search_map;
result.num_noncoherent_ms = num_noncoherent_ms;
result.samples_per_code = samples_per_code;
end

function cfg = ensure_acq_defaults(cfg)
% 这些默认值优先保证“能先看到峰”，后续再按实验结果细调。
if ~isfield(cfg, 'noncoherent_ms') || isempty(cfg.noncoherent_ms)
    cfg.noncoherent_ms = 10;
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

function sampled_code = build_sampled_prn1_code(samples_per_code, sample_rate_hz)
% 按当前采样率把 1023 芯片的 PRN1 C/A 码重采样到 1 ms 采样点上。
chip_rate_hz = 1.023e6;
chip_count = 1023;
chip_indices = floor((0:samples_per_code - 1) * chip_rate_hz / sample_rate_hz);
chip_indices = mod(chip_indices, chip_count) + 1;
ca_code = generate_prn1_ca_code();
sampled_code = ca_code(chip_indices).';
end

function code = generate_prn1_ca_code()
% GPS L1 C/A PRN1: G2 使用 taps 2 和 6。
g1 = true(1, 10);
g2 = true(1, 10);
code = zeros(1, 1023);

for idx = 1:1023
    g1_out = g1(10);
    g2_out = xor(g2(2), g2(6));
    code(idx) = xor(g1_out, g2_out);

    g1_feedback = xor(g1(3), g1(10));
    g2_feedback = xor(xor(xor(xor(xor(g2(2), g2(3)), g2(6)), g2(8)), g2(9)), g2(10));

    g1 = [g1_feedback, g1(1:9)];
    g2 = [g2_feedback, g2(1:9)];
end

code = 1 - 2 * double(code);
end
