function survey = run_multi_prn_survey(samples, meta, cfg)
%RUN_MULTI_PRN_SURVEY 对同一段 IQ 数据同时搜索 PRN1~32，返回每颗星的捕获指标。
%
%   本函数与 run_prn1_acquisition 使用相同的捕获算法（非相干累加 + FFT 循环相关），
%   但同时处理多个 PRN，可用于快速确认当前信号是哪颗卫星发出的（或有哪些卫星可见）。
%
%   算法优化：所有 PRN 共用同一组 Doppler 载波向量，避免重复计算。
%
%   输入：
%     samples  —— 复数基带样本列向量（已归一化到 [-1, 1]）
%     meta     —— 元数据结构体（来自 load_gnss_rx_capture，须含 sample_rate_hz）
%     cfg      —— 可选配置，支持以下字段：
%                   prn_list            要搜索的 PRN 编号列表（默认 1:32）
%                   noncoherent_ms      非相干累加毫秒数（默认 20）
%                   doppler_min_hz      Doppler 搜索下限 Hz（默认 -10000）
%                   doppler_max_hz      Doppler 搜索上限 Hz（默认 10000）
%                   doppler_step_hz     Doppler 搜索步长 Hz（默认 500）
%                   detection_threshold 次峰比判决门限（默认 2.5）
%
%   输出：survey 结构体，包含：
%     prn_list          —— 搜索的 PRN 编号列表
%     peak_metric       —— 每个 PRN 的峰值与均值比（信噪比参考）
%     second_peak_ratio —— 每个 PRN 的主峰与次峰比（捕获判决指标）
%     detected          —— 每个 PRN 是否捕获成功（逻辑数组）
%     best_doppler_hz   —— 每个 PRN 对应的最优 Doppler 频移估计

if nargin < 3
    cfg = struct();
end
cfg = ensure_survey_defaults(cfg);
accel = gnss_rx_resolve_accel_options(cfg.accel_options);

% 采样率与 1 ms 码周期验证（与 run_prn1_acquisition 逻辑相同）。
sample_rate_hz   = double(meta.sample_rate_hz);
samples_per_code = round(sample_rate_hz / 1000);
if samples_per_code <= 0 || abs(sample_rate_hz / 1000 - samples_per_code) > 1e-6
    error('GNSS_RX:UnsupportedSampleRate', ...
        '采样率 %.6f Hz 无法整除 1 ms 码周期。', sample_rate_hz);
end

% 计算可用毫秒数并截断到配置值。
available_ms       = floor(numel(samples) / samples_per_code);
num_noncoherent_ms = min(cfg.noncoherent_ms, available_ms);
if num_noncoherent_ms < 1
    error('GNSS_RX:InsufficientData', '样本数不足 1 ms，无法进行捕获搜索。');
end

% 去除 DC 偏置（消除 USRP 本振泄漏对相关运算的影响）。
samples = samples - mean(samples);

% 截取用于搜索的样本段。
search_samples  = samples(1 : num_noncoherent_ms * samples_per_code);
doppler_bins_hz = cfg.doppler_min_hz : cfg.doppler_step_hz : cfg.doppler_max_hz;
t               = (0 : samples_per_code - 1)' ./ sample_rate_hz;

prn_list = cfg.prn_list;
n_prn    = numel(prn_list);

% 预分配输出数组（避免在循环中动态扩容，提升性能）。
peak_metric       = zeros(1, n_prn);
second_peak_ratio = zeros(1, n_prn);
detected          = false(1, n_prn);
best_doppler_hz   = zeros(1, n_prn);

fprintf('多星搜索：共 %d 个 PRN，每星 %d ms 非相干累加，%d 个 Doppler 分格\n', ...
    n_prn, num_noncoherent_ms, numel(doppler_bins_hz));

if accel.gpu_enabled
    survey = run_multi_prn_survey_via_acquisition(samples, meta, cfg, prn_list);
    return;
end

% 预计算所有 Doppler 载波向量（所有 PRN 共用，避免重复运算）。
% carriers 矩阵：第 di 列是 Doppler = doppler_bins_hz(di) 时的去载波复指数向量。
carriers = zeros(samples_per_code, numel(doppler_bins_hz));
for di = 1:numel(doppler_bins_hz)
    carriers(:, di) = exp(-1j * 2 * pi * doppler_bins_hz(di) * t);
end

