function result = run_ber_loopback_capture(capture_path, options)
%RUN_BER_LOOPBACK_CAPTURE Execute BER loopback analysis for one capture stem.
%
%   result = RUN_BER_LOOPBACK_CAPTURE(capture_path)
%   result = RUN_BER_LOOPBACK_CAPTURE(capture_path, options)
%
%   The input capture_path must point to one capture stem, or to its paired
%   .json / .sc16 file. The returned result struct contains the same core
%   outputs that run_ber_loopback.m historically left in the workspace.

if nargin < 1 || strlength(string(capture_path)) == 0
    error('GNSS_RX:MissingCapturePath', ...
        'run_ber_loopback_capture requires a capture stem / .json / .sc16 path.');
end
if nargin < 2 || isempty(options)
    options = struct();
end

options = apply_default_options(options);
capture_path = char(string(capture_path));

DEFAULT_TX_PATTERN = [+1, -1, +1, +1, -1, -1, +1, -1];
ACQ_DURATION_S = 0.1;
accel_options = gnss_rx_resolve_accel_options(options.accel_options);
stage_timings = struct();

fprintf('本次分析文件：%s\n', capture_path);
fprintf('加速配置：requested=%s, resolved=%s, precision=%s, batch_ms=%d, parfor=%d\n', ...
    accel_options.requested_backend, accel_options.resolved_backend, ...
    accel_options.precision, accel_options.batch_ms, accel_options.parfor_enabled);
if accel_options.gpu_enabled
    fprintf('GPU 设备：[%d] %s\n', accel_options.gpu_device_index, accel_options.gpu_device_name);
elseif ~isempty(accel_options.fallback_reason)
    fprintf('加速回退：%s\n', accel_options.fallback_reason);
end

fprintf('=== Step 1: 加载采集数据 ===\n');
step_timer = tic;
[samples, meta] = load_gnss_rx_capture(capture_path, accel_options.precision);
stage_timings.step1_load_s = toc(step_timer);
total_s = length(samples) / meta.sample_rate_hz;
fprintf('采集时长：%.1f 秒，样本数：%d\n', total_s, length(samples));
fprintf('Step 1 用时：%.2f s\n', stage_timings.step1_load_s);

fprintf('=== Step 2: GPS L1 C/A 捕获 ===\n');
fprintf('Step 2 后端：%s（precision=%s）\n', ...
    accel_options.resolved_backend, accel_options.precision);
step_timer = tic;
acq_len = round(ACQ_DURATION_S * meta.sample_rate_hz);
acq_samples = samples(1:min(acq_len, length(samples)));
acq_cfg = struct('accel_options', accel_options);
acq_result = run_prn_acquisition(acq_samples, meta, acq_cfg);
stage_timings.step2_acquisition_s = toc(step_timer);

if isfield(acq_result, 'detected')
    acq_detected = logical(acq_result.detected);
elseif isfield(acq_result, 'acquired')
    acq_detected = logical(acq_result.acquired);
else
    error('GNSS_RX:MissingAcqDetectedField', ...
        '捕获结果中既没有 detected 也没有 acquired 字段，无法判断捕获是否成功。');
end

if isfield(acq_result, 'second_peak_ratio')
    acq_peak_ratio = acq_result.second_peak_ratio;
elseif isfield(acq_result, 'secondary_peak_ratio')
    acq_peak_ratio = acq_result.secondary_peak_ratio;
else
    error('GNSS_RX:MissingAcqPeakRatioField', ...
        '捕获结果中既没有 second_peak_ratio 也没有 secondary_peak_ratio 字段。');
end

if ~acq_detected
    error('捕获失败！次峰比 = %.2f（阈值 2.5）。请检查信号链路或调整增益。', ...
        acq_peak_ratio);
end
fprintf('捕获成功！Doppler = %.1f Hz，码相位 = %d samples，次峰比 = %.2f\n', ...
    acq_result.best_doppler_hz, acq_result.best_code_phase_samples, ...
    acq_peak_ratio);
fprintf('Step 2 用时：%.2f s\n', stage_timings.step2_acquisition_s);

