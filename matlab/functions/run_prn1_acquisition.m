function result = run_prn1_acquisition(samples, meta, cfg)
%RUN_PRN1_ACQUISITION 对一段基带 IQ 样本执行 GPS L1 C/A PRN1 信号捕获搜索。
%
%   GNSS 信号捕获的目标是在”时间-频率”二维搜索空间中找到信号峰值，
%   即同时确定：
%     - 码相位（code phase）：本地 C/A 码与接收信号对齐所需的时间偏移量
%     - 多普勒频移（Doppler）：因卫星和接收机相对运动导致的载波频率偏差
%
%   本函数使用”多毫秒非相干累加 + FFT 循环相关”方法：
%     1. 对每个 Doppler 假设，用复指数去旋转载波（去 Doppler）
%     2. 用 FFT 快速计算去 Doppler 后的样本与本地 C/A 码的循环相关
%     3. 对多个 1 ms 周期的相关功率做非相干累加（叠加），提升信噪比
%     4. 找二维搜索图中的最大峰值，用”主峰/次峰比”判断是否真正捕获到信号
%
%   输入：
%     samples  —— 复数基带样本列向量（已归一化到 [-1, 1]）
%     meta     —— 元数据结构体，须包含 prn_id 和 sample_rate_hz 字段
%     cfg      —— 可选配置结构体（各字段说明见 ensure_acq_defaults）
%
%   输出：result 结构体，包含捕获结论、峰值位置、多普勒估计和搜索图数据

% 若未传入配置，使用空结构体，由 ensure_acq_defaults 填充所有默认值。
if nargin < 3
    cfg = struct();
end
cfg = ensure_acq_defaults(cfg);

% 当前实现仅支持 PRN1，其他 PRN 请使用 run_multi_prn_survey。
if ~isfield(meta, 'prn_id') || meta.prn_id ~= 1
    error('GNSS_RX:UnsupportedPrn', ...
        '本函数当前仅支持 PRN1 捕获，其他 PRN 请使用 run_multi_prn_survey。');
end

% 验证输入样本非空。
if isempty(samples)
    error('GNSS_RX:EmptySamples', '输入样本为空，无法进行捕获搜索。');
end

% 采样率决定了每 1 ms（一个 C/A 码周期）内有多少个采样点。
% GPS C/A 码码率为 1.023 MHz，码长 1023 个码片，码周期恰好为 1 ms。
sample_rate_hz   = double(meta.sample_rate_hz);
samples_per_code = round(sample_rate_hz / 1000);

% 检查采样率是否能整除 1 ms 周期。若无法整除，循环相关将对不齐码边界，结果会出错。
if samples_per_code <= 0 || abs(sample_rate_hz / 1000 - samples_per_code) > 1e-6
    error('GNSS_RX:UnsupportedSampleRate', ...
        '采样率 %.6f Hz 无法整除 1 ms 码周期，请使用 1.023 MHz 整数倍采样率。', ...
        sample_rate_hz);
end

% 去除 DC 偏置（直流分量）。
% USRP 等 SDR 设备的本振（Local Oscillator）会产生轻微的载波泄漏，
% 表现为 IQ 信号的均值不为零。去均值可消除此影响，避免干扰相关运算。
samples = samples - mean(samples);

% 计算实际可用的 1 ms 片段数，非相干累加不超过可用片段数。
available_ms       = floor(numel(samples) / samples_per_code);
num_noncoherent_ms = min(cfg.noncoherent_ms, available_ms);
if num_noncoherent_ms < 1
    error('GNSS_RX:InsufficientData', '样本数不足 1 ms，无法进行捕获搜索。');
end

% 截取用于搜索的样本段（前 num_noncoherent_ms 个完整 1 ms 片段）。
search_samples = samples(1:(num_noncoherent_ms * samples_per_code));

% 生成 Doppler 搜索频率网格（等间隔离散化）。
doppler_bins_hz = cfg.doppler_min_hz : cfg.doppler_step_hz : cfg.doppler_max_hz;

% 生成本地 PRN1 C/A 码（按当前采样率重采样到 samples_per_code 个点）并做 FFT，
% 后续用于与接收信号做频域循环相关：
%   循环相关 = IFFT( FFT(信号) .* conj(FFT(本地码)) )
local_code     = build_sampled_prn1_code(samples_per_code, sample_rate_hz);
local_code_fft = fft(local_code);

