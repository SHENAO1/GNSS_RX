function diagnostic = run_capture_iq_diagnostic(stem_or_json_path, options)
%RUN_CAPTURE_IQ_DIAGNOSTIC Diagnose raw IQ geometry for one capture.
%
%   diagnostic = RUN_CAPTURE_IQ_DIAGNOSTIC(capture_path)
%   diagnostic = RUN_CAPTURE_IQ_DIAGNOSTIC(capture_path, options)
%   diagnostic = RUN_CAPTURE_IQ_DIAGNOSTIC()
%
%   This helper is intended for quick verification when the raw IQ scatter
%   looks suspicious. It loads one capture, removes DC, estimates a coarse
%   BPSK phase rotation, then produces:
%     1. raw IQ scatter
%     2. DC-removed + phase-rotated IQ scatter
%     3. per-sample-phase scatter panels
%     4. numeric summary (DC level, phase angle, rotated Q/I ratio)

if nargin < 1
    stem_or_json_path = '';
end
if nargin < 2 || isempty(options)
    options = struct();
end

here = fileparts(mfilename('fullpath'));
functions_dir = fullfile(here, 'functions');
if exist(functions_dir, 'dir') == 7
    addpath(functions_dir);
end

options = apply_default_options(options);
if strlength(string(stem_or_json_path)) == 0
    capture_root_dir = gnss_rx_resolve_data_dir();
    stem_or_json_path = find_latest_capture(capture_root_dir);
end

[samples, meta, paths] = load_gnss_rx_capture(stem_or_json_path, options.output_precision);

sample_count = min(options.max_samples, numel(samples));
x = samples(1:sample_count);
x0 = x - mean(x);

moment2 = mean(x0 .^ 2);
if abs(moment2) <= eps(class(moment2))
    phi_rad = 0;
else
    phi_rad = 0.5 * angle(moment2);
end
xr = x0 * exp(-1j * phi_rad);

samples_per_chip = estimate_samples_per_chip(meta);
analysis_dir = ensure_analysis_dir(paths.analysis_dir);

summary = build_summary(x, x0, xr, phi_rad, meta, sample_count, samples_per_chip, analysis_dir);
print_summary(paths, summary);

figures = struct();
figures.scatter_compare = create_scatter_compare_figure(x, xr, paths, options);
figures.sample_phase = create_sample_phase_figure(xr, samples_per_chip, paths, options);

saved_paths = struct();
saved_paths.analysis_dir = analysis_dir;
saved_paths.scatter_compare_png = '';
saved_paths.sample_phase_png = '';
saved_paths.summary_json = '';
saved_paths.summary_mat = '';

if options.save_png
    saved_paths.scatter_compare_png = fullfile(analysis_dir, 'iq_diagnostic_compare.png');
    export_figure(figures.scatter_compare, saved_paths.scatter_compare_png);

    if ~isempty(figures.sample_phase)
        saved_paths.sample_phase_png = fullfile(analysis_dir, 'iq_diagnostic_sample_phase.png');
        export_figure(figures.sample_phase, saved_paths.sample_phase_png);
    end
end

if options.save_json_summary
    saved_paths.summary_json = fullfile(analysis_dir, 'iq_diagnostic_summary.json');
    write_text_file(saved_paths.summary_json, jsonencode(summary));
end

if options.save_mat_summary
    saved_paths.summary_mat = fullfile(analysis_dir, 'iq_diagnostic_summary.mat');
    save(saved_paths.summary_mat, 'summary');
end

diagnostic = struct();
diagnostic.capture_path = paths.stem_path;
diagnostic.meta = meta;
diagnostic.paths = paths;
diagnostic.summary = summary;
diagnostic.figures = figures;
diagnostic.saved_paths = saved_paths;
diagnostic.samples_preview = x;
diagnostic.centered_samples = x0;
diagnostic.rotated_samples = xr;
end


function options = apply_default_options(options)
    if ~isfield(options, 'output_precision') || isempty(options.output_precision)
        options.output_precision = 'double';
    end
    if ~isfield(options, 'max_samples') || isempty(options.max_samples)
        options.max_samples = 20000;
    end
    if ~isfield(options, 'sample_phase_plot_samples') || isempty(options.sample_phase_plot_samples)
        options.sample_phase_plot_samples = 5000;
    end
    if ~isfield(options, 'figure_visibility') || isempty(options.figure_visibility)
        options.figure_visibility = 'on';
    end
    if ~isfield(options, 'save_png') || isempty(options.save_png)
        options.save_png = true;
    end
    if ~isfield(options, 'save_json_summary') || isempty(options.save_json_summary)
        options.save_json_summary = true;
    end
    if ~isfield(options, 'save_mat_summary') || isempty(options.save_mat_summary)
        options.save_mat_summary = true;
    end
end


function samples_per_chip = estimate_samples_per_chip(meta)
    chip_rate_hz = 1.023e6;
    samples_per_chip_real = double(meta.sample_rate_hz) / chip_rate_hz;
    samples_per_chip_rounded = round(samples_per_chip_real);
    if abs(samples_per_chip_real - samples_per_chip_rounded) <= 1e-6
        samples_per_chip = samples_per_chip_rounded;
    else
        samples_per_chip = NaN;
    end
end


function analysis_dir = ensure_analysis_dir(analysis_dir)
    if exist(analysis_dir, 'dir') ~= 7
        mkdir(analysis_dir);
    end
