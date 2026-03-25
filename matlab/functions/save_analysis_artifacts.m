function save_info = save_analysis_artifacts(meta, paths, figures, acq_result, cfg)
%SAVE_ANALYSIS_ARTIFACTS 保存分析图像和结果摘要。

if nargin < 5
    cfg = struct();
end
cfg = ensure_save_defaults(cfg);

analysis_dir = paths.analysis_dir;
% 所有 MATLAB 侧产物统一落到 analysis/<stem>/，避免和原始采集文件混放。
if exist(analysis_dir, 'dir') ~= 7
    mkdir(analysis_dir);
end

if cfg.save_png
    export_figure(figures.overview_time, fullfile(analysis_dir, 'overview_time.png'));
    export_figure(figures.overview_spectrum, fullfile(analysis_dir, 'overview_spectrum.png'));
    export_figure(figures.iq_scatter, fullfile(analysis_dir, 'iq_scatter.png'));
end

% acquisition 图单独在这里生成，便于把最终判决点标在热力图上。
acq_figure = figure('Name', 'GNSS_RX PRN1 Acquisition', 'Visible', cfg.figure_visibility);
imagesc(acq_result.code_phase_samples, acq_result.doppler_bins_hz, 10 * log10(acq_result.search_map + eps));
axis xy;
grid on;
colorbar;
xlabel('Code Phase (samples)');
ylabel('Doppler (Hz)');
title(sprintf('PRN1 Acquisition: %s', paths.stem_name), 'Interpreter', 'none');
hold on;
plot(acq_result.best_code_phase_samples, acq_result.best_doppler_hz, 'wx', 'MarkerSize', 12, 'LineWidth', 2);
hold off;

if cfg.save_png
    export_figure(acq_figure, fullfile(analysis_dir, 'prn1_acquisition.png'));
end

% summary 用于后续自动归档、比对实验结果，字段尽量保持机器可读。
summary = struct();
summary.stem_name = paths.stem_name;
summary.capture_dir = paths.capture_dir;
summary.json_path = paths.json_path;
summary.sc16_path = paths.sc16_path;
summary.sample_rate_hz = meta.sample_rate_hz;
summary.center_freq_hz = meta.center_freq_hz;
summary.duration_s = meta.duration_s;
summary.signal_mode = meta.signal_mode;
summary.prn_id = meta.prn_id;
summary.samples_captured = meta.samples_captured;
summary.detected = acq_result.detected;
summary.peak_metric = acq_result.peak_metric;
summary.second_peak_ratio = acq_result.second_peak_ratio;
summary.best_doppler_hz = acq_result.best_doppler_hz;
summary.best_code_phase_samples = acq_result.best_code_phase_samples;
summary.num_noncoherent_ms = acq_result.num_noncoherent_ms;
summary.analysis_dir = analysis_dir;

if cfg.save_json_summary
    json_path = fullfile(analysis_dir, 'analysis_summary.json');
    fid = fopen(json_path, 'w');
    if fid < 0
        error('GNSS_RX:SummaryWriteFailed', 'Failed to open summary JSON for writing: %s', json_path);
    end
    fprintf(fid, '%s\n', jsonencode(summary));
    fclose(fid);
end

if cfg.save_mat_summary
    save(fullfile(analysis_dir, 'analysis_summary.mat'), 'summary', 'acq_result');
end

save_info = struct();
save_info.analysis_dir = analysis_dir;
save_info.acquisition_figure = acq_figure;
save_info.summary = summary;
end

function cfg = ensure_save_defaults(cfg)
% 保存开关统一集中，方便后续切换成“只显示不保存”的调试模式。
if ~isfield(cfg, 'figure_visibility') || isempty(cfg.figure_visibility)
    cfg.figure_visibility = 'on';
end
if ~isfield(cfg, 'save_png') || isempty(cfg.save_png)
    cfg.save_png = true;
end
if ~isfield(cfg, 'save_json_summary') || isempty(cfg.save_json_summary)
    cfg.save_json_summary = true;
end
if ~isfield(cfg, 'save_mat_summary') || isempty(cfg.save_mat_summary)
    cfg.save_mat_summary = true;
end
end

function export_figure(fig_handle, output_path)
% 这里先用最基础的 saveas，兼容性最好，后续需要时可再切 exportgraphics。
saveas(fig_handle, output_path);
end
