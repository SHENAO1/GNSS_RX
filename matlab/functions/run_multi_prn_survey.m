function survey = run_multi_prn_survey(samples, meta, cfg)
%RUN_MULTI_PRN_SURVEY 对同一段 IQ 数据同时搜索 PRN1~32，返回每颗星的捕获指标。
%
%   survey = run_multi_prn_survey(samples, meta)
%   survey = run_multi_prn_survey(samples, meta, cfg)
%
%   输入：
%     samples  - 复数基带样本列向量（已归一化到 [-1,1]）
%     meta     - 采集元数据结构体（来自 load_gnss_rx_capture）
%     cfg      - 可选配置，支持以下字段：
%                  prn_list         - 要搜索的 PRN 编号列表（默认 1:32）
%                  noncoherent_ms   - 非相干累加毫秒数（默认 10）
%                  doppler_min_hz   - Doppler 搜索下限（默认 -10000）
%                  doppler_max_hz   - Doppler 搜索上限（默认 10000）
%                  doppler_step_hz  - Doppler 搜索步长（默认 500）
%                  detection_threshold - 次峰比判决门限（默认 2.5）
%
%   输出：survey 结构体，包含：
%     prn_list          - 搜索的 PRN 编号列表
%     peak_metric       - 每个 PRN 的峰值与均值比
%     second_peak_ratio - 每个 PRN 的峰值与次峰比（>threshold 则判为捕获）
%     detected          - 每个 PRN 的捕获判决结果（logical）
%     best_doppler_hz   - 每个 PRN 对应的最优 Doppler 频移

if nargin < 3
    cfg = struct();
end
cfg = ensure_survey_defaults(cfg);

sample_rate_hz = double(meta.sample_rate_hz);
samples_per_code = round(sample_rate_hz / 1000);
if samples_per_code <= 0 || abs(sample_rate_hz / 1000 - samples_per_code) > 1e-6
    error('GNSS_RX:UnsupportedSampleRate', ...
        'Sample rate %.6f does not map cleanly to 1 ms code periods.', sample_rate_hz);
end

available_ms = floor(numel(samples) / samples_per_code);
num_noncoherent_ms = min(cfg.noncoherent_ms, available_ms);
if num_noncoherent_ms < 1
    error('GNSS_RX:InsufficientData', 'At least 1 ms of samples is required.');
end

% 去除 DC 偏置（消除 USRP 本振泄漏对相关的影响）
samples = samples - mean(samples);

search_samples = samples(1:(num_noncoherent_ms * samples_per_code));
doppler_bins_hz = cfg.doppler_min_hz:cfg.doppler_step_hz:cfg.doppler_max_hz;
t = (0:samples_per_code - 1)' ./ sample_rate_hz;

prn_list = cfg.prn_list;
n_prn = numel(prn_list);

peak_metric       = zeros(1, n_prn);
second_peak_ratio = zeros(1, n_prn);
detected          = false(1, n_prn);
best_doppler_hz   = zeros(1, n_prn);

fprintf('多星搜索：共 %d 个 PRN，每星 %d ms 非相干累加，%d 个 Doppler 分格\n', ...
    n_prn, num_noncoherent_ms, numel(doppler_bins_hz));

% 预计算 Doppler 载波（所有 PRN 共用同一组载波相位向量）
carriers = zeros(samples_per_code, numel(doppler_bins_hz));
for di = 1:numel(doppler_bins_hz)
    carriers(:, di) = exp(-1j * 2 * pi * doppler_bins_hz(di) * t);
end

