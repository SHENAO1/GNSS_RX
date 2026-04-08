function result = run_capture_analysis(stem_or_json_path, cfg)
%RUN_CAPTURE_ANALYSIS GNSS_RX 数据分析主入口：加载采集文件、绘图、执行信号捕获。
%
%   这是整个 MATLAB 分析链的顶层入口函数，按以下步骤自动完成：
%     1. 加载最新（或指定）采集文件（.sc16 IQ 数据 + .json 元数据）
%     2. 绘制时域、频谱、IQ 散点总览图（快速目视检查信号质量）
%     3. 对 PRN1 执行 Doppler × 码相位二维捕获搜索（寻找信号在哪里）
%     4. 对 PRN1~32 进行多星对比扫描，确认信号来自哪颗卫星
%     5. 将图片和摘要 JSON/MAT 保存到 analysis/<stem>/ 目录
%
%   用法示例：
%     result = run_capture_analysis()                          % 自动分析最新采集
%     result = run_capture_analysis('/path/to/capture.json')  % 分析指定文件
%     result = run_capture_analysis('', cfg)                  % 自动分析 + 自定义配置
%
%   输出 result 结构体包含 samples、meta、paths、acq_result、survey 等所有中间结果，
%   方便在命令窗口中进一步交互式分析。
%
%   如果要给别人介绍这条链，可以把它概括成三句话：
%     - 先把原始采集文件读进来，确认“拿到的是什么信号”
%     - 再做 acquisition / survey，确认“信号来自哪颗星、落在什么 Doppler 和码相位”
%     - 最后把图和摘要归档，方便复盘、对比和汇报

% 将 functions/ 目录加入 MATLAB 搜索路径，确保能找到各子函数。
% 使用 exist 检查避免重复加载（不影响功能，只是更整洁）。
script_dir    = fileparts(mfilename('fullpath'));
matlab_root   = fileparts(script_dir);
functions_dir = fullfile(matlab_root, 'functions');
if exist(functions_dir, 'dir') == 7
    addpath(functions_dir);
end

% 处理输入参数：未提供路径时默认为空字符串（后续自动找最新文件）。
if nargin < 1
    stem_or_json_path = '';
end
if nargin < 2 || isempty(cfg)
    cfg = build_default_cfg();
else
    cfg = merge_cfg_with_defaults(cfg, build_default_cfg());
end
if ~isfield(cfg, 'accel_options') || isempty(cfg.accel_options)
    cfg.accel_options = struct();
end
cfg.accel_options = gnss_rx_resolve_accel_options(cfg.accel_options);

% 如果配置中没有指定数据根目录，就自动解析默认路径。
if ~isfield(cfg, 'capture_root_dir') || isempty(cfg.capture_root_dir)
    cfg.capture_root_dir = gnss_rx_resolve_data_dir();
end

% 若未指定具体文件，自动在数据根目录下找最新的完整采集文件对。
if strlength(string(stem_or_json_path)) == 0
    stem_or_json_path = find_latest_capture(cfg.capture_root_dir);
end

fprintf('【GNSS_RX】分析目标文件：\n  %s\n', char(string(stem_or_json_path)));

% 步骤 1：加载 IQ 数据和元数据。
[samples, meta, paths] = load_gnss_rx_capture(stem_or_json_path, cfg.accel_options.precision);

% 步骤 2：绘制时域、频谱、IQ 散点总览图。
figures = plot_capture_overview(samples, meta, paths, cfg);

% 步骤 3：对目标 PRN 执行捕获搜索（PRN 编号从 meta.prn_id 读取，默认 PRN1）。
% 这是“粗同步”步骤，目的是先回答信号大概落在哪个 Doppler 和码相位。
acq_result = run_prn_acquisition(samples, meta, cfg);

% 步骤 4：对 PRN1~32 进行多星对比扫描（判断是哪颗卫星，或有几颗卫星可见）。
% 和单星捕获相比，多星扫描更像一次“身份核验”：谁的次峰比最高，谁就最可能是真正目标。
survey     = run_multi_prn_survey(samples, meta, cfg);
fig_survey = plot_multi_prn_survey(survey, paths, cfg);

% 步骤 5：保存分析产物（图片 + 摘要文件）。
save_info = save_analysis_artifacts(meta, paths, figures, acq_result, cfg);

