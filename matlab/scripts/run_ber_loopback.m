%% run_ber_loopback.m
% BER 闭环验证主脚本：
%   - open_loop_truth：现有 truth 驱动开环诊断基线
%   - tracked_truth：新的 tracking BER 主链（默认）
% 执行入口的 4 个关键量：
%   - CAPTURE_PATH：待分析的采集输入，可为 stem / .json / .sc16 路径
%   - latest_capture：当 CAPTURE_PATH 未显式给出时，自动选出的最新一组采集 stem
%   - TX_TRUTH_PATH：TX 导出的 truth JSON，用作参考真值，不是 IQ 采集输入
%   - BER_MODE：结果判决模式；默认 tracked_truth，但脚本仍会同时计算 open-loop 基线

clearvars -except CAPTURE_PATH TX_TRUTH_PATH BER_MODE TRACKING_OPTIONS ACCEL_OPTIONS;
close all;
addpath(fullfile(fileparts(mfilename('fullpath')), '..', 'functions'));

if ~exist('BER_MODE', 'var') || isempty(BER_MODE)
    BER_MODE = 'tracked_truth';
end
if ~exist('TRACKING_OPTIONS', 'var') || isempty(TRACKING_OPTIONS)
    TRACKING_OPTIONS = struct();
end
if ~exist('ACCEL_OPTIONS', 'var') || isempty(ACCEL_OPTIONS)
    ACCEL_OPTIONS = struct();
end

%% ---- 用户配置区 -------------------------------------------------------
if ~exist('CAPTURE_PATH', 'var') || isempty(CAPTURE_PATH)
    try
        % 这里只是在“自动帮用户选输入采集文件”，和 tracked_truth 模式本身无关。
        % find_latest_capture() 返回的是一组原始采集的 stem 路径：
        %   <capture_dir>/<capture_name>
        % 后续 load_gnss_rx_capture() 会据此补出同名 .json 与 .sc16。
        latest_capture = find_latest_capture();
        fprintf('检测到最新采集文件：\n  %s\n', latest_capture);
        user_choice = input( ...
            '直接分析最新文件请按回车；如需手动选择文件请输入任意字符后回车：', ...
            's');
        if isempty(user_choice)
            CAPTURE_PATH = latest_capture;
        else
            % 手动选择时可以直接选 .json 或 .sc16；loader 会自动推导配对文件。
            [fn, fp] = uigetfile({'*.json;*.sc16', 'Capture files (*.json, *.sc16)'}, ...
                                  '选择采集文件');
            if isequal(fn, 0)
                error('未选择采集文件，脚本终止。');
            end
            CAPTURE_PATH = fullfile(fp, fn);
        end
    catch ME
        warning('自动查找最新采集文件失败：%s\n将改为手动选择文件。', ME.message);
        [fn, fp] = uigetfile({'*.json;*.sc16', 'Capture files (*.json, *.sc16)'}, ...
                              '选择采集文件');
        if isequal(fn, 0)
            error('未选择采集文件，脚本终止。');
        end
        CAPTURE_PATH = fullfile(fp, fn);
    end
end
fprintf('本次分析文件：%s\n', char(string(CAPTURE_PATH)));

DEFAULT_TX_PATTERN = [+1, -1, +1, +1, -1, -1, +1, -1];
ACQ_DURATION_S = 0.1;
accel_options = gnss_rx_resolve_accel_options(ACCEL_OPTIONS);
stage_timings = struct();

fprintf('加速配置：requested=%s, resolved=%s, precision=%s, batch_ms=%d, parfor=%d\n', ...
    accel_options.requested_backend, accel_options.resolved_backend, ...
    accel_options.precision, accel_options.batch_ms, accel_options.parfor_enabled);
if accel_options.gpu_enabled
    fprintf('GPU 设备：[%d] %s\n', accel_options.gpu_device_index, accel_options.gpu_device_name);
elseif ~isempty(accel_options.fallback_reason)
    fprintf('加速回退：%s\n', accel_options.fallback_reason);
end
%% -----------------------------------------------------------------------

%% Step 1：加载采集数据
fprintf('=== Step 1: 加载采集数据 ===\n');
step_timer = tic;
[samples, meta] = load_gnss_rx_capture(CAPTURE_PATH, accel_options.precision);
stage_timings.step1_load_s = toc(step_timer);
total_s = length(samples) / meta.sample_rate_hz;
fprintf('采集时长：%.1f 秒，样本数：%d\n', total_s, length(samples));
fprintf('Step 1 用时：%.2f s\n', stage_timings.step1_load_s);

%% Step 2：GPS L1 C/A 捕获
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

%% Step 2.5：加载 TX truth 契约
truth_path = '';
if ~exist('TX_TRUTH_PATH', 'var') || isempty(TX_TRUTH_PATH)
    % 若未显式指定 TX_TRUTH_PATH，就尝试在采集目录旁边寻找 truth JSON。
    truth_path = discover_tx_truth_json(CAPTURE_PATH);
else
    truth_path = char(string(TX_TRUTH_PATH));
end

if ~isempty(truth_path) && isfile(truth_path)
    truth = load_tx_truth_json(truth_path);
    fprintf('TX truth：JSON 模式，来源 = %s\n', truth.source_path);
