function save_info = save_analysis_artifacts(meta, paths, figures, acq_result, cfg)
%SAVE_ANALYSIS_ARTIFACTS 将分析图像和结果摘要保存到磁盘。
%
%   所有产物保存在 paths.analysis_dir 目录下，该目录由 load_gnss_rx_capture
%   设置为 <capture_dir>/analysis/<stem_name>/，每次采集独立一个子目录，
%   不同采集文件的分析结果不会互相覆盖。
%
%   保存内容：
%     overview_time.png       —— 时域波形图
%     overview_spectrum.png   —— 频谱图
%     iq_scatter.png          —— IQ 散点图
%     prn1_acquisition.png    —— PRN1 捕获热力图（Doppler × 码相位）
%     analysis_summary.json   —— 采集与捕获结果的机器可读摘要（方便 Python 等工具读取）
%     analysis_summary.mat    —— 同上，MATLAB 格式（方便后续继续分析）
%
%   输入：
%     meta        —— 元数据结构体
%     paths       —— 路径结构体（来自 load_gnss_rx_capture）
%     figures     —— 图形句柄结构体（来自 plot_capture_overview）
%     acq_result  —— 捕获结果结构体（来自 run_prn1_acquisition）
%     cfg         —— 可选配置（详见 ensure_save_defaults）
%
%   这个函数对应“分析结束后的归档环节”。
%   它的目标不是再做新计算，而是把最重要的图和数字稳定地落盘，
%   方便后续发给别人、写汇报或做不同采集之间的横向比较。

if nargin < 5
    cfg = struct();
end
cfg = ensure_save_defaults(cfg);

% 若分析目录不存在则创建（mkdir 对已存在目录不会报错）。
analysis_dir = paths.analysis_dir;
if exist(analysis_dir, 'dir') ~= 7
    mkdir(analysis_dir);
end

% 保存三张总览图（时域、频谱、IQ 散点）。
if cfg.save_png
    export_figure(figures.overview_time,     fullfile(analysis_dir, 'overview_time.png'));
    export_figure(figures.overview_spectrum, fullfile(analysis_dir, 'overview_spectrum.png'));
    export_figure(figures.iq_scatter,        fullfile(analysis_dir, 'iq_scatter.png'));
end

% 绘制 PRN1 捕获热力图：X 轴为码相位，Y 轴为 Doppler，颜色代表相关功率（dB）。
% imagesc 把二维搜索图显示为伪彩色图，直观看出峰值所在位置。
acq_figure = figure('Name', 'GNSS_RX PRN1 Acquisition', 'Visible', cfg.figure_visibility);
imagesc(acq_result.code_phase_samples, acq_result.doppler_bins_hz, ...
        10 * log10(acq_result.search_map + eps));
axis xy;    % 使 Y 轴从下到上递增（默认 imagesc 是从上到下，与习惯相反）
grid on;
colorbar;
xlabel('码相位（采样点）');
ylabel('多普勒频移（Hz）');
title(sprintf('PRN1 捕获搜索图：%s', paths.stem_name), 'Interpreter', 'none');
hold on;
% 用白色 X 标记最佳峰值点，便于直观确认搜索结果。
plot(acq_result.best_code_phase_samples, acq_result.best_doppler_hz, ...
    'wx', 'MarkerSize', 12, 'LineWidth', 2);
hold off;

if cfg.save_png
    export_figure(acq_figure, fullfile(analysis_dir, 'prn1_acquisition.png'));
end

% 构建摘要结构体，以机器可读格式记录本次采集和捕获的关键结果。
% 使用 safe_meta 安全读取 meta 字段，避免旧版元数据缺少字段时报错。
summary = struct();
summary.stem_name        = paths.stem_name;
summary.capture_dir      = paths.capture_dir;
summary.json_path        = paths.json_path;
summary.sc16_path        = paths.sc16_path;
summary.sample_rate_hz   = safe_meta(meta, 'sample_rate_hz',   nan);
summary.center_freq_hz   = safe_meta(meta, 'center_freq_hz',   nan);
summary.duration_s       = safe_meta(meta, 'duration_s',       nan);
summary.signal_mode      = safe_meta(meta, 'signal_mode',      '');
summary.prn_id           = safe_meta(meta, 'prn_id',           nan);
summary.samples_captured = safe_meta(meta, 'samples_captured', nan);
summary.detected                = acq_result.detected;
summary.peak_metric             = acq_result.peak_metric;
summary.second_peak_ratio       = acq_result.second_peak_ratio;
summary.best_doppler_hz         = acq_result.best_doppler_hz;
summary.best_code_phase_samples = acq_result.best_code_phase_samples;
summary.num_noncoherent_ms      = acq_result.num_noncoherent_ms;
summary.analysis_dir            = analysis_dir;

% 保存 JSON 格式摘要（方便其他工具读取，例如 Python 脚本）。
if cfg.save_json_summary
    json_out_path = fullfile(analysis_dir, 'analysis_summary.json');
    fid = fopen(json_out_path, 'w');
    if fid < 0
        error('GNSS_RX:SummaryWriteFailed', '无法创建摘要 JSON 文件：%s', json_out_path);
    end
    % onCleanup 确保无论 fprintf 是否成功，文件句柄都会被关闭，避免资源泄漏。
    fid_cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
    fprintf(fid, '%s\n', jsonencode(summary));
end

% 保存 MAT 格式摘要（方便在 MATLAB 中直接 load 继续分析）。
if cfg.save_mat_summary
    save(fullfile(analysis_dir, 'analysis_summary.mat'), 'summary', 'acq_result');
end

save_info = struct();
save_info.analysis_dir       = analysis_dir;
save_info.acquisition_figure = acq_figure;
save_info.summary            = summary;
end


function cfg = ensure_save_defaults(cfg)
%ENSURE_SAVE_DEFAULTS 为保存配置结构体填充缺省值。
% 默认策略偏向“图和摘要都留一份”，这样最方便后续复盘。
if ~isfield(cfg, 'figure_visibility') || isempty(cfg.figure_visibility)
    cfg.figure_visibility = 'on';   % 保存时顺便显示图窗；设为 'off' 可静默批量保存
end
if ~isfield(cfg, 'save_png') || isempty(cfg.save_png)
    cfg.save_png = true;            % 默认保存所有 PNG 图片
end
if ~isfield(cfg, 'save_json_summary') || isempty(cfg.save_json_summary)
    cfg.save_json_summary = true;   % 默认保存 JSON 摘要
end
if ~isfield(cfg, 'save_mat_summary') || isempty(cfg.save_mat_summary)
    cfg.save_mat_summary = true;    % 默认保存 MAT 摘要
end
end


function export_figure(fig_handle, output_path)
%EXPORT_FIGURE 将图形窗口保存为图片文件。
%
%   优先尝试 exportgraphics（R2020a+，支持精确分辨率控制），
%   若不可用则回退到兼容性更好的 saveas。
try
    exportgraphics(fig_handle, output_path, 'Resolution', 150);
catch
    saveas(fig_handle, output_path);
end
end


function val = safe_meta(meta, field, default)
%SAFE_META 安全地从 meta 结构体中读取字段，字段不存在时返回默认值。
%
%   避免因旧版元数据缺少某些字段而导致 save_analysis_artifacts 中途报错。
if isfield(meta, field)
    val = meta.(field);
else
    val = default;
end
end