if accel.parfor_enabled
    parfor prn_idx = 1:n_prn
        local_result = run_single_prn_search(prn_list(prn_idx), search_samples, carriers, ...
            doppler_bins_hz, sample_rate_hz, samples_per_code, cfg);
        peak_metric(prn_idx) = local_result.peak_metric;
        second_peak_ratio(prn_idx) = local_result.second_peak_ratio;
        detected(prn_idx) = local_result.detected;
        best_doppler_hz(prn_idx) = local_result.best_doppler_hz;
    end
else
    for prn_idx = 1:n_prn
        local_result = run_single_prn_search(prn_list(prn_idx), search_samples, carriers, ...
            doppler_bins_hz, sample_rate_hz, samples_per_code, cfg);
        peak_metric(prn_idx) = local_result.peak_metric;
        second_peak_ratio(prn_idx) = local_result.second_peak_ratio;
        detected(prn_idx) = local_result.detected;
        best_doppler_hz(prn_idx) = local_result.best_doppler_hz;
    end
end

% 打包结果到输出结构体。
survey = struct();
survey.prn_list            = prn_list(:)';
survey.peak_metric         = peak_metric;
survey.second_peak_ratio   = second_peak_ratio;
survey.detected            = detected;
survey.best_doppler_hz     = best_doppler_hz;
survey.detection_threshold = cfg.detection_threshold;
survey.num_noncoherent_ms  = num_noncoherent_ms;
survey.accel_backend       = accel.resolved_backend;
end


%% -------------------------------------------------------------------------
function cfg = ensure_survey_defaults(cfg)
%ENSURE_SURVEY_DEFAULTS 为多星搜索配置结构体填充缺省值。
if ~isfield(cfg, 'prn_list') || isempty(cfg.prn_list)
    cfg.prn_list = 1:32;            % 默认搜索全部 32 颗 GPS 卫星
end
if ~isfield(cfg, 'noncoherent_ms') || isempty(cfg.noncoherent_ms)
    cfg.noncoherent_ms = 10;        % 非相干累加毫秒数（10 ms 为当前默认）
end
if ~isfield(cfg, 'doppler_min_hz') || isempty(cfg.doppler_min_hz)
    cfg.doppler_min_hz = -10000;    % Doppler 搜索下限（Hz）
end
if ~isfield(cfg, 'doppler_max_hz') || isempty(cfg.doppler_max_hz)
    cfg.doppler_max_hz = 10000;     % Doppler 搜索上限（Hz）
end
if ~isfield(cfg, 'doppler_step_hz') || isempty(cfg.doppler_step_hz)
    cfg.doppler_step_hz = 500;      % Doppler 搜索步长（Hz）
end
if ~isfield(cfg, 'detection_threshold') || isempty(cfg.detection_threshold)
    cfg.detection_threshold = 2.5;  % 次峰比判决门限
end
if ~isfield(cfg, 'accel_options') || isempty(cfg.accel_options)
    cfg.accel_options = struct();
end
end


function local_result = run_single_prn_search(prn_id, search_samples, carriers, doppler_bins_hz, sample_rate_hz, samples_per_code, cfg)
    num_noncoherent_ms = floor(numel(search_samples) / samples_per_code);
    local_code     = build_sampled_ca_code(prn_id, samples_per_code, sample_rate_hz);
    local_code_fft = fft(local_code);
    search_map = zeros(numel(doppler_bins_hz), samples_per_code);

    for di = 1:numel(doppler_bins_hz)
        accumulated_power = zeros(1, samples_per_code);
        for ms_idx = 1:num_noncoherent_ms
            offset = (ms_idx - 1) * samples_per_code;
            seg    = search_samples(offset + 1 : offset + samples_per_code);
            mixed = seg .* carriers(:, di);
            corr  = ifft(fft(mixed) .* conj(local_code_fft));
            accumulated_power = accumulated_power + abs(corr(:)).' .^ 2;
        end
        search_map(di, :) = accumulated_power;
    end

    [peak_val, peak_idx] = max(search_map(:));
    [best_di, best_ci] = ind2sub(size(search_map), peak_idx);
    chip_excl = max(1, round(samples_per_code / 1023));
    excl_idx  = mod((best_ci - 1 - chip_excl) : (best_ci - 1 + chip_excl), samples_per_code) + 1;
    masked    = search_map;
    masked(:, excl_idx) = 0;
    second_peak = max(masked(:));
    mean_floor = mean(search_map(:));

    local_result = struct();
    local_result.peak_metric = peak_val / max(mean_floor, eps);
    if isempty(second_peak) || second_peak <= 0
        local_result.second_peak_ratio = inf;
    else
        local_result.second_peak_ratio = peak_val / second_peak;
    end
    local_result.detected = local_result.second_peak_ratio >= cfg.detection_threshold;
    local_result.best_doppler_hz = doppler_bins_hz(best_di);