truth_path = '';
truth_source = 'internal_fallback';
truth_log_label = 'fallback 模式（使用默认参考 pattern）';
if ~isempty(options.tx_truth_path)
    truth_path = char(string(options.tx_truth_path));
    truth_source = 'explicit';
    truth_log_label = 'JSON 模式（显式 TX_TRUTH_PATH）';
else
    [truth_path, truth_source, truth_log_label] = discover_tx_truth_json( ...
        capture_path, options.workspace_tx_truth_fallback_path);
end

if ~isempty(truth_path) && isfile(truth_path)
    truth = load_tx_truth_json(truth_path);
    fprintf('TX truth：%s，来源 = %s\n', truth_log_label, truth.source_path);
else
    if strcmpi(truth_source, 'explicit') && ~isempty(truth_path)
        warning('显式指定的 TX_TRUTH_PATH 不存在：%s；当前将回退到脚本内默认 pattern。', truth_path);
    end
    truth = build_fallback_tx_truth(DEFAULT_TX_PATTERN, meta, acq_result);
    warning(['未提供 TX truth JSON；当前将回退到脚本内默认 pattern。', ...
        ' 该模式仅用于兼容旧流程，建议优先使用 gnss_tx 导出的 truth JSON。']);
    fprintf('TX truth：%s\n', truth_log_label);
end

fprintf('=== Step 3: open-loop truth 基线 ===\n');
fprintf('Step 3 后端：%s（precision=%s, batch_ms=%d）\n', ...
    accel_options.resolved_backend, accel_options.precision, accel_options.batch_ms);
step_timer = tic;
try
    [~, ~, open_loop_result] = recover_nav_bits(samples, meta, acq_result, truth, accel_options);
    fprintf('open-loop 匹配率：%.1f%%，bit 偏移：%d ms，pattern 偏移：%d bit\n', ...
        open_loop_result.match_rate * 100, ...
        open_loop_result.bit_offset_ms, open_loop_result.pattern_offset);
catch ME
    if is_out_of_memory_exception(ME)
        warning(['open-loop truth 基线在当前长采集上触发内存不足，', ...
            '将跳过 Step 3 并继续执行 tracked BER 主链。原始错误：%s'], ...
            ME.message);
        open_loop_result = build_skipped_open_loop_result(truth, ME.message);
    else
        rethrow(ME);
    end
end
stage_timings.step3_open_loop_s = toc(step_timer);
fprintf('Step 3 用时：%.2f s\n', stage_timings.step3_open_loop_s);

fprintf('=== Step 4: tracked BER 主链 ===\n');
fprintf('Step 4 计划后端：%s\n', accel_options.step4_backend_hint);
step_timer = tic;
tracked_result = track_nav_bits(samples, meta, acq_result, truth, options.tracking_options, accel_options);
stage_timings.step4_tracked_s = toc(step_timer);
fprintf('tracked BER：%.2e，匹配率：%.1f%%，bit 偏移：%d ms，pattern 偏移：%d bit\n', ...
    tracked_result.ber, tracked_result.match_rate * 100, ...
    tracked_result.bit_offset_ms, tracked_result.pattern_offset);
fprintf('Step 4 用时：%.2f s\n', stage_timings.step4_tracked_s);
fprintf('Step 4 实际后端：%s\n', tracked_result.accel_backend);

selected_result = tracked_result;
ber_mode = char(string(options.ber_mode));
if strcmpi(ber_mode, 'open_loop_truth')
    if isfield(open_loop_result, 'skipped') && open_loop_result.skipped
        warning('BER_MODE=open_loop_truth，但 open-loop 基线已被跳过；当前将回退到 tracked_truth。');
    else
        selected_result = open_loop_result;
    end
elseif ~strcmpi(ber_mode, 'tracked_truth')
    warning('未知 BER_MODE=%s，将回退到 tracked_truth。', ber_mode);
    ber_mode = 'tracked_truth';
end

fprintf('=== Step 5: truth 一致性判决 ===\n');
fprintf('分析模式：%s\n', ber_mode);
fprintf('最佳 bit 偏移：%d ms\n', selected_result.bit_offset_ms);
fprintf('最佳 pattern 偏移：%d bit\n', selected_result.pattern_offset);
fprintf('最佳极性：%+d\n', selected_result.polarity);
fprintf('truth 匹配率：%.1f%%\n', selected_result.match_rate * 100);