% 生成时间轴，用于构造各 Doppler 假设下的复指数载波（去 Doppler 用）。
t = (0 : samples_per_code - 1)' ./ sample_rate_hz;   % 单位：秒

% 初始化二维搜索图：行 = Doppler 格，列 = 码相位（采样点）。
search_map = zeros(numel(doppler_bins_hz), samples_per_code);

for doppler_idx = 1:numel(doppler_bins_hz)
    fd = doppler_bins_hz(doppler_idx);

    % 构造去 Doppler 复指数：exp(-j*2π*fd*t)
    % 将接收信号与该复指数相乘，即可把频率为 fd 的 Doppler 分量搬移回零频。
    carrier = exp(-1j * 2 * pi * fd * t);
    accumulated_power = zeros(1, samples_per_code);

    for ms_idx = 1:num_noncoherent_ms
        % 提取当前 1 ms 片段。
        sample_offset = (ms_idx - 1) * samples_per_code;
        segment = search_samples(sample_offset + 1 : sample_offset + samples_per_code);

        % 第一步：去 Doppler（频率搬移）
        mixed = segment .* carrier;

        % 第二步：FFT 循环相关（复杂度 O(N log N)，远优于直接滑窗的 O(N²)）
        correlation = ifft(fft(mixed) .* conj(local_code_fft));

        % 第三步：取功率（模平方）并非相干累加。
        % “非相干”是指累加功率而非复数幅值，不需要相位对齐，鲁棒性更强。
        accumulated_power = accumulated_power + abs(correlation(:)).' .^ 2;
    end

    search_map(doppler_idx, :) = accumulated_power;
end

% 在二维搜索图中找全局最大值，即最佳 Doppler + 码相位组合。
[peak_value, peak_linear_idx] = max(search_map(:));
[best_doppler_idx, best_code_idx] = ind2sub(size(search_map), peak_linear_idx);
best_doppler_hz = doppler_bins_hz(best_doppler_idx);

% 计算次峰比（second peak ratio），这是判断是否真正捕获到信号的主要指标。
% 做法：在主峰附近挖掉一个”排除窗口”，在剩余位置找次大值。
% 若主峰/次峰比远大于 1，说明主峰显著突出，信号被真正捕获；
% 若比值接近 1，说明搜索图没有明显峰，只是噪声波动。
masked_map = search_map;

% 排除窗口宽度为 1 个码片对应的样本数（最少 1 个样本）。
% mod 取模运算用于处理码相位在 0 或末尾时窗口绕回的边界情况。
chip_exclusion = max(1, round(samples_per_code / 1023));
excl_idx = mod((best_code_idx - 1 - chip_exclusion) : (best_code_idx - 1 + chip_exclusion), ...
               samples_per_code) + 1;
masked_map(:, excl_idx) = 0;
second_peak = max(masked_map(:));

if isempty(second_peak) || second_peak <= 0
    % 没有次峰（极不可能），视为无穷大，说明主峰绝对突出。
    second_peak_ratio = inf;
else
    second_peak_ratio = peak_value / second_peak;
end

% 峰值指标（peak metric）= 主峰功率 / 平均功率，反映整体信噪比水平。
mean_floor  = mean(search_map(:));
peak_metric = peak_value / max(mean_floor, eps);

% 判决：次峰比超过阈值则认为捕获成功。
detected = second_peak_ratio >= cfg.detection_threshold;

% 打包所有结果到输出结构体，供后续绘图和保存使用。
result = struct();
result.detected                = logical(detected);
result.peak_value              = peak_value;
result.peak_metric             = peak_metric;
result.second_peak_ratio       = second_peak_ratio;
result.best_doppler_hz         = best_doppler_hz;
result.best_code_phase_samples = best_code_idx - 1;   % 转为 0-indexed（与 Python 侧一致）
result.doppler_bins_hz         = doppler_bins_hz;
result.code_phase_samples      = 0 : (samples_per_code - 1);
result.search_map              = search_map;
result.num_noncoherent_ms      = num_noncoherent_ms;
result.samples_per_code        = samples_per_code;
end