end


function survey = run_multi_prn_survey_via_acquisition(samples, meta, cfg, prn_list)
    n_prn = numel(prn_list);
    peak_metric = zeros(1, n_prn);
    second_peak_ratio = zeros(1, n_prn);
    detected = false(1, n_prn);
    best_doppler_hz = zeros(1, n_prn);

    base_cfg = struct( ...
        'noncoherent_ms', cfg.noncoherent_ms, ...
        'doppler_min_hz', cfg.doppler_min_hz, ...
        'doppler_max_hz', cfg.doppler_max_hz, ...
        'doppler_step_hz', cfg.doppler_step_hz, ...
        'detection_threshold', cfg.detection_threshold, ...
        'accel_options', cfg.accel_options);

    for prn_idx = 1:n_prn
        local_meta = meta;
        local_meta.prn_id = prn_list(prn_idx);
        acq_result = run_prn_acquisition(samples, local_meta, base_cfg);
        peak_metric(prn_idx) = acq_result.peak_metric;
        second_peak_ratio(prn_idx) = acq_result.second_peak_ratio;
        detected(prn_idx) = acq_result.detected;
        best_doppler_hz(prn_idx) = acq_result.best_doppler_hz;
    end

    survey = struct();
    survey.prn_list = prn_list(:)';
    survey.peak_metric = peak_metric;
    survey.second_peak_ratio = second_peak_ratio;
    survey.detected = detected;
    survey.best_doppler_hz = best_doppler_hz;
    survey.detection_threshold = cfg.detection_threshold;
    survey.num_noncoherent_ms = min(cfg.noncoherent_ms, floor(numel(samples) / round(double(meta.sample_rate_hz) / 1000)));
    survey.accel_backend = 'gpu';
end


%% -------------------------------------------------------------------------
function sampled_code = build_sampled_ca_code(prn_id, samples_per_code, sample_rate_hz)
%BUILD_SAMPLED_CA_CODE 将指定 PRN 的 C/A 码重采样到 samples_per_code 个采样点。
chip_rate_hz = 1.023e6;
chip_count   = 1023;
chip_indices = floor((0 : samples_per_code - 1) * chip_rate_hz / sample_rate_hz);
chip_indices = mod(chip_indices, chip_count) + 1;
ca_code      = generate_ca_code(prn_id);
sampled_code = ca_code(chip_indices).';
end


%% -------------------------------------------------------------------------
function code = generate_ca_code(prn_id)
%GENERATE_CA_CODE 按 GPS ICD IS-GPS-200 标准生成指定 PRN 的 C/A 码（+1/-1 格式）。
%
%   GPS C/A 码由 G1 和 G2 两个 LFSR 的输出异或生成。G2 的输出由两个特定抽头异或决定，
%   不同的抽头组合对应不同的 PRN 编号（即不同卫星的识别码）。
%   下表为 PRN1~32 对应的 G2 抽头（1-indexed，来自 IS-GPS-200 表格）。

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

% 检查 PRN 编号是否在支持范围内。
if prn_id < 1 || prn_id > size(G2_TAPS, 1)
    error('GNSS_RX:UnsupportedPrn', 'PRN %d 不在支持范围 1~%d 内。', ...
        prn_id, size(G2_TAPS, 1));
end

% 取出该 PRN 对应的 G2 抽头位置。
tap_a = G2_TAPS(prn_id, 1);
tap_b = G2_TAPS(prn_id, 2);

% 两个 10 级 LFSR 初始全为 1（GPS 标准规定的初始条件）。
g1   = true(1, 10);
g2   = true(1, 10);
code = zeros(1, 1023);

for idx = 1:1023
    g1_out    = g1(10);
    g2_out    = xor(g2(tap_a), g2(tap_b));
    code(idx) = xor(g1_out, g2_out);

    % G1 反馈：第 3 位和第 10 位异或
    g1_fb = xor(g1(3), g1(10));
    % G2 反馈：第 2、3、6、8、9、10 位异或
    g2_fb = xor(xor(xor(xor(xor(g2(2), g2(3)), g2(6)), g2(8)), g2(9)), g2(10));

    % 寄存器移位（新反馈位移入最高位）
    g1 = [g1_fb, g1(1:9)];
    g2 = [g2_fb, g2(1:9)];
end

% 0 → +1，1 → -1（双极性格式）
code = 1 - 2 * double(code);
end