else
    truth = build_fallback_tx_truth(DEFAULT_TX_PATTERN, meta, acq_result);
    warning(['未提供 TX truth JSON；当前将回退到脚本内默认 pattern。', ...
             ' 该模式仅用于兼容旧流程，建议优先使用 gnss_tx 导出的 truth JSON。']);
    fprintf('TX truth：fallback 模式（使用默认参考 pattern）\n');
end

%% Step 3：open-loop truth 基线
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

%% Step 4：tracked BER 主链
fprintf('=== Step 4: tracked BER 主链 ===\n');
fprintf('Step 4 后端：cpu（tracking 主循环在 v1 保持 CPU）\n');
step_timer = tic;
tracked_result = track_nav_bits(samples, meta, acq_result, truth, TRACKING_OPTIONS, accel_options);
stage_timings.step4_tracked_s = toc(step_timer);
fprintf('tracked BER：%.2e，匹配率：%.1f%%，bit 偏移：%d ms，pattern 偏移：%d bit\n', ...
    tracked_result.ber, tracked_result.match_rate * 100, ...
    tracked_result.bit_offset_ms, tracked_result.pattern_offset);
fprintf('Step 4 用时：%.2f s\n', stage_timings.step4_tracked_s);

% 默认使用 tracked_truth 作为最终判决结果，但仍保留 open-loop_truth 作为诊断基线。
selected_result = tracked_result;
if strcmpi(BER_MODE, 'open_loop_truth')
    if isfield(open_loop_result, 'skipped') && open_loop_result.skipped
        warning('BER_MODE=open_loop_truth，但 open-loop 基线已被跳过；当前将回退到 tracked_truth。');
    else
        selected_result = open_loop_result;
    end
elseif ~strcmpi(BER_MODE, 'tracked_truth')
    warning('未知 BER_MODE=%s，将回退到 tracked_truth。', BER_MODE);
end

%% Step 5：truth 一致性判决
fprintf('=== Step 5: truth 一致性判决 ===\n');
fprintf('分析模式：%s\n', BER_MODE);
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

%% Step 6：BER 统计
fprintf('=== Step 6: BER 统计 ===\n');
errors = sum(sign(selected_result.rx_bits) ~= sign(selected_result.ref_bits));
total_bits = length(selected_result.rx_bits);
ber = errors / total_bits;

fprintf('\n========================================\n');
fprintf('  BER 统计结果\n');
fprintf('========================================\n');
fprintf('  模式：        %s\n', BER_MODE);
fprintf('  truth 模式：  %s\n', truth.truth_mode);
fprintf('  总发送比特数：%d\n', total_bits);
fprintf('  误码个数：    %d\n', errors);
fprintf('  BER：         %.2e\n', ber);
fprintf('  bit 偏移：    %d ms\n', selected_result.bit_offset_ms);
fprintf('  pattern 偏移：%d bit\n', selected_result.pattern_offset);
fprintf('  极性：        %+d\n', selected_result.polarity);
fprintf('  truth 匹配率：%.1f%%\n', selected_result.match_rate * 100);
fprintf('  捕获 Doppler：%.1f Hz\n', acq_result.best_doppler_hz);
fprintf('  次峰比：      %.2f\n', acq_peak_ratio);
fprintf('========================================\n');

%% Step 7：可视化
analysis_result = struct();
analysis_result.ber_mode = BER_MODE;
analysis_result.truth = truth;
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
plot_ber_loopback(analysis_result);

%% Step 8：保存结果
save_choice = input('\n是否保存结果到 .mat 文件？[y/N]：', 's');
if strcmpi(strtrim(save_choice), 'y')
    results_dir = fullfile(fileparts(mfilename('fullpath')), '..', 'results');
    if ~exist(results_dir, 'dir')
        mkdir(results_dir);
    end
    result_path = fullfile(results_dir, ...
        sprintf('ber_loopback_%s.mat', datestr(now, 'yyyymmdd_HHMMSS')));
    save(result_path, 'truth', 'meta', 'acq_result', 'acq_peak_ratio', ...
         'open_loop_result', 'tracked_result', 'selected_result', ...
         'analysis_result', 'errors', 'total_bits', 'ber', 'BER_MODE', ...
         'accel_options', 'stage_timings');
    fprintf('结果已保存至：%s\n', result_path);
else
    fprintf('已跳过保存。\n');
end

function truth_path = discover_tx_truth_json(capture_path)
    truth_path = '';
    capture_str = char(string(capture_path));
    capture_dir = fileparts(capture_str);
    [~, capture_name, ext] = fileparts(capture_str);
    if strcmpi(ext, '.json') || strcmpi(ext, '.sc16')
        capture_stem = capture_name;
    else
        capture_stem = capture_name;
    end

    candidates = {
        fullfile(capture_dir, 'tx_truth.json'), ...
        fullfile(capture_dir, 'ber_truth.json'), ...
        fullfile(capture_dir, [capture_stem, '_tx_truth.json']), ...
        fullfile(capture_dir, [capture_stem, '.truth.json'])};

    for k = 1:numel(candidates)
        if isfile(candidates{k})
            truth_path = candidates{k};
            return;
        end
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
