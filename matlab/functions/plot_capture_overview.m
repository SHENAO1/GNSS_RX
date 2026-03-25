function figures = plot_capture_overview(samples, meta, paths, cfg)
%PLOT_CAPTURE_OVERVIEW 生成时域、频谱和 IQ 散点总览图。

if nargin < 4
    cfg = struct();
end
cfg = ensure_plot_defaults(cfg);

% 各类图只取一部分样本做展示，避免首版脚本在大文件上响应过慢。
time_count = min(cfg.time_plot_samples, numel(samples));
scatter_count = min(cfg.scatter_plot_samples, numel(samples));
fft_len = min(cfg.spectrum_fft_len, numel(samples));
fft_len = max(fft_len, 1024);
fft_len = 2 ^ floor(log2(double(fft_len)));

time_axis_ms = (0:time_count - 1) ./ double(meta.sample_rate_hz) * 1e3;
scatter_samples = samples(1:scatter_count);
spec_samples = samples(1:fft_len);

% 频谱图使用简单加窗 FFT，目标是快速检查信号结构而不是做严格谱估计。
window = 0.5 - 0.5 * cos(2 * pi * (0:fft_len - 1)' / max(fft_len - 1, 1));
spectrum = fftshift(fft(spec_samples .* window, fft_len));
freq_axis_mhz = linspace(-double(meta.sample_rate_hz) / 2, double(meta.sample_rate_hz) / 2, fft_len) ./ 1e6;
spectrum_db = 20 * log10(abs(spectrum) ./ max(abs(spectrum) + eps) + eps);

figures = struct();

figures.overview_time = figure('Name', 'GNSS_RX Time Overview', 'Visible', cfg.figure_visibility);
plot(time_axis_ms, real(samples(1:time_count)), 'LineWidth', 1.0);
hold on;
plot(time_axis_ms, imag(samples(1:time_count)), 'LineWidth', 1.0);
hold off;
grid on;
xlabel('Time (ms)');
ylabel('Amplitude');
title(sprintf('Time Overview: %s', paths.stem_name), 'Interpreter', 'none');
legend({'I', 'Q'}, 'Location', 'best');

figures.overview_spectrum = figure('Name', 'GNSS_RX Spectrum Overview', 'Visible', cfg.figure_visibility);
plot(freq_axis_mhz, spectrum_db, 'LineWidth', 1.0);
grid on;
xlabel('Frequency Offset (MHz)');
ylabel('Relative Magnitude (dB)');
title(sprintf('Spectrum Overview: %s', paths.stem_name), 'Interpreter', 'none');

figures.iq_scatter = figure('Name', 'GNSS_RX IQ Scatter', 'Visible', cfg.figure_visibility);
scatter(real(scatter_samples), imag(scatter_samples), 8, '.');
grid on;
axis equal;
xlabel('In-Phase');
ylabel('Quadrature');
title(sprintf('IQ Scatter: %s', paths.stem_name), 'Interpreter', 'none');
end

function cfg = ensure_plot_defaults(cfg)
% 绘图默认值集中放在这里，便于后续统一调整显示规模。
if ~isfield(cfg, 'time_plot_samples') || isempty(cfg.time_plot_samples)
    cfg.time_plot_samples = 5000;
end
if ~isfield(cfg, 'scatter_plot_samples') || isempty(cfg.scatter_plot_samples)
    cfg.scatter_plot_samples = 20000;
end
if ~isfield(cfg, 'spectrum_fft_len') || isempty(cfg.spectrum_fft_len)
    cfg.spectrum_fft_len = 65536;
end
if ~isfield(cfg, 'figure_visibility') || isempty(cfg.figure_visibility)
    cfg.figure_visibility = 'on';
end
end