for pi_idx = 1:n_prn
    prn_id = prn_list(pi_idx);
    local_code = build_sampled_ca_code(prn_id, samples_per_code, sample_rate_hz);
    local_code_fft = fft(local_code);

    search_map = zeros(numel(doppler_bins_hz), samples_per_code);
    for di = 1:numel(doppler_bins_hz)
        accumulated_power = zeros(1, samples_per_code);
        for ms_idx = 1:num_noncoherent_ms
            offset = (ms_idx - 1) * samples_per_code;
            seg = search_samples(offset + 1:offset + samples_per_code);
            mixed = seg .* carriers(:, di);
            corr = ifft(fft(mixed) .* conj(local_code_fft));
            accumulated_power = accumulated_power + abs(corr(:)).' .^ 2;
        end
        search_map(di, :) = accumulated_power;
    end

    [peak_val, peak_idx] = max(search_map(:));
    [best_di, best_ci]   = ind2sub(size(search_map), peak_idx);
    best_doppler_hz(pi_idx) = doppler_bins_hz(best_di);

    % 次峰：挖掉主峰附近一个 chip 宽度的窗口（循环取模处理边界绕回）
    chip_excl = max(1, round(samples_per_code / 1023));
    excl_idx = mod((best_ci - 1 - chip_excl):(best_ci - 1 + chip_excl), samples_per_code) + 1;
    masked = search_map;
    masked(:, excl_idx) = 0;
    second_peak = max(masked(:));

    mean_floor = mean(search_map(:));
    peak_metric(pi_idx) = peak_val / max(mean_floor, eps);

    if isempty(second_peak) || second_peak <= 0
        second_peak_ratio(pi_idx) = inf;
    else
        second_peak_ratio(pi_idx) = peak_val / second_peak;
    end
    detected(pi_idx) = second_peak_ratio(pi_idx) >= cfg.detection_threshold;
end

survey = struct();
survey.prn_list          = prn_list(:)';
survey.peak_metric       = peak_metric;
survey.second_peak_ratio = second_peak_ratio;
survey.detected          = detected;
survey.best_doppler_hz   = best_doppler_hz;
survey.detection_threshold = cfg.detection_threshold;
survey.num_noncoherent_ms  = num_noncoherent_ms;
end


%% -------------------------------------------------------------------------
function cfg = ensure_survey_defaults(cfg)
if ~isfield(cfg, 'prn_list') || isempty(cfg.prn_list)
    cfg.prn_list = 1:32;
end
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


%% -------------------------------------------------------------------------
function sampled_code = build_sampled_ca_code(prn_id, samples_per_code, sample_rate_hz)
%BUILD_SAMPLED_CA_CODE 按采样率把 PRN C/A 码重采样到 1 ms 样本点上。
chip_rate_hz = 1.023e6;
chip_count   = 1023;
chip_indices = floor((0:samples_per_code - 1) * chip_rate_hz / sample_rate_hz);
chip_indices = mod(chip_indices, chip_count) + 1;
ca_code = generate_ca_code(prn_id);
sampled_code = ca_code(chip_indices).';
end


%% -------------------------------------------------------------------------
function code = generate_ca_code(prn_id)
%GENERATE_CA_CODE 生成 GPS L1 C/A PRN 码，PRN1~32，输出 +/-1 格式。
%
% G2 抽头表来自 GPS ICD IS-GPS-200（1-indexed）。

G2_TAPS = [
     2,  6;   %  1
     3,  7;   %  2
     4,  8;   %  3
     5,  9;   %  4
     1,  9;   %  5
     2, 10;   %  6
     1,  8;   %  7
     2,  9;   %  8
     3, 10;   %  9
     2,  3;   % 10
     3,  4;   % 11
     5,  6;   % 12
     6,  7;   % 13
     7,  8;   % 14
     8,  9;   % 15
     9, 10;   % 16
     1,  4;   % 17
     2,  5;   % 18
     3,  6;   % 19
     4,  7;   % 20
     5,  8;   % 21
     6,  9;   % 22
     1,  3;   % 23
     4,  6;   % 24
     5,  7;   % 25
     6,  8;   % 26
     7,  9;   % 27
     8, 10;   % 28
     1,  6;   % 29
     2,  7;   % 30
     3,  8;   % 31
     4,  9;   % 32
];

if prn_id < 1 || prn_id > size(G2_TAPS, 1)
    error('GNSS_RX:UnsupportedPrn', 'PRN %d is not in the supported range 1~%d.', ...
        prn_id, size(G2_TAPS, 1));
end

tap_a = G2_TAPS(prn_id, 1);
tap_b = G2_TAPS(prn_id, 2);

g1 = true(1, 10);
g2 = true(1, 10);
code = zeros(1, 1023);

for idx = 1:1023
    g1_out = g1(10);
    g2_out = xor(g2(tap_a), g2(tap_b));
    code(idx) = xor(g1_out, g2_out);

    g1_fb = xor(g1(3), g1(10));
    g2_fb = xor(xor(xor(xor(xor(g2(2), g2(3)), g2(6)), g2(8)), g2(9)), g2(10));

    g1 = [g1_fb, g1(1:9)];
    g2 = [g2_fb, g2(1:9)];
end

code = 1 - 2 * double(code);
end
