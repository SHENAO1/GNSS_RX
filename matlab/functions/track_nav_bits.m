function tracked_result = track_nav_bits(samples, meta, acq_result, truth, options, accel_options)
% TRACK_NAV_BITS 基于 acquisition 的窄范围 tracking 导航比特恢复主链。
%
% 目标：
%   1. 逐 1 ms 做 prompt/early/late 相关，持续跟踪码相位漂移
%   2. 在 prompt 相关序列上做 FLL-assisted PLL 载波跟踪
%   3. 用 truth 仅做初始 bit 对齐/极性选择和最终 BER 评估
%
% 输出 tracked_result 为结构体，包含比特、BER、tracking history、lock 指标等。
%
% 如果说 recover_nav_bits 更像“离线暴力搜索”，那这个函数更像一个简化接收机：
%   - DLL 思路：靠 early/prompt/late 维持码相位
%   - FLL/PLL 思路：靠 prompt 相位序列维持载波锁定
%   - bit 对齐：在 tracking 稳定后，再决定 20 ms bit 边界落在哪里

    % 补全可选参数，并把 tracking 配置整理成固定字段集合。
    if nargin < 5
        options = struct();
    end
    if nargin < 6
        accel_options = struct();
    end
    options = ensure_track_defaults(options);

    fs = meta.sample_rate_hz;
    samples_per_ms = round(fs * 1e-3);
    samples_per_chip = round(fs / 1.023e6);

    if ~isfield(truth, 'nav_bits_pattern_pm1') || isempty(truth.nav_bits_pattern_pm1)
        error('GNSS_RX:MissingTruthForTracking', ...
            'track_nav_bits 需要 truth.nav_bits_pattern_pm1 作为 BER 参考真值。');
    end

    samples = samples(:);
    samples_mean = mean(samples);

    % 构造 1 ms 本地 PRN 码，后面 DLL 会重复拿它和输入片段做相关。
    prn_chips = generate_ca_code(meta.prn_id);
    prn_samples = repelem(prn_chips, samples_per_chip);
    prn_one_ms = prn_samples(1:samples_per_ms)';

    num_ms = floor((length(samples) - acq_result.best_code_phase_samples) / samples_per_ms) - 1;
    if num_ms < options.min_required_ms
        error('GNSS_RX:InsufficientTrackingData', ...
            '可用于 tracking 的 1 ms 块数不足，至少需要 %d ms。', options.min_required_ms);
    end

    % 第一阶段：先做码跟踪。输出的 prompt/early/late 是后面所有判断的基础。
    [prompt_ms, early_ms, late_ms, code_phase_samples, code_track_events, lock_metric_ms, tracking_backend_info] = track_code_phase_ms( ...
        samples, samples_mean, prn_one_ms, acq_result.best_code_phase_samples + 1, ...
        samples_per_ms, acq_result.best_doppler_hz, fs, options, accel_options);

    % 第二阶段：对 prompt 序列做载波频率/相位跟踪。
    [prompt_fll, prompt_pll, carrier_history] = track_carrier_from_prompt(prompt_ms, options);

    % 第三阶段：借助 truth 在训练段上找出最佳 bit 边界、pattern 偏移和极性。
    [initial_alignment, bit_offset_metrics] = estimate_initial_bit_alignment( ...
        prompt_pll, truth.nav_bits_pattern_pm1, options, accel_options);

    % 第四阶段：在更长时间范围内观察 bit 边界是否漂移，提前发现”看似锁住但 bit 已错位”的情况。
    [window_metrics, bit_timing_events] = check_bit_timing_stability( ...
        prompt_pll, initial_alignment.bit_offset_ms, options, accel_options);

    % 第五阶段：按估计出的 bit 边界把 20 ms prompt 积分成 1 个 bit。
    [bit_corr, bit_times_s] = integrate_bits_from_prompt( ...
        prompt_pll, code_phase_samples, initial_alignment.bit_offset_ms, samples_per_ms, fs, accel_options);

    % BPSK 的 180 度翻转会让实部正负互换，因此先估一个公共相位轴再判决比特符号。
    phi_axis = angle(sum(bit_corr.^2)) / 2;
    bit_corr_rot = bit_corr .* exp(-1j * phi_axis);
    rx_bits = sign(real(bit_corr_rot));
    rx_bits(rx_bits == 0) = 1;

    ref_bits = build_reference_bits_local( ...
        truth.nav_bits_pattern_pm1, length(rx_bits), ...
        initial_alignment.pattern_offset, initial_alignment.polarity);

    ber = mean(sign(rx_bits) ~= sign(ref_bits));
    % 构建比特级锁定质量掩码，综合两类信号：
    %   1. window_match_rate：比特边界能量比（直接反映比特时序是否正确）
    %   2. FLL 频率突变：overflow 触发点检测（用于快速感知失锁起始）
    lock_quality_per_bit = build_bit_lock_quality( ...
        lock_metric_ms, carrier_history.fll_freq_hz, ...
        window_metrics, initial_alignment.bit_offset_ms, ...
        length(rx_bits), options);
    window_ber = compute_window_ber(rx_bits, ref_bits, bit_times_s, options.window_ber_bits, lock_quality_per_bit);

    lock_metrics = struct();
    lock_metrics.prompt_mag = abs(prompt_ms);
    lock_metrics.prompt_mag_pll = abs(prompt_pll);
    lock_metrics.early_mag = abs(early_ms);
    lock_metrics.late_mag = abs(late_ms);
    lock_metrics.code_lock_metric = lock_metric_ms;
    lock_metrics.code_phase_samples = code_phase_samples;
    lock_metrics.code_error = carrier_history.code_error_proxy;
    lock_metrics.fll_freq_hz = carrier_history.fll_freq_hz;
    lock_metrics.pll_phase_deg = carrier_history.pll_phase_deg;
    lock_metrics.phase_error_deg = carrier_history.phase_error_deg;
    lock_metrics.window_match_rate = window_metrics.window_match_rate;
    lock_metrics.window_bit_energy = window_metrics.window_bit_energy;
    lock_metrics.bit_offset_energy = bit_offset_metrics.offset_energy;
    lock_metrics.bit_lock_quality = lock_quality_per_bit;

    tracked_result = struct();
    tracked_result.mode = 'tracked_truth';
    tracked_result.truth_mode = truth.truth_mode;
    tracked_result.rx_bits = rx_bits;
    tracked_result.ref_bits = ref_bits;
    tracked_result.bit_times_s = bit_times_s;
    tracked_result.ber = ber;
    tracked_result.bit_offset_ms = initial_alignment.bit_offset_ms;
    tracked_result.pattern_offset = initial_alignment.pattern_offset;
    tracked_result.polarity = initial_alignment.polarity;
    tracked_result.df_pre_hz = initial_alignment.df_pre_hz;
    tracked_result.df_fine_hz = carrier_history.final_freq_hz;
    tracked_result.phi_est_deg = rad2deg(phi_axis);
    tracked_result.match_rate = initial_alignment.match_rate;
    tracked_result.ambiguity_flag = initial_alignment.ambiguity_flag;
    tracked_result.ambiguity_margin = initial_alignment.ambiguity_margin;
    tracked_result.open_loop_like_score = initial_alignment.score;
    tracked_result.phase_cluster_metrics = struct( ...
        'pre_fll_cluster_strength', bpsk_cluster_strength(prompt_ms), ...
        'post_fll_cluster_strength', bpsk_cluster_strength(prompt_fll), ...
        'post_pll_cluster_strength', bpsk_cluster_strength(prompt_pll), ...
        'bit_corr_cluster_strength', bpsk_cluster_strength(bit_corr));
    tracked_result.tracking_history = struct( ...
        'prompt_ms', prompt_ms, ...
        'prompt_fll', prompt_fll, ...
        'prompt_pll', prompt_pll, ...
        'early_ms', early_ms, ...
        'late_ms', late_ms, ...
        'code_phase_samples', code_phase_samples, ...
        'fll_freq_hz', carrier_history.fll_freq_hz, ...
        'pll_phase_deg', carrier_history.pll_phase_deg, ...
        'phase_error_deg', carrier_history.phase_error_deg);
    tracked_result.lock_metrics = lock_metrics;
    tracked_result.reacq_events = [code_track_events(:); bit_timing_events(:)];
    tracked_result.window_ber = window_ber;
    tracked_result.search_grid_summary = initial_alignment.search_grid_summary;
    tracked_result.diagnostics = struct( ...
        'bit_corr', bit_corr, ...
        'bit_corr_phase_deg', rad2deg(angle(bit_corr)), ...
        'bit_corr_rot', bit_corr_rot, ...
        'bit_corr_rot_phase_deg', rad2deg(angle(bit_corr_rot)), ...
        'initial_alignment', initial_alignment, ...
        'window_metrics', window_metrics);
    if isstruct(accel_options) && isfield(accel_options, 'requested_backend')
        tracked_result.accel_requested_backend = accel_options.requested_backend;
    else
        tracked_result.accel_requested_backend = 'cpu';
    end
    if isstruct(accel_options) && isfield(accel_options, 'resolved_backend')
        tracked_result.accel_resolved_backend = accel_options.resolved_backend;
    else
        tracked_result.accel_resolved_backend = 'cpu';
    end
    if exist('tracking_backend_info', 'var') && isstruct(tracking_backend_info) ...
            && isfield(tracking_backend_info, 'accel_backend') ...
            && ~isempty(tracking_backend_info.accel_backend)
        tracked_result.accel_backend = tracking_backend_info.accel_backend;
    else
        tracked_result.accel_backend = 'cpu';
    end
    fallback_notes = {};
    if isstruct(accel_options) && isfield(accel_options, 'fallback_reason') ...
            && ~isempty(accel_options.fallback_reason)
        fallback_notes{end+1, 1} = char(string(accel_options.fallback_reason)); %#ok<AGROW>
    end
    if exist('tracking_backend_info', 'var') && isstruct(tracking_backend_info) ...
            && isfield(tracking_backend_info, 'fallback_reason') ...
            && ~isempty(tracking_backend_info.fallback_reason)
        fallback_notes{end+1, 1} = char(string(tracking_backend_info.fallback_reason)); %#ok<AGROW>
    end
    if isempty(fallback_notes)
        tracked_result.fallback_reason = '';
    else
        tracked_result.fallback_reason = strjoin(fallback_notes(:).', ' | ');
    end
end

function options = ensure_track_defaults(options)
    % 这些默认值偏向“先稳定跑通”，每个阈值都对应 tracking 链的某个观测窗口或判决门限。
    defaults = struct( ...
        'min_required_ms', 200, ...
        'early_late_spacing_samples', 1, ...
        'code_switch_ratio', 1.015, ...
        'code_search_interval_ms', 100, ...
        'code_search_half_span_samples', 8, ...
        'code_lock_threshold', 0.08, ...
        'fll_smooth_ms', 50, ...
        'pll_gain', 0.08, ...
        'alignment_training_ms', 2000, ...
        'bit_timing_check_interval_ms', 1000, ...
        'bit_timing_check_span_ms', 2000, ...
        'bit_timing_realign_margin', 1.05, ...
        'window_ber_bits', 100, ...
        'fll_jump_threshold_hz', 10.0, ...
        'bit_match_rate_threshold', 0.9);

    option_names = fieldnames(defaults);
    for k = 1:numel(option_names)
        name = option_names{k};
        if ~isfield(options, name) || isempty(options.(name))
            options.(name) = defaults.(name);
        end
    end
end

function [prompt_ms, early_ms, late_ms, code_phase_samples, events, lock_metric_ms, backend_info] = track_code_phase_ms( ...
    samples, samples_mean, prn_one_ms, start_sample, samples_per_ms, doppler_hz, fs, options, accel_options)

    % 这里的核心思想和传统 DLL 类似：
    %   prompt 最大表示当前码相位大致对齐；
    %   early / late 谁更强，提示我们下一毫秒应该把采样窗口往前还是往后挪一点。
    %
    % GPU 批处理路径（accel_options.dll_gpu_enabled = true）：
    %   每批 batch_ms 个 ms 的段矩阵一次性传到 GPU 做矩阵乘法，
    %   然后 gather 回 CPU 串行更新 DLL cursor。
    %   近似：批次内使用批首 cursor 估算所有段起始位置（未修正的 DLL 增量），
    %   最大批内漂移 ≤ batch_ms 个采样点，锁定状态下每 ms 修正量接近 0。
    if nargin < 9
        accel_options = struct();
    end
    backend_info = struct('accel_backend', 'cpu', 'fallback_reason', '');

    dll_gpu = isstruct(accel_options) ...
        && isfield(accel_options, 'dll_gpu_enabled') ...
        && accel_options.dll_gpu_enabled ...
        && isfield(accel_options, 'gpu_enabled') ...
        && accel_options.gpu_enabled;

    if dll_gpu
        try
            [prompt_ms, early_ms, late_ms, code_phase_samples, events, lock_metric_ms] = ...
                track_code_phase_ms_gpu_hybrid( ...
                    samples, samples_mean, prn_one_ms, start_sample, samples_per_ms, ...
                    doppler_hz, fs, options, accel_options);
            backend_info.accel_backend = 'gpu_hybrid';
            return;
        catch ME
            backend_info.accel_backend = 'cpu';
            backend_info.fallback_reason = sprintf( ...
                'Step 4 GPU tracking 路径失败，已自动回退到 CPU：%s', ...
                ME.message);
        end
    end

    [prompt_ms, early_ms, late_ms, code_phase_samples, events, lock_metric_ms] = ...
        track_code_phase_ms_cpu( ...
            samples, samples_mean, prn_one_ms, start_sample, samples_per_ms, ...
            doppler_hz, fs, options);
end

function [prompt_ms, early_ms, late_ms, code_phase_samples, events, lock_metric_ms] = track_code_phase_ms_cpu( ...
    samples, samples_mean, prn_one_ms, start_sample, samples_per_ms, doppler_hz, fs, options)

    num_ms = floor((length(samples) - start_sample + 1) / samples_per_ms);
    prompt_ms = complex(zeros(num_ms, 1));
    early_ms = complex(zeros(num_ms, 1));
    late_ms = complex(zeros(num_ms, 1));
    code_phase_samples = zeros(num_ms, 1);
    lock_metric_ms = zeros(num_ms, 1);
    events = struct('ms_index', {}, 'type', {}, 'detail', {}, 'old_value', {}, 'new_value', {});

    spacing = options.early_late_spacing_samples;
    early_code = circshift(prn_one_ms, -spacing);
    late_code = circshift(prn_one_ms, spacing);
    carrier_one_ms = exp(-1j * 2 * pi * doppler_hz * (0:samples_per_ms-1)' / fs);

    cursor = double(start_sample);
    step = double(samples_per_ms);

    for ms_idx = 1:num_ms
        sample_start = round(cursor);
        if sample_start < 1 || (sample_start + samples_per_ms - 1) > length(samples)
            prompt_ms = prompt_ms(1:ms_idx-1);
            early_ms = early_ms(1:ms_idx-1);
            late_ms = late_ms(1:ms_idx-1);
            code_phase_samples = code_phase_samples(1:ms_idx-1);
            lock_metric_ms = lock_metric_ms(1:ms_idx-1);
            break;
        end

        segment = extract_compensated_segment( ...
            samples, samples_mean, sample_start, samples_per_ms, ...
            carrier_one_ms, doppler_hz, fs);
        prompt_ms(ms_idx) = sum(segment .* prn_one_ms);
        early_ms(ms_idx) = sum(segment .* early_code);
        late_ms(ms_idx) = sum(segment .* late_code);
        code_phase_samples(ms_idx) = sample_start - 1;

        next_adjust = choose_code_adjustment(prompt_ms(ms_idx), early_ms(ms_idx), late_ms(ms_idx), options);
        cursor = cursor + step + next_adjust;

        lock_metric = abs(prompt_ms(ms_idx)) / max(abs(early_ms(ms_idx)) + abs(late_ms(ms_idx)), eps);
        lock_metric_ms(ms_idx) = lock_metric;
        should_search = mod(ms_idx, options.code_search_interval_ms) == 0 || lock_metric < options.code_lock_threshold;
        if should_search
            search_offsets = -options.code_search_half_span_samples : options.code_search_half_span_samples;
            [best_offset, best_metric] = search_local_code_offset( ...
                samples, samples_mean, prn_one_ms, sample_start + round(step), ...
                samples_per_ms, search_offsets, carrier_one_ms, doppler_hz, fs);
            if best_offset ~= 0
                old_cursor = cursor;
                cursor = cursor + best_offset;
                events(end+1) = struct( ... %#ok<AGROW>
                    'ms_index', ms_idx, ...
                    'type', 'code_reacq', ...
                    'detail', sprintf('local_search_metric=%.1f', best_metric), ...
                    'old_value', old_cursor, ...
                    'new_value', cursor);
            end
        end
    end
end

function [prompt_ms, early_ms, late_ms, code_phase_samples, events, lock_metric_ms] = track_code_phase_ms_gpu_hybrid( ...
    samples, samples_mean, prn_one_ms, start_sample, samples_per_ms, doppler_hz, fs, options, accel_options)

    num_ms = floor((length(samples) - start_sample + 1) / samples_per_ms);
    prompt_ms = complex(zeros(num_ms, 1));
    early_ms = complex(zeros(num_ms, 1));
    late_ms = complex(zeros(num_ms, 1));
    code_phase_samples = zeros(num_ms, 1);
    lock_metric_ms = zeros(num_ms, 1);
    events = struct('ms_index', {}, 'type', {}, 'detail', {}, 'old_value', {}, 'new_value', {});

    spacing = options.early_late_spacing_samples;
    early_code = circshift(prn_one_ms, -spacing);
    late_code = circshift(prn_one_ms, spacing);
    prn_block = [prn_one_ms, early_code, late_code];
    carrier_one_ms = exp(-1j * 2 * pi * doppler_hz * (0:samples_per_ms-1)' / fs);

    prec = accel_options.precision_class;
    B = accel_options.batch_ms;
    sample_offsets = (0:samples_per_ms-1)';
    samples_mean_prec = cast(samples_mean, prec);

    samples_gpu = gpuArray(cast(samples, prec));
    samples_mean_gpu = gpuArray(samples_mean_prec);
    prn_gpu = gpuArray(cast(prn_block, prec));
    prn_prompt_gpu = gpuArray(cast(prn_one_ms, prec));
    carrier_gpu = gpuArray(cast(carrier_one_ms, prec));

    cursor = double(start_sample);
    step = double(samples_per_ms);
    batch_start = 1;
    while batch_start <= num_ms
        B_actual = min(B, num_ms - batch_start + 1);
        sample_starts = round(cursor) + (0:B_actual-1) * round(step);

        valid_mask = sample_starts >= 1 & (sample_starts + samples_per_ms - 1) <= length(samples);
        if ~any(valid_mask)
            break;
        end
        first_invalid = find(~valid_mask, 1, 'first');
        if ~isempty(first_invalid)
            B_actual = first_invalid - 1;
            if B_actual == 0
                break;
            end
            sample_starts = sample_starts(1:B_actual);
        end

        idx_mat = bsxfun(@plus, sample_offsets, sample_starts);
        raw_gpu = samples_gpu(idx_mat) - samples_mean_gpu;
        phase_start = exp(-1j * 2 * pi * doppler_hz * double(sample_starts - 1) / fs);
        phase_gpu = reshape(gpuArray(cast(phase_start, prec)), 1, []);
        seg_gpu = raw_gpu .* (carrier_gpu .* phase_gpu);
        corr_batch = double(gather(prn_gpu' * seg_gpu));

        prompt_batch = corr_batch(1, :).';
        early_batch = corr_batch(2, :).';
        late_batch = corr_batch(3, :).';
        lock_metric_batch = abs(prompt_batch) ./ max(abs(early_batch) + abs(late_batch), eps);
        next_adjust_batch = choose_code_adjustment_batch(prompt_batch, early_batch, late_batch, options);
        should_search_batch = mod((batch_start:batch_start+B_actual-1).', options.code_search_interval_ms) == 0 ...
            | lock_metric_batch < options.code_lock_threshold;

        for b = 1:B_actual
            idx = batch_start + b - 1;
            p = prompt_batch(b);
            e = early_batch(b);
            l = late_batch(b);
            prompt_ms(idx) = p;
            early_ms(idx) = e;
            late_ms(idx) = l;
            code_phase_samples(idx) = sample_starts(b) - 1;
            lock_metric_ms(idx) = lock_metric_batch(b);
            cursor = cursor + step + next_adjust_batch(b);
            if should_search_batch(b)
                search_offsets = -options.code_search_half_span_samples : options.code_search_half_span_samples;
                [best_offset, best_metric] = search_local_code_offset_gpu( ...
                    samples_gpu, samples_mean_gpu, prn_prompt_gpu, sample_starts(b) + round(step), ...
                    samples_per_ms, search_offsets, carrier_gpu, doppler_hz, fs, prec);
                if best_offset ~= 0
                    old_cursor = cursor;
                    cursor = cursor + best_offset;
                    events(end+1) = struct( ... %#ok<AGROW>
                        'ms_index', idx, ...
                        'type', 'code_reacq', ...
                        'detail', sprintf('local_search_metric=%.1f', best_metric), ...
                        'old_value', old_cursor, ...
                        'new_value', cursor);
                end
            end
        end
        batch_start = batch_start + B_actual;
    end

    actual_ms = batch_start - 1;
    prompt_ms = prompt_ms(1:actual_ms);
    early_ms = early_ms(1:actual_ms);
    late_ms = late_ms(1:actual_ms);
    code_phase_samples = code_phase_samples(1:actual_ms);
    lock_metric_ms = lock_metric_ms(1:actual_ms);
end

function next_adjust = choose_code_adjustment_batch(prompt_corr, early_corr, late_corr, options)
    prompt_mag = abs(prompt_corr);
    early_mag = abs(early_corr);
    late_mag = abs(late_corr);
    next_adjust = zeros(size(prompt_mag));
    early_mask = early_mag > prompt_mag * options.code_switch_ratio & early_mag > late_mag;
    late_mask = late_mag > prompt_mag * options.code_switch_ratio & late_mag > early_mag;
    next_adjust(early_mask) = -1;
    next_adjust(late_mask) = +1;
end

function segment = extract_compensated_segment( ...
    samples, samples_mean, sample_start, samples_per_ms, carrier_one_ms, doppler_hz, fs)

    sample_end = sample_start + samples_per_ms - 1;
    segment = samples(sample_start:sample_end) - samples_mean;
    phase_start = exp(-1j * 2 * pi * doppler_hz * double(sample_start - 1) / fs);
    segment = segment .* (phase_start .* carrier_one_ms);
end

function next_adjust = choose_code_adjustment(prompt_corr, early_corr, late_corr, options)
    prompt_mag = abs(prompt_corr);
    early_mag = abs(early_corr);
    late_mag = abs(late_corr);

    if early_mag > prompt_mag * options.code_switch_ratio && early_mag > late_mag
        next_adjust = -1;
    elseif late_mag > prompt_mag * options.code_switch_ratio && late_mag > early_mag
        next_adjust = +1;
    else
        next_adjust = 0;
    end
end

function [best_offset, best_metric] = search_local_code_offset( ...
    samples, samples_mean, prn_one_ms, center_sample, samples_per_ms, ...
    search_offsets, carrier_one_ms, doppler_hz, fs)
    % 在当前估计点附近做一个很小的局部扫描，避免完整 acquisition 的高开销。
    best_offset = 0;
    best_metric = -inf;
    for off = search_offsets
        sample_start = center_sample + off;
        if sample_start < 1 || (sample_start + samples_per_ms - 1) > length(samples)
            continue;
        end
        segment = extract_compensated_segment( ...
            samples, samples_mean, sample_start, samples_per_ms, ...
            carrier_one_ms, doppler_hz, fs);
        metric = abs(sum(segment .* prn_one_ms));
        if metric > best_metric
            best_metric = metric;
            best_offset = off;
        end
    end
end

function [best_offset, best_metric] = search_local_code_offset_gpu( ...
    samples_gpu, samples_mean_gpu, prn_one_ms_gpu, center_sample, samples_per_ms, ...
    search_offsets, carrier_one_ms_gpu, doppler_hz, fs, prec)
    sample_starts = center_sample + search_offsets;
    valid_mask = sample_starts >= 1 & (sample_starts + samples_per_ms - 1) <= length(samples_gpu);
    if ~any(valid_mask)
        best_offset = 0;
        best_metric = -inf;
        return;
    end

    valid_starts = sample_starts(valid_mask);
    valid_offsets = search_offsets(valid_mask);
    idx_mat = bsxfun(@plus, (0:samples_per_ms-1)', valid_starts);
    raw_gpu = samples_gpu(idx_mat) - samples_mean_gpu;
    phase_start = exp(-1j * 2 * pi * doppler_hz * double(valid_starts - 1) / fs);
    phase_gpu = reshape(gpuArray(cast(phase_start, prec)), 1, []);
    seg_gpu = raw_gpu .* (carrier_one_ms_gpu .* phase_gpu);
    metrics = abs(double(gather(prn_one_ms_gpu' * seg_gpu)));
    [best_metric, best_idx] = max(metrics);
    best_offset = valid_offsets(best_idx);
end

function [prompt_fll, prompt_pll, carrier_history] = track_carrier_from_prompt(prompt_ms, options)
    % 载波跟踪分两步：
    %   1. FLL 先估频率漂移，解决“相位一直转”的问题
    %   2. PLL 再细调相位，把相关点尽量拉回实轴附近
    n_ms = length(prompt_ms);
    if n_ms < 2
        prompt_fll = prompt_ms;
        prompt_pll = prompt_ms;
        carrier_history = struct( ...
            'fll_freq_hz', zeros(n_ms, 1), ...
            'pll_phase_deg', zeros(n_ms, 1), ...
            'phase_error_deg', zeros(n_ms, 1), ...
            'final_freq_hz', 0, ...
            'code_error_proxy', zeros(n_ms, 1));
        return;
    end

    prompt_sq = prompt_ms .^ 2;
    df_inst_hz = zeros(n_ms, 1);
    df_inst_hz(2:end) = angle(conj(prompt_sq(1:end-1)) .* prompt_sq(2:end)) / (4 * pi * 1e-3);

    fll_freq_hz = movmean(df_inst_hz, options.fll_smooth_ms, 'Endpoints', 'shrink');
    fll_phase_rad = 2 * pi * cumsum(fll_freq_hz) * 1e-3;
    prompt_fll = prompt_ms .* exp(-1j * fll_phase_rad);

    pll_phase_rad = zeros(n_ms, 1);
    phase_error_rad = zeros(n_ms, 1);
    for k = 2:n_ms
        phase_error_rad(k) = 0.5 * wrap_to_pi(angle(prompt_fll(k).^2) - 2 * pll_phase_rad(k-1));
        pll_phase_rad(k) = pll_phase_rad(k-1) + options.pll_gain * phase_error_rad(k);
    end
    prompt_pll = prompt_fll .* exp(-1j * pll_phase_rad);

    carrier_history = struct();
    carrier_history.fll_freq_hz = fll_freq_hz;
    carrier_history.pll_phase_deg = rad2deg(pll_phase_rad);
    carrier_history.phase_error_deg = rad2deg(phase_error_rad);
    start_idx = max(2, n_ms - 200);
    carrier_history.final_freq_hz = median(fll_freq_hz(start_idx:end));
    carrier_history.code_error_proxy = abs(mean(exp(1j * 2 * angle(prompt_pll)))) * ones(n_ms, 1);
end

function [alignment, bit_offset_metrics] = estimate_initial_bit_alignment(prompt_pll, truth_pattern, options, accel_options)
    % 只在前一段训练数据里做 bit 对齐，避免整段长采集都参与搜索而拖慢流程。
    % 这里遍历 20 种 bit 边界和所有 truth pattern 起点，挑出最匹配的组合。
    if nargin < 4
        accel_options = struct();
    end
    gpu_on = isstruct(accel_options) && isfield(accel_options, 'gpu_enabled') && accel_options.gpu_enabled;

    training_ms = min(options.alignment_training_ms, length(prompt_pll));
    prompt_train = prompt_pll(1:training_ms);
    pattern_len = length(truth_pattern);

    offset_energy = nan(20, 1);
    score_map = -inf(20, pattern_len);
    match_map = nan(20, pattern_len);
    polarity_map = ones(20, pattern_len);

    % 预建 [pattern_len × pattern_len] 的循环移位参考矩阵（列 = 不同 pattern_offset）
    pattern = double(truth_pattern(:));
    pattern_cyc_long = repmat(pattern, ceil((pattern_len + pattern_len) / pattern_len) + 1, 1);
    ref_matrix_base = zeros(pattern_len, pattern_len);
    for po = 0:(pattern_len-1)
        ref_matrix_base(:, po+1) = pattern_cyc_long(po+1 : po+pattern_len);
    end

    best = struct('score', -inf);
    top_scores = -inf(2, 1);
    df_pre_hz = median(angle(conj(prompt_train(1:end-1).^2) .* prompt_train(2:end).^2) / (4 * pi * 1e-3));

    for bit_offset_ms = 0:19
        num_bits = floor((training_ms - bit_offset_ms) / 20);
        if num_bits < 4
            continue;
        end

        % 向量化 bit 积分：reshape + sum，替代 for k 循环
        trim_start = bit_offset_ms + 1;
        block = prompt_train(trim_start : trim_start + num_bits * 20 - 1);
        bit_corr = sum(reshape(block, 20, num_bits), 1).';

        offset_energy(bit_offset_ms + 1) = mean(abs(bit_corr));
        phi_axis = angle(sum(bit_corr.^2)) / 2;
        bit_corr_rot = bit_corr .* exp(-1j * phi_axis);
        bits = sign(real(bit_corr_rot));
        bits(bits == 0) = 1;

        % 构建 num_bits 行的参考矩阵：每列对应一个 pattern_offset，两个极性
        num_reps = ceil(num_bits / pattern_len) + 1;
        pattern_cyc = repmat(pattern, num_reps, 1);
        ref_matrix = zeros(num_bits, pattern_len);
        for po = 0:(pattern_len-1)
            ref_matrix(:, po+1) = pattern_cyc(po+1 : po+num_bits);
        end

        % 对两种极性分别计算所有 pattern_offset 的 match_rate 和 score
        % bits: [num_bits × 1], ref_matrix: [num_bits × pattern_len]
        if gpu_on
            prec = accel_options.precision_class;
            bits_gpu = gpuArray(cast(real(bits),               prec));  % bits 是 ±1 实数
            bcr_gpu  = gpuArray(cast(real(bit_corr_rot),       prec));
            ref_gpu  = gpuArray(cast(ref_matrix,               prec));
            % match_rate: mean(bits == ref) → mean(bits .* ref > 0)（因为 ±1 相等等价于乘积 > 0）
            match_plus  = double(gather(mean(bits_gpu ==  ref_gpu, 1)));
            match_minus = double(gather(mean(bits_gpu == -ref_gpu, 1)));
            corr_plus   = double(gather(mean(bcr_gpu  .*  ref_gpu, 1)));
            corr_minus  = double(gather(mean(bcr_gpu  .* -ref_gpu, 1)));
        else
            match_plus  = mean(bits ==  ref_matrix, 1);
            match_minus = mean(bits == -ref_matrix, 1);
            corr_plus   = mean(real(bit_corr_rot) .*  ref_matrix, 1);
            corr_minus  = mean(real(bit_corr_rot) .* -ref_matrix, 1);
        end

        score_plus  = 1e6 * match_plus  + 1e3 * corr_plus;
        score_minus = 1e6 * match_minus + 1e3 * corr_minus;

        for po_idx = 1:pattern_len
            pattern_offset = po_idx - 1;
            % 极性 +1
            s = score_plus(po_idx);
            mr = match_plus(po_idx);
            pol = 1;
            if s > score_map(bit_offset_ms + 1, po_idx)
                score_map(bit_offset_ms + 1, po_idx) = s;
                match_map(bit_offset_ms + 1, po_idx) = mr;
                polarity_map(bit_offset_ms + 1, po_idx) = pol;
            end
            top_scores = update_top_scores(top_scores, s);
            if s > best.score
                best = struct('score', s, 'bit_offset_ms', bit_offset_ms, ...
                    'pattern_offset', pattern_offset, 'polarity', pol, ...
                    'match_rate', mr, 'df_pre_hz', df_pre_hz);
            end
            % 极性 -1
            s = score_minus(po_idx);
            mr = match_minus(po_idx);
            pol = -1;
            if s > score_map(bit_offset_ms + 1, po_idx)
                score_map(bit_offset_ms + 1, po_idx) = s;
                match_map(bit_offset_ms + 1, po_idx) = mr;
                polarity_map(bit_offset_ms + 1, po_idx) = pol;
            end
            top_scores = update_top_scores(top_scores, s);
            if s > best.score
                best = struct('score', s, 'bit_offset_ms', bit_offset_ms, ...
                    'pattern_offset', pattern_offset, 'polarity', pol, ...
                    'match_rate', mr, 'df_pre_hz', df_pre_hz);
            end
        end
    end

    alignment = best;
    alignment.ambiguity_margin = top_scores(1) - top_scores(2);
    alignment.ambiguity_flag = alignment.match_rate < 0.7 || alignment.ambiguity_margin < 2e4;
    alignment.search_grid_summary = struct( ...
        'bit_offsets_ms', (0:19)', ...
        'pattern_offsets', (0:pattern_len-1)', ...
        'score_by_bit_offset_pattern', score_map, ...
        'match_rate_by_bit_offset_pattern', match_map, ...
        'best_polarity_by_bit_offset_pattern', polarity_map);

    bit_offset_metrics = struct();
    bit_offset_metrics.offset_energy = offset_energy;
end

function [window_metrics, events] = check_bit_timing_stability(prompt_pll, initial_bit_offset_ms, options, accel_options)
    % 初始 bit 对齐并不代表整个采集过程中一直正确。
    % 这个检查会周期性比较”当前 bit 边界的能量”与”局部最优边界的能量”，
    % 用来发现 overflow、重同步或慢性漂移导致的 bit timing 失配。
    if nargin < 4
        accel_options = struct();
    end
    gpu_on = isstruct(accel_options) && isfield(accel_options, 'gpu_enabled') && accel_options.gpu_enabled;

    step_ms = options.bit_timing_check_interval_ms;
    span_ms = min(options.bit_timing_check_span_ms, length(prompt_pll));
    num_windows = floor((length(prompt_pll) - span_ms) / step_ms) + 1;
    events = struct('ms_index', {}, 'type', {}, 'detail', {}, 'old_value', {}, 'new_value', {});

    window_match_rate = nan(num_windows, 1);
    window_bit_energy = nan(num_windows, 1);
    offset_candidates = 0:19;
    offset_energy_map = nan(num_windows, numel(offset_candidates));

    for win_idx = 1:num_windows
        ms_s = 1 + (win_idx - 1) * step_ms;
        ms_e = ms_s + span_ms - 1;
        prompt_window = prompt_pll(ms_s:ms_e);

        for off = offset_candidates
            num_bits = floor((length(prompt_window) - off) / 20);
            if num_bits < 2
                continue;
            end
            trim_s = off + 1;
            block = prompt_window(trim_s : trim_s + num_bits * 20 - 1);
            if gpu_on
                block_gpu = gpuArray(cast(block, accel_options.precision_class));
                bit_corr_off = double(gather(sum(reshape(block_gpu, 20, num_bits), 1).'));
            else
                bit_corr_off = sum(reshape(block, 20, num_bits), 1).';
            end
            offset_energy_map(win_idx, off + 1) = mean(abs(bit_corr_off));
        end

        base_energy = offset_energy_map(win_idx, initial_bit_offset_ms + 1);
        row_energy = offset_energy_map(win_idx, :);
        valid_mask = ~isnan(row_energy);
        if any(valid_mask)
            [best_energy, local_idx] = max(row_energy(valid_mask));
            valid_indices = find(valid_mask);
            best_idx = valid_indices(local_idx);
        else
            best_energy = NaN;
            best_idx = initial_bit_offset_ms + 1;
        end
        window_match_rate(win_idx) = base_energy / max(best_energy, eps);
        window_bit_energy(win_idx) = base_energy;
        best_offset_ms = best_idx - 1;
        if best_offset_ms ~= initial_bit_offset_ms && ...
                best_energy > base_energy * options.bit_timing_realign_margin
            events(end+1) = struct( ... %#ok<AGROW>
                'ms_index', ms_s, ...
                'type', 'bit_timing_watch', ...
                'detail', sprintf('best_energy=%.1f base_energy=%.1f', best_energy, base_energy), ...
                'old_value', initial_bit_offset_ms, ...
                'new_value', best_offset_ms);
        end
    end

    window_metrics = struct();
    window_metrics.window_match_rate = window_match_rate;
    window_metrics.window_bit_energy = window_bit_energy;
    window_metrics.offset_energy_map = offset_energy_map;
end

function [bit_corr, bit_times_s] = integrate_bits_from_prompt(prompt_pll, code_phase_samples, bit_offset_ms, samples_per_ms, fs, accel_options)
    % 把连续 20 个 prompt 相关结果积分成 1 个导航 bit 的复相关值。
    if nargin < 6
        accel_options = struct();
    end
    gpu_on = isstruct(accel_options) && isfield(accel_options, 'gpu_enabled') && accel_options.gpu_enabled;

    num_bits = floor((length(prompt_pll) - bit_offset_ms) / 20);
    trim_start = bit_offset_ms + 1;
    block = prompt_pll(trim_start : trim_start + num_bits * 20 - 1);

    if gpu_on
        block_gpu = gpuArray(cast(block, accel_options.precision_class));
        bit_corr = double(gather(sum(reshape(block_gpu, 20, num_bits), 1).'));
    else
        bit_corr = sum(reshape(block, 20, num_bits), 1).';
    end

    bit_times_s = double(code_phase_samples(trim_start : 20 : trim_start + (num_bits-1)*20)) / fs;
end

function ref_bits = build_reference_bits_local(pattern, num_bits, pattern_offset, polarity)
    pattern = double(pattern(:));
    pattern_cyc = repmat(pattern, ceil(num_bits / length(pattern)) + 1, 1);
    ref_bits = polarity * pattern_cyc(pattern_offset + 1 : pattern_offset + num_bits);
end

function window_ber = compute_window_ber(rx_bits, ref_bits, bit_times_s, window_bits, lock_quality)
    % 计算滑动窗口 BER 曲线。它回答的问题不是“总 BER 是多少”，
    % 而是“错误是不是集中在某一段时间爆发出来的”。
    if nargin < 4 || isempty(window_bits)
        window_bits = 100;
    end
    has_quality = nargin >= 5 && ~isempty(lock_quality) && length(lock_quality) == length(rx_bits);
    n_bits = length(rx_bits);
    step = max(1, floor(window_bits / 4));
    centers = [];
    ber_values = [];
    valid_flags = [];
    for idx = 1:step:(n_bits - window_bits + 1)
        idx_end = idx + window_bits - 1;
        centers(end+1, 1) = bit_times_s(round((idx + idx_end) / 2)); %#ok<AGROW>
        ber_values(end+1, 1) = mean(sign(rx_bits(idx:idx_end)) ~= sign(ref_bits(idx:idx_end))); %#ok<AGROW>
        if has_quality
            % 若本窗口内有任何比特的锁定质量低于阈值，标记为无效（不计入总 BER）
            valid_flags(end+1, 1) = all(lock_quality(idx:idx_end) >= 0.5); %#ok<AGROW>
        else
            valid_flags(end+1, 1) = true; %#ok<AGROW>
        end
    end
    window_ber = struct('time_s', centers, 'ber', ber_values, 'valid', logical(valid_flags));
end

function lock_quality = build_bit_lock_quality(lock_metric_ms, fll_freq_hz, window_metrics, bit_offset_ms, num_bits, options)
% 为每个比特计算锁定质量分数（0=无效，1=有效），用于在 BER 统计中屏蔽失锁窗口。
%
% 检测逻辑（两级）：
%   级别 1 — 触发：FLL 频率平滑值的帧间差分超过阈值，标记 overflow 起始点
%   级别 2 — 持续：window_match_rate < 阈值，比特边界能量已漂移（比特时序错误）
%
% 状态机：FLL 触发 → 进入失效；bit_match_rate 恢复 → 退出失效
% 正确处理"DLL/FLL 重锁但比特边界永久漂移"的 overflow 典型场景。
    n_ms = length(lock_metric_ms);

    % ── 级别 1：FLL 突变检测（overflow 触发点）────────────────────────
    fll_jump = abs(diff([fll_freq_hz(1); fll_freq_hz]));
    fll_trigger_ms = fll_jump > options.fll_jump_threshold_hz;

    % ── 级别 2：比特边界能量比（直接反映比特时序是否正确）──────────────
    % window_match_rate = base_energy / best_energy：
    %   - 比特时序正确时 ≈ 1.0
    %   - 比特时序错误时 << 1.0（当前 bit_offset 能量 < 最优偏移能量）
    bit_match_ok = true(num_bits, 1);
    if isfield(window_metrics, 'window_match_rate') && ~isempty(window_metrics.window_match_rate)
        check_interval_ms = options.bit_timing_check_interval_ms;
        for win_idx = 1:length(window_metrics.window_match_rate)
            mr = window_metrics.window_match_rate(win_idx);
            if isnan(mr) || mr < options.bit_match_rate_threshold
                ms_s = 1 + (win_idx - 1) * check_interval_ms;
                ms_e = min(n_ms, ms_s + check_interval_ms - 1);
                b_s = max(1, ceil((ms_s - bit_offset_ms) / 20));
                b_e = min(num_bits, floor((ms_e - bit_offset_ms) / 20));
                if b_e >= b_s
                    bit_match_ok(b_s:b_e) = false;
                end
            end
        end
    end

    % ── 状态机：进入失效 → 等待 match_rate 恢复才退出 ─────────────────
    lock_quality = ones(num_bits, 1);
    in_bad_state = false;
    for k = 1:num_bits
        ms_s = bit_offset_ms + 1 + (k-1) * 20;
        ms_e = min(n_ms, ms_s + 19);
        triggered = any(fll_trigger_ms(ms_s:ms_e)) || ...
                    min(lock_metric_ms(ms_s:ms_e)) < options.code_lock_threshold;
        if triggered
            in_bad_state = true;
        end
        % match_rate 恢复才允许退出失效状态
        if in_bad_state && bit_match_ok(k)
            in_bad_state = false;
        end
        if in_bad_state || ~bit_match_ok(k)
            lock_quality(k) = 0;
        end
    end
end

function top_scores = update_top_scores(top_scores, candidate)
    % 只保留前两名分数，用于估计最佳候选和次佳候选之间的歧义程度。
    if candidate > top_scores(1)
        top_scores = [candidate; top_scores(1)];
    elseif candidate > top_scores(2)
        top_scores(2) = candidate;
    end
end

function value = bpsk_cluster_strength(corr_values)
    % BPSK 理想锁定时，相位会聚成两团（相差 180 度），该指标越接近 1 表示聚类越明显。
    if isempty(corr_values)
        value = 0;
        return;
    end
    value = abs(mean(exp(1j * 2 * angle(corr_values))));
end

function y = wrap_to_pi(x)
    % 把任意相位角折叠回 [-pi, pi)，方便 PLL 使用最短角距离。
    y = mod(x + pi, 2 * pi) - pi;
end