if selected_result.ambiguity_flag
    warning('最优候选与次优候选接近，当前结果存在 timing/truth ambiguity。');
end
if selected_result.match_rate < 0.55
    warning('最佳 truth 匹配率仅 %.1f%%，当前更像 truth mismatch 或 bit timing 歧义，而非稳定解调。', ...
        selected_result.match_rate * 100);
end

fprintf('=== Step 6: BER 统计 ===\n');
errors = sum(sign(selected_result.rx_bits) ~= sign(selected_result.ref_bits));
total_bits = length(selected_result.rx_bits);
ber = errors / total_bits;

fprintf('\n========================================\n');
fprintf('  BER 统计结果\n');
fprintf('========================================\n');
fprintf('  模式：        %s\n', ber_mode);
fprintf('  truth 模式：  %s\n', truth.truth_mode);
fprintf('  总发送比特数：%d\n', total_bits);
fprintf('  误码个数：    %d\n', errors);
fprintf('  BER：         %.2e\n', ber);
fprintf('  bit 偏移：    %d ms\n', selected_result.bit_offset_ms);
fprintf('  pattern 偏移：%d bit\n', selected_result.pattern_offset);
fprintf('  极性：        %+d\n', selected_result.polarity);
fprintf('  truth 匹配率：%.1f%%\n', selected_result.match_rate * 100);
fprintf('  请求后端：    %s\n', tracked_result.accel_requested_backend);
fprintf('  解析后端：    %s\n', tracked_result.accel_resolved_backend);
fprintf('  加速后端：    %s\n', tracked_result.accel_backend);
fprintf('  捕获 Doppler：%.1f Hz\n', acq_result.best_doppler_hz);
fprintf('  次峰比：      %.2f\n', acq_peak_ratio);
if isfield(tracked_result, 'fallback_reason') && ~isempty(tracked_result.fallback_reason)
    fprintf('  回退说明：    %s\n', tracked_result.fallback_reason);
end
fprintf('========================================\n');

analysis_result = struct();
analysis_result.ber_mode = ber_mode;
analysis_result.truth = truth;
analysis_result.truth_source = truth_source;
analysis_result.acq_result = acq_result;
analysis_result.acq_peak_ratio = acq_peak_ratio;
analysis_result.open_loop_result = open_loop_result;
analysis_result.tracked_result = tracked_result;
analysis_result.selected_result = selected_result;
analysis_result.errors = errors;
analysis_result.total_bits = total_bits;
analysis_result.ber = ber;
analysis_result.accel_options = accel_options;
analysis_result.stage_timings = stage_timings;

if options.plot_results
    plot_ber_loopback(analysis_result);
end

saved_result_path = '';
save_performed = false;
save_choice = char(string(options.save_choice));
if options.prompt_save
    save_choice = input('\n是否保存结果到 .mat 文件？[y/N]：', 's');
elseif isempty(save_choice)
    save_choice = 'n';
end

if strcmpi(strtrim(save_choice), 'y')
    results_dir = fullfile(fileparts(mfilename('fullpath')), '..', 'results');
    if ~exist(results_dir, 'dir')
        mkdir(results_dir);
    end
    saved_result_path = fullfile(results_dir, ...
        sprintf('ber_loopback_%s.mat', datestr(now, 'yyyymmdd_HHMMSS')));
    save(saved_result_path, 'truth', 'meta', 'acq_result', 'acq_peak_ratio', ...
        'open_loop_result', 'tracked_result', 'selected_result', ...
        'analysis_result', 'errors', 'total_bits', 'ber', 'ber_mode', ...
        'accel_options', 'stage_timings');
    fprintf('结果已保存至：%s\n', saved_result_path);
    save_performed = true;
else
    fprintf('已跳过保存。\n');
end