end


function summary = build_summary(x, x0, xr, phi_rad, meta, sample_count, samples_per_chip, analysis_dir)
    raw_mean = mean(x);
    centered_std_i = std(real(x0));
    centered_std_q = std(imag(x0));
    rotated_std_i = std(real(xr));
    rotated_std_q = std(imag(xr));

    summary = struct();
    summary.sample_rate_hz = double(meta.sample_rate_hz);
    summary.sample_count_used = sample_count;
    summary.samples_per_chip = samples_per_chip;
    summary.mean_i = real(raw_mean);
    summary.mean_q = imag(raw_mean);
    summary.dc_magnitude = abs(raw_mean);
    summary.rms_magnitude = sqrt(mean(abs(x) .^ 2));
    summary.dc_to_rms_ratio = summary.dc_magnitude / max(summary.rms_magnitude, eps);
    summary.centered_std_i = centered_std_i;
    summary.centered_std_q = centered_std_q;
    summary.centered_q_to_i_ratio = centered_std_q / max(centered_std_i, eps);
    summary.phase_estimate_rad = phi_rad;
    summary.phase_estimate_deg = phi_rad * 180 / pi;
    summary.rotated_std_i = rotated_std_i;
    summary.rotated_std_q = rotated_std_q;
    summary.rotated_q_to_i_ratio = rotated_std_q / max(rotated_std_i, eps);
    summary.analysis_dir = analysis_dir;
end


function print_summary(paths, summary)
    fprintf('=== IQ Diagnostic ===\n');
    fprintf('capture path              : %s\n', paths.stem_path);
    fprintf('samples used              : %d\n', summary.sample_count_used);
    if ~isnan(summary.samples_per_chip)
        fprintf('samples/chip              : %d\n', summary.samples_per_chip);
    else
        fprintf('samples/chip              : NaN (sample rate not aligned to 1.023 Mcps)\n');
    end
    fprintf('mean(I), mean(Q)          : %.6f, %.6f\n', summary.mean_i, summary.mean_q);
    fprintf('DC magnitude / RMS        : %.6f / %.6f (ratio %.4f)\n', ...
        summary.dc_magnitude, summary.rms_magnitude, summary.dc_to_rms_ratio);
    fprintf('std(I), std(Q) centered   : %.6f, %.6f (Q/I %.4f)\n', ...
        summary.centered_std_i, summary.centered_std_q, summary.centered_q_to_i_ratio);
    fprintf('phase estimate            : %.2f deg\n', summary.phase_estimate_deg);
    fprintf('std(I), std(Q) rotated    : %.6f, %.6f (Q/I %.4f)\n', ...
        summary.rotated_std_i, summary.rotated_std_q, summary.rotated_q_to_i_ratio);
    fprintf('diagnostic output dir     : %s\n', summary.analysis_dir);
end


function fig = create_scatter_compare_figure(x, xr, paths, options)
    fig = figure('Name', 'GNSS_RX IQ Diagnostic Compare', 'Visible', options.figure_visibility);
    tiledlayout(fig, 1, 2, 'TileSpacing', 'compact', 'Padding', 'compact');

    nexttile;
    scatter(real(x), imag(x), 8, '.');
    axis equal;
    grid on;
    xlabel('同相分量 I');
    ylabel('正交分量 Q');
    title('原始 IQ');

    nexttile;
    scatter(real(xr), imag(xr), 8, '.');
    axis equal;
    grid on;
    xlabel('同相分量 I');
    ylabel('正交分量 Q');
    title('去均值 + 去相位后');

    sgtitle(sprintf('IQ 诊断：%s', paths.stem_name), 'Interpreter', 'none');
end


function fig = create_sample_phase_figure(xr, samples_per_chip, paths, options)
    if isnan(samples_per_chip) || samples_per_chip < 1
        fig = [];
        return;
    end

    fig = figure('Name', 'GNSS_RX IQ Diagnostic Sample Phase', 'Visible', options.figure_visibility);
    tile_rows = ceil(sqrt(samples_per_chip));
    tile_cols = ceil(samples_per_chip / tile_rows);
    tiledlayout(fig, tile_rows, tile_cols, 'TileSpacing', 'compact', 'Padding', 'compact');

    for phase_index = 1:samples_per_chip
        phase_samples = xr(phase_index:samples_per_chip:end);
        if isempty(phase_samples)
            phase_samples = xr([]);
        end
        phase_count = min(options.sample_phase_plot_samples, numel(phase_samples));

        nexttile;
        if phase_count > 0
            scatter(real(phase_samples(1:phase_count)), imag(phase_samples(1:phase_count)), 8, '.');
        end
        axis equal;
        grid on;
        xlabel('I');
        ylabel('Q');
        title(sprintf('sample phase %d', phase_index - 1));
    end

    sgtitle(sprintf('按 Sample Phase 分组：%s', paths.stem_name), 'Interpreter', 'none');
end


function export_figure(fig_handle, output_path)
    try
        exportgraphics(fig_handle, output_path, 'Resolution', 150);
    catch
        saveas(fig_handle, output_path);
    end
end


function write_text_file(output_path, text_content)
    fid = fopen(output_path, 'w');
    if fid < 0
        error('GNSS_RX:DiagnosticWriteFailed', '无法写入文件：%s', output_path);
    end
    fid_cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
    fprintf(fid, '%s\n', text_content);
end
