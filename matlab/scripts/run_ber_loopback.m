%% run_ber_loopback.m
% Milestone 1 BER 闭环验证主脚本
%
% 用法：
%   1. 修改下方 CAPTURE_PATH 为实际采集文件路径（stem 路径或 .json 路径）
%   2. 在 MATLAB 中运行：run matlab/scripts/run_ber_loopback.m
%
% 也可从命令行直接覆盖 CAPTURE_PATH：
%   CAPTURE_PATH = 'results/captures/xxx'; run_ber_loopback
%
% 输出：
%   - 控制台打印 BER 统计结果
%   - 结果保存至 results/ber_loopback_YYYYMMDD_HHMMSS.mat

clear; close all;
addpath(fullfile(fileparts(mfilename('fullpath')), '..', 'functions'));

%% ---- 用户配置区 -------------------------------------------------------
% 指定采集文件 stem（不带扩展名）或 .json 路径
% 若未提前赋值则弹出文件选择对话框
if ~exist('CAPTURE_PATH', 'var') || isempty(CAPTURE_PATH)
    [fn, fp] = uigetfile({'*.json;*.sc16', 'Capture files (*.json, *.sc16)'}, ...
                          '选择采集文件');
    if isequal(fn, 0)
        error('未选择采集文件，脚本终止。');
    end
    CAPTURE_PATH = fullfile(fp, fn);
end

% TX 端已知导航比特模式（+/-1 表示，与 DEFAULT_NAV_PATTERN 一致）
% 对应 "1 0 1 1 0 0 1 0"
TX_PATTERN = [+1, -1, +1, +1, -1, -1, +1, -1];

% 捕获所用前缀时长（秒），用于 run_prn_acquisition；取 100 ms 足够
ACQ_DURATION_S = 0.1;
%% -----------------------------------------------------------------------

%% Step 1：加载采集数据
fprintf('=== Step 1: 加载采集数据 ===\n');
[samples, meta] = load_gnss_rx_capture(CAPTURE_PATH);
total_s = length(samples) / meta.sample_rate_hz;
fprintf('采集时长：%.1f 秒，样本数：%d\n', total_s, length(samples));

%% Step 2：GPS L1 C/A 捕获（取前 ACQ_DURATION_S 秒）
fprintf('=== Step 2: GPS L1 C/A 捕获 ===\n');
acq_len     = round(ACQ_DURATION_S * meta.sample_rate_hz);
acq_samples = samples(1:min(acq_len, length(samples)));
acq_result  = run_prn_acquisition(acq_samples, meta, struct());

if ~acq_result.acquired
    error('捕获失败！次峰比 = %.2f（阈值 2.5）。请检查信号链路或调整增益。', ...
          acq_result.secondary_peak_ratio);
end
fprintf('捕获成功！Doppler = %.1f Hz，码相位 = %d samples，次峰比 = %.2f\n', ...
        acq_result.best_doppler_hz, acq_result.best_code_phase_samples, ...
        acq_result.secondary_peak_ratio);

%% Step 3：开环比特恢复
fprintf('=== Step 3: 开环比特恢复 ===\n');
[rx_bits, bit_times] = recover_nav_bits(samples, meta, acq_result);
fprintf('恢复比特数：%d\n', length(rx_bits));

if length(rx_bits) < 1000
    warning('恢复比特数不足 1000，请检查捕获结果或增大采集时长。');
end

%% Step 4：比特序列对齐（循环相位搜索）
fprintf('=== Step 4: 比特序列对齐 ===\n');
pattern_len = length(TX_PATTERN);
pattern_cyc = repmat(TX_PATTERN(:), ceil(length(rx_bits) / pattern_len) + 1, 1);

best_offset = 0;
best_match  = 0;
for offset = 0:pattern_len - 1
    ref        = pattern_cyc(offset + 1 : offset + length(rx_bits));
    match_rate = mean(sign(rx_bits) == sign(ref));
    if match_rate > best_match
        best_match  = match_rate;
        best_offset = offset;
    end
end
fprintf('最佳对齐偏移：%d bit（匹配率 %.1f%%）\n', best_offset, best_match * 100);

if best_match < 0.5
    warning('最高匹配率 %.1f%% < 50%%，序列可能反相，尝试取反...', best_match * 100);
    rx_bits    = -rx_bits;
    best_match = 1 - best_match;
    fprintf('取反后匹配率：%.1f%%\n', best_match * 100);
end

%% Step 5：BER 统计
fprintf('=== Step 5: BER 统计 ===\n');
ref_bits   = pattern_cyc(best_offset + 1 : best_offset + length(rx_bits));
errors     = sum(sign(rx_bits) ~= sign(ref_bits));
total_bits = length(rx_bits);
ber        = errors / total_bits;

fprintf('\n========================================\n');
fprintf('  BER 统计结果\n');
fprintf('========================================\n');
fprintf('  总发送比特数：%d\n',  total_bits);
fprintf('  误码个数：    %d\n',  errors);
fprintf('  BER：         %.2e\n', ber);
fprintf('  对齐相位偏移：%d bit\n', best_offset);
fprintf('  捕获 Doppler：%.1f Hz\n', acq_result.best_doppler_hz);
fprintf('  次峰比：      %.2f\n',  acq_result.secondary_peak_ratio);
fprintf('========================================\n');

%% Step 6：保存结果
results_dir = fullfile(fileparts(mfilename('fullpath')), '..', 'results');
if ~exist(results_dir, 'dir')
    mkdir(results_dir);
end
result_path = fullfile(results_dir, ...
    sprintf('ber_loopback_%s.mat', datestr(now, 'yyyymmdd_HHMMSS')));
save(result_path, 'rx_bits', 'ref_bits', 'errors', 'total_bits', 'ber', ...
     'acq_result', 'meta', 'best_offset');
fprintf('结果已保存至：%s\n', result_path);