result = struct();
result.capture_path = capture_path;
result.truth = truth;
result.truth_path = truth_path;
result.truth_source = truth_source;
result.meta = meta;
result.acq_result = acq_result;
result.acq_peak_ratio = acq_peak_ratio;
result.open_loop_result = open_loop_result;
result.tracked_result = tracked_result;
result.selected_result = selected_result;
result.analysis_result = analysis_result;
result.errors = errors;
result.total_bits = total_bits;
result.ber = ber;
result.ber_mode = ber_mode;
result.accel_options = accel_options;
result.stage_timings = stage_timings;
result.saved_result_path = saved_result_path;
result.save_performed = save_performed;
end


function options = apply_default_options(options)
    if ~isfield(options, 'ber_mode') || isempty(options.ber_mode)
        options.ber_mode = 'tracked_truth';
    end
    if ~isfield(options, 'tx_truth_path') || isempty(options.tx_truth_path)
        options.tx_truth_path = '';
    end
    if ~isfield(options, 'tracking_options') || isempty(options.tracking_options)
        options.tracking_options = struct();
    end
    if ~isfield(options, 'accel_options') || isempty(options.accel_options)
        options.accel_options = struct();
    end
    if ~isfield(options, 'workspace_tx_truth_fallback_path') || isempty(options.workspace_tx_truth_fallback_path)
        options.workspace_tx_truth_fallback_path = '';
    end
    if ~isfield(options, 'plot_results') || isempty(options.plot_results)
        options.plot_results = true;
    end
    if ~isfield(options, 'prompt_save') || isempty(options.prompt_save)
        options.prompt_save = true;
    end
    if ~isfield(options, 'save_choice') || isempty(options.save_choice)
        options.save_choice = '';
    end
end


function [truth_path, truth_source, truth_log_label] = discover_tx_truth_json(capture_path, workspace_truth_path)
    truth_path = '';
    truth_source = 'internal_fallback';
    truth_log_label = 'fallback 模式（使用默认参考 pattern）';
    capture_str = char(string(capture_path));
    capture_dir = fileparts(capture_str);
    [~, capture_name, ext] = fileparts(capture_str);
    if strcmpi(ext, '.json') || strcmpi(ext, '.sc16')
        capture_stem = capture_name;
    else
        capture_stem = capture_name;
    end

    candidates = {
        fullfile(capture_dir, [capture_stem, '_tx_truth.json']), 'sidecar', 'JSON 模式（capture sidecar truth）'; ...
        fullfile(capture_dir, [capture_stem, '.truth.json']), 'sidecar', 'JSON 模式（capture sidecar truth）'; ...
        fullfile(capture_dir, 'tx_truth.json'), 'capture_dir', 'JSON 模式（capture 目录 truth）'; ...
        fullfile(capture_dir, 'ber_truth.json'), 'capture_dir', 'JSON 模式（capture 目录 truth）'};

    for k = 1:size(candidates, 1)
        candidate_path = candidates{k, 1};
        if isfile(candidate_path)
            truth_path = candidate_path;
            truth_source = candidates{k, 2};
            truth_log_label = candidates{k, 3};
            return;
        end
    end

    if ~isempty(workspace_truth_path) && isfile(workspace_truth_path)
        truth_path = workspace_truth_path;
        truth_source = 'workspace_fallback';
        truth_log_label = 'JSON 模式（workspace fallback truth）';
    end
end


function tf = is_out_of_memory_exception(ME)
    message_text = lower(char(string(ME.message)));
    identifier_text = lower(char(string(ME.identifier)));
    tf = contains(message_text, 'out of memory') ...
        || contains(message_text, '内存不足') ...
        || contains(identifier_text, 'nomem') ...
        || contains(identifier_text, 'outofmemory');
end


function result = build_skipped_open_loop_result(truth, reason)
    result = struct();
    result.mode = 'open_loop_truth';
    result.truth_mode = truth.truth_mode;
    result.rx_bits = zeros(0, 1);
    result.ref_bits = zeros(0, 1);
    result.bit_times_s = zeros(0, 1);
    result.match_rate = NaN;
    result.bit_offset_ms = NaN;
    result.pattern_offset = NaN;
    result.polarity = NaN;
    result.ambiguity_flag = true;
    result.skipped = true;
    result.skip_reason = reason;
    result.window_ber = struct('time_s', zeros(0, 1), 'ber', zeros(0, 1));
end