function cfg = ensure_acq_defaults(cfg)
%ENSURE_ACQ_DEFAULTS 为捕获配置结构体填充缺省值。
%
%   这些默认值优先保证”能先看到信号峰”，适合实验室短距离环境下的初步验证。
%   多普勒搜索范围 ±10 kHz 覆盖了绝大多数地面测试场景（实际卫星多普勒可达 ±5 kHz）。
if ~isfield(cfg, 'noncoherent_ms') || isempty(cfg.noncoherent_ms)
    cfg.noncoherent_ms = 10;        % 非相干累加毫秒数：累加越多信噪比越高，但耗时也越长
end
if ~isfield(cfg, 'doppler_min_hz') || isempty(cfg.doppler_min_hz)
    cfg.doppler_min_hz = -10000;    % Doppler 搜索下限（Hz）
end
if ~isfield(cfg, 'doppler_max_hz') || isempty(cfg.doppler_max_hz)
    cfg.doppler_max_hz = 10000;     % Doppler 搜索上限（Hz）
end
if ~isfield(cfg, 'doppler_step_hz') || isempty(cfg.doppler_step_hz)
    cfg.doppler_step_hz = 500;      % Doppler 搜索步长（Hz）：步长越小越精确，格数越多
end
if ~isfield(cfg, 'detection_threshold') || isempty(cfg.detection_threshold)
    cfg.detection_threshold = 2.5;  % 次峰比判决门限：高于此值判为捕获成功
end
end


function sampled_code = build_sampled_prn1_code(samples_per_code, sample_rate_hz)
%BUILD_SAMPLED_PRN1_CODE 将 PRN1 的 1023 个 C/A 码码片重采样到 samples_per_code 个点。
%
%   GPS C/A 码码率为 1.023 MHz（每秒 1,023,000 个码片），码周期为 1 ms（1023 个码片）。
%   重采样的做法：对每个采样时刻，计算它对应的码片索引，直接查表取码片值。
%   这等效于在数字域对 C/A 码做矩形脉冲成形。
chip_rate_hz = 1.023e6;   % GPS C/A 码码率（固定值）
chip_count   = 1023;      % C/A 码码长（固定值）

% 计算每个采样点对应的码片索引（floor 取整，mod 循环，+1 转为 1-indexed）。
chip_indices = floor((0 : samples_per_code - 1) * chip_rate_hz / sample_rate_hz);
chip_indices = mod(chip_indices, chip_count) + 1;

ca_code      = generate_prn1_ca_code();
sampled_code = ca_code(chip_indices).';
end


function code = generate_prn1_ca_code()
%GENERATE_PRN1_CA_CODE 生成 GPS L1 C/A PRN1 的完整码序列，输出 +1/-1 双极性格式。
%
%   GPS C/A 码由两个 10 级线性反馈移位寄存器（LFSR）G1 和 G2 的输出异或生成。
%   寄存器初始全为 1，运行 1023 步后输出一个完整周期的伪随机码。
%   PRN1 使用 G2 寄存器的第 2、6 位（1-indexed）异或作为 G2 输出抽头。
%
%   输出格式：0 → +1，1 → -1（双极性表示，方便与接收信号直接做相关运算）

% 两个 10 级寄存器，初始状态全为 1（全 1 是 GPS 标准规定的初始条件）。
g1 = true(1, 10);
g2 = true(1, 10);
code = zeros(1, 1023);

for idx = 1:1023
    % G1 的输出来自第 10 位（最右位）。
    g1_out = g1(10);
    % PRN1 的 G2 输出：第 2 位和第 6 位异或（抽头由 GPS ICD 规定）。
    g2_out = xor(g2(2), g2(6));
    % 最终码片 = G1 输出 XOR G2 输出。
    code(idx) = xor(g1_out, g2_out);

    % G1 反馈多项式：x^10 + x^3 + 1（第 3 位和第 10 位异或后移入）。
    g1_feedback = xor(g1(3), g1(10));
    % G2 反馈多项式：x^10 + x^9 + x^8 + x^6 + x^3 + x^2 + 1。
    g2_feedback = xor(xor(xor(xor(xor(g2(2), g2(3)), g2(6)), g2(8)), g2(9)), g2(10));

    % 寄存器左移（新反馈位移入最高位）。
    g1 = [g1_feedback, g1(1:9)];
    g2 = [g2_feedback, g2(1:9)];
end

% 将 0/1 二进制码转为 +1/-1 双极性格式：0 → +1，1 → -1。
code = 1 - 2 * double(code);
end
