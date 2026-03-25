function figures = plot_capture_overview(samples, meta, paths, cfg)
%PLOT_CAPTURE_OVERVIEW 生成三张信号总览图：时域波形、频谱和 IQ 散点。
%
%   这三张图是 GNSS 信号接收的第一步"肉眼检查"，帮助快速判断：
%     - 时域图：信号有没有严重截幅（削波）或明显噪声突刺
%     - 频谱图：信号频谱形状是否合理，有无强干扰（GPS L1 应呈 sinc² 形状）
%     - IQ 散点：点云是否基本圆形对称（若严重偏斜，说明 IQ 幅度不平衡）
%
%   为了在大文件上也能快速响应，各图只取一部分样本绘制（数量由 cfg 控制）。
%
%   输入：
%     samples  —— 复数基带样本
%     meta     —— 元数据结构体（须含 sample_rate_hz 字段）
%     paths    —— 路径结构体（用于图标题，须含 stem_name 字段）
%     cfg      —— 可选配置（详见 ensure_plot_defaults）
%
%   输出：figures 结构体，包含三个图形句柄

if nargin < 4
    cfg = struct();
end
cfg = ensure_plot_defaults(cfg);

% 计算各图实际使用的样本数，不超过文件总样本数。
time_count    = min(cfg.time_plot_samples,    numel(samples));
scatter_count = min(cfg.scatter_plot_samples, numel(samples));
fft_len       = min(cfg.spectrum_fft_len,     numel(samples));

% FFT 长度向下取 2 的整数次幂，FFT 在 2^N 长度时运算效率最高（基 2 快速算法）。
fft_len = max(fft_len, 1024);
fft_len = 2 ^ floor(log2(double(fft_len)));

% 时域图的横轴（单位：毫秒）。
time_axis_ms = (0 : time_count - 1) ./ double(meta.sample_rate_hz) * 1e3;

% 散点图和频谱图分别取各自所需的样本段。
scatter_samples = samples(1:scatter_count);
spec_samples    = samples(1:fft_len);

% 频谱计算：加 Hann 窗抑制频谱泄漏，然后做 FFT 并转为分贝值。
% Hann 窗公式：w(n) = 0.5 - 0.5*cos(2π*n/(N-1))，是最常用的谱分析窗函数之一。
window   = 0.5 - 0.5 * cos(2 * pi * (0 : fft_len - 1)' / max(fft_len - 1, 1));
spectrum = fftshift(fft(spec_samples .* window, fft_len));

% 频率轴（单位：MHz），fftshift 后 0 Hz 居中显示。
freq_axis_mhz = linspace(-double(meta.sample_rate_hz)/2, double(meta.sample_rate_hz)/2, fft_len) ./ 1e6;

% 归一化幅度谱（相对最大值），转换为分贝（dB）。
% 加 eps 避免对 0 取 log；max 归一化使最大值始终为 0 dB，便于比较不同采集。
spectrum_db = 20 * log10(abs(spectrum) ./ max(abs(spectrum) + eps) + eps);

figures = struct();

% 图 1：时域波形图（I/Q 分量分别用不同颜色显示）
figures.overview_time = figure('Name', 'GNSS_RX Time Overview', 'Visible', cfg.figure_visibility);
plot(time_axis_ms, real(samples(1:time_count)), 'LineWidth', 1.0);
hold on;
plot(time_axis_ms, imag(samples(1:time_count)), 'LineWidth', 1.0);
hold off;
grid on;
xlabel('时间 (ms)');
ylabel('归一化幅度');
title(sprintf('时域总览：%s', paths.stem_name), 'Interpreter', 'none');
legend({'I（同相）', 'Q（正交）'}, 'Location', 'best');

% 图 2：功率谱图（频域，用于检查信号带宽和有无干扰）
figures.overview_spectrum = figure('Name', 'GNSS_RX Spectrum Overview', 'Visible', cfg.figure_visibility);
plot(freq_axis_mhz, spectrum_db, 'LineWidth', 1.0);
grid on;
xlabel('频率偏移 (MHz)');
ylabel('相对幅度 (dB)');
title(sprintf('频谱总览：%s', paths.stem_name), 'Interpreter', 'none');

% 图 3：IQ 散点图（检查 I/Q 幅度平衡和直流偏置）
figures.iq_scatter = figure('Name', 'GNSS_RX IQ Scatter', 'Visible', cfg.figure_visibility);
scatter(real(scatter_samples), imag(scatter_samples), 8, '.');
grid on;
axis equal;
xlabel('同相分量 I');
ylabel('正交分量 Q');
title(sprintf('IQ 散点：%s', paths.stem_name), 'Interpreter', 'none');
end


function cfg = ensure_plot_defaults(cfg)
%ENSURE_PLOT_DEFAULTS 为绘图配置结构体填充缺省值。
if ~isfield(cfg, 'time_plot_samples') || isempty(cfg.time_plot_samples)
    cfg.time_plot_samples = 5000;      % 时域图显示的样本数（取前段即可看清波形）
end
if ~isfield(cfg, 'scatter_plot_samples') || isempty(cfg.scatter_plot_samples)
    cfg.scatter_plot_samples = 20000;  % IQ 散点图的样本数（多一点更能代表统计特性）
end
if ~isfield(cfg, 'spectrum_fft_len') || isempty(cfg.spectrum_fft_len)
    cfg.spectrum_fft_len = 65536;      % 频谱 FFT 点数（点数越多，频率分辨率越高）
end
if ~isfield(cfg, 'figure_visibility') || isempty(cfg.figure_visibility)
    cfg.figure_visibility = 'on';      % 'on' 显示图窗；'off' 用于批量无头模式
end
end