% 额外保存多星对比图（优先用 exportgraphics 控制分辨率，失败则回退到 saveas）。
if cfg.save_png && isfield(save_info, 'analysis_dir')
    survey_png = fullfile(save_info.analysis_dir, 'multi_prn_survey.png');
    try
        exportgraphics(fig_survey, survey_png, 'Resolution', 150);
    catch
        saveas(fig_survey, survey_png);
    end
end

% 在命令窗口打印分析摘要，便于快速确认结果。
fprintf('分析结果已保存至：\n  %s\n', save_info.analysis_dir);
if acq_result.detected
    detected_str = '成功';
else
    detected_str = '失败';
end
acq_prn = acq_result.target_prn;
fprintf('PRN%d 捕获结果：%s | 峰值指标：%.3f | 次峰比：%.3f\n', ...
    acq_prn, detected_str, acq_result.peak_metric, acq_result.second_peak_ratio);
fprintf('最佳多普勒：%.1f Hz | 码相位：%d 个采样点\n', ...
    acq_result.best_doppler_hz, acq_result.best_code_phase_samples);

n_detected = sum(survey.detected);
if n_detected > 0
    detected_prns = survey.prn_list(survey.detected);
    prn_str = strjoin(arrayfun(@(x) num2str(x), detected_prns, 'UniformOutput', false), ', ');
    fprintf('多星扫描：PRN %s 捕获成功（共 %d/%d 颗）\n', prn_str, n_detected, numel(survey.prn_list));
else
    fprintf('多星扫描：全部 %d 颗星未捕获\n', numel(survey.prn_list));
end

% 将所有中间结果打包返回，方便在命令窗口中交互式进一步分析。
result = struct( ...
    'samples',    samples, ...
    'meta',       meta, ...
    'paths',      paths, ...
    'figures',    figures, ...
    'acq_result', acq_result, ...
    'survey',     survey, ...
    'fig_survey', fig_survey, ...
    'save_info',  save_info);
end


function cfg = build_default_cfg()
%BUILD_DEFAULT_CFG 构建分析链的默认配置，目标是”先跑通、快出结果”。
%
% 这些默认值偏向“第一次看数据先别太慢，也别太复杂”。
% 真正做深度排查时，最常调整的通常是 noncoherent_ms 和 Doppler 搜索范围。
cfg = struct();
cfg.capture_root_dir     = gnss_rx_resolve_data_dir();
cfg.time_plot_samples    = 5000;        % 时域图采样点数
cfg.scatter_plot_samples = 20000;       % IQ 散点图采样点数
cfg.spectrum_fft_len     = 65536;       % 频谱 FFT 点数
cfg.noncoherent_ms       = 10;          % 非相干累加毫秒数（10 ms 为当前默认；20 ms 灵敏度更高，100 ms 最强但慢）
cfg.doppler_min_hz       = -10000;      % Doppler 搜索下限（Hz）
cfg.doppler_max_hz       =  10000;      % Doppler 搜索上限（Hz）
cfg.doppler_step_hz      = 500;         % Doppler 搜索步长（Hz）
cfg.detection_threshold  = 2.5;         % 次峰比判决门限
cfg.figure_visibility    = 'on';        % 图窗显示（'off' 用于无头批量模式）
cfg.save_png             = true;        % 是否保存 PNG 图片
cfg.save_json_summary    = true;        % 是否保存 JSON 摘要
cfg.save_mat_summary     = true;        % 是否保存 MAT 摘要
cfg.accel_options        = struct();    % 可选：统一离线分析加速配置
end


function cfg = merge_cfg_with_defaults(cfg_override, cfg_defaults)
%MERGE_CFG_WITH_DEFAULTS 允许调用方只传想覆盖的 cfg 字段。
%
%   run_capture_analysis(..., cfg) 的约定是：
%   - 未传的字段继续沿用默认值
%   - 仅调用方显式提供且非空的字段才覆盖默认值
cfg = cfg_defaults;
if nargin < 1 || isempty(cfg_override)
    return;
end

override_fields = fieldnames(cfg_override);
for idx = 1:numel(override_fields)
    field_name = override_fields{idx};
    if ~isempty(cfg_override.(field_name))
        cfg.(field_name) = cfg_override.(field_name);
    end
end
end
