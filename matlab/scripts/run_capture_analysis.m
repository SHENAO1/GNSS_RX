function result = run_capture_analysis(stem_or_json_path, cfg)
%RUN_CAPTURE_ANALYSIS 加载一组 GNSS_RX 采集文件，绘图并执行 PRN1 捕获。

script_dir = fileparts(mfilename('fullpath'));
matlab_root = fileparts(script_dir);
functions_dir = fullfile(matlab_root, 'functions');
% 入口脚本运行时自动把 functions/ 加入路径，避免手工 addpath。
if exist(functions_dir, 'dir') == 7
    addpath(functions_dir);
end

if nargin < 1
    stem_or_json_path = '';
end
if nargin < 2 || isempty(cfg)
    cfg = build_default_cfg();
end

if ~isfield(cfg, 'capture_root_dir') || isempty(cfg.capture_root_dir)
    cfg.capture_root_dir = gnss_rx_resolve_data_dir();
end

% 不传路径时，默认分析共享目录下最新的一组 .sc16 + .json。
if strlength(string(stem_or_json_path)) == 0
    stem_or_json_path = find_latest_capture(cfg.capture_root_dir);
end

fprintf('【GNSS_RX】分析目标文件：\n  %s\n', char(string(stem_or_json_path)));

[samples, meta, paths] = load_gnss_rx_capture(stem_or_json_path);
figures = plot_capture_overview(samples, meta, paths, cfg);
acq_result = run_prn1_acquisition(samples, meta, cfg);

% 多星对比搜索（PRN1~32），用于直观判断是哪颗星被捕获
survey = run_multi_prn_survey(samples, meta, cfg);
fig_survey = plot_multi_prn_survey(survey, paths, cfg);

save_info = save_analysis_artifacts(meta, paths, figures, acq_result, cfg);

% 额外保存多星对比图
if cfg.save_png && isfield(save_info, 'analysis_dir')
    survey_png = fullfile(save_info.analysis_dir, 'multi_prn_survey.png');
    try
        exportgraphics(fig_survey, survey_png, 'Resolution', 150);
    catch
        saveas(fig_survey, survey_png);
    end
end

fprintf('分析结果已保存至：\n  %s\n', save_info.analysis_dir);
if acq_result.detected
    detected_str = '成功';
else
    detected_str = '失败';
end
fprintf('捕获结果：%s | 峰值指标：%.3f | 次峰比：%.3f\n', ...
    detected_str, acq_result.peak_metric, acq_result.second_peak_ratio);
fprintf('最佳多普勒：%.1f Hz | 码相位：%d 个采样点\n', ...
    acq_result.best_doppler_hz, acq_result.best_code_phase_samples);

n_detected = sum(survey.detected);
if n_detected > 0
    detected_prns = survey.prn_list(survey.detected);
    prn_str = strjoin(arrayfun(@(x) num2str(x), detected_prns, 'UniformOutput', false), ', ');
    fprintf('多星搜索：PRN %s 捕获成功（共 %d/%d 颗）\n', prn_str, n_detected, numel(survey.prn_list));
else
    fprintf('多星搜索：全部 %d 颗星未捕获\n', numel(survey.prn_list));
end

result = struct( ...
    'samples', samples, ...
    'meta', meta, ...
    'paths', paths, ...
    'figures', figures, ...
    'acq_result', acq_result, ...
    'survey', survey, ...
    'fig_survey', fig_survey, ...
    'save_info', save_info);
end

function cfg = build_default_cfg()
% 默认配置优先服务”先跑通分析链”，而不是追求最重的搜索或绘图分辨率。
cfg = struct();
cfg.capture_root_dir = gnss_rx_resolve_data_dir();
cfg.time_plot_samples = 5000;
cfg.scatter_plot_samples = 20000;
cfg.spectrum_fft_len = 65536;
cfg.noncoherent_ms = 10;
cfg.doppler_min_hz = -10000;
cfg.doppler_max_hz = 10000;
cfg.doppler_step_hz = 500;
cfg.detection_threshold = 2.5;
cfg.figure_visibility = 'on';
cfg.save_png = true;
cfg.save_json_summary = true;
cfg.save_mat_summary = true;
end
