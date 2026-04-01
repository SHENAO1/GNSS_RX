%% run_ber_loopback.m
% BER 闭环验证脚本包装器：
%   - 保持历史工作区变量接口不变
%   - 交互式选择单个 capture
%   - 具体 BER 主逻辑委托给 run_ber_loopback_capture()

clearvars -except CAPTURE_PATH TX_TRUTH_PATH BER_MODE TRACKING_OPTIONS ACCEL_OPTIONS ...
    WORKSPACE_TX_TRUTH_FALLBACK_PATH RUN_BER_OPTIONS;
close all;

script_dir = fileparts(mfilename('fullpath'));
matlab_root = fileparts(script_dir);
functions_dir = fullfile(matlab_root, 'functions');
if exist(functions_dir, 'dir') == 7
    addpath(functions_dir);
end

if ~exist('BER_MODE', 'var') || isempty(BER_MODE)
    BER_MODE = 'tracked_truth';
end
if ~exist('TRACKING_OPTIONS', 'var') || isempty(TRACKING_OPTIONS)
    TRACKING_OPTIONS = struct();
end
if ~exist('ACCEL_OPTIONS', 'var') || isempty(ACCEL_OPTIONS)
    ACCEL_OPTIONS = struct();
end

if ~exist('CAPTURE_PATH', 'var') || isempty(CAPTURE_PATH)
    try
        latest_capture = find_latest_capture();
        fprintf('检测到最新采集文件：\n  %s\n', latest_capture);
        user_choice = input( ...
            '直接分析最新文件请按回车；如需手动选择文件请输入任意字符后回车：', ...
            's');
        if isempty(user_choice)
            CAPTURE_PATH = latest_capture;
        else
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

run_options = struct();
run_options.ber_mode = BER_MODE;
run_options.tracking_options = TRACKING_OPTIONS;
run_options.accel_options = ACCEL_OPTIONS;
if exist('TX_TRUTH_PATH', 'var') && ~isempty(TX_TRUTH_PATH)
    run_options.tx_truth_path = TX_TRUTH_PATH;
else
    run_options.tx_truth_path = '';
end
if exist('WORKSPACE_TX_TRUTH_FALLBACK_PATH', 'var') && ~isempty(WORKSPACE_TX_TRUTH_FALLBACK_PATH)
    run_options.workspace_tx_truth_fallback_path = WORKSPACE_TX_TRUTH_FALLBACK_PATH;
else
    run_options.workspace_tx_truth_fallback_path = fullfile(matlab_root, 'tx_truth.json');
end
if exist('RUN_BER_OPTIONS', 'var') && isstruct(RUN_BER_OPTIONS)
    run_options = merge_structs(run_options, RUN_BER_OPTIONS);
end

result = run_ber_loopback_capture(CAPTURE_PATH, run_options);

truth = result.truth;
meta = result.meta;
acq_result = result.acq_result;
acq_peak_ratio = result.acq_peak_ratio;
open_loop_result = result.open_loop_result;
tracked_result = result.tracked_result;
selected_result = result.selected_result;
analysis_result = result.analysis_result;
errors = result.errors;
total_bits = result.total_bits;
ber = result.ber;
BER_MODE = result.ber_mode;


function merged = merge_structs(base, override)
    merged = base;
    override_fields = fieldnames(override);
    for idx = 1:numel(override_fields)
        field_name = override_fields{idx};
        merged.(field_name) = override.(field_name);
    end
end
