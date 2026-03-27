function [bits, timestamps_s] = recover_nav_bits(samples, meta, acq_result)
% RECOVER_NAV_BITS  基于捕获结果的开环导航比特恢复（无跟踪环路）
%
% 输入：
%   samples     - 复数 IQ 样本（列向量，complex double）
%   meta        - 采集元数据结构体（含字段 sample_rate）
%   acq_result  - run_prn_acquisition 返回的捕获结果结构体
%                 （含字段 best_doppler_hz, best_code_phase_samples）
%
% 输出：
%   bits         - 恢复的导航比特序列（列向量，+1/-1 整数）
%   timestamps_s - 每个比特对应的起始时间戳（秒，从采集开始计）
%
% 算法（开环，无跟踪环路）：
%   1. 去除 DC 偏置
%   2. 由捕获的 Doppler 偏移生成频率补偿复指数
%   3. 由捕获的码相位对齐本地 PRN 序列
%   4. 每 20 ms（1 个导航 bit = 20 个 C/A 码周期）做相关积分
%   5. 积分结果取符号 → 恢复 bit
%
% 注意：开环方案不跟踪频率/码相位变化。对于长数据（> 100 s），若本振存在频偏，
% 后期可能出现码相位漂移导致误码集中，可考虑分段捕获处理。

    fs               = meta.sample_rate_hz;
    chip_rate        = 1.023e6;
    samples_per_chip = fs / chip_rate;
    samples_per_ms   = round(fs * 1e-3);          % 每 ms 采样数（1 个 C/A 码周期）
    samples_per_bit  = samples_per_ms * 20;        % 每个导航 bit 的采样数（20 ms）
    code_phase       = acq_result.best_code_phase_samples;
    doppler_hz       = acq_result.best_doppler_hz;

    % 1. 去除 DC 偏置
    samples = samples(:) - mean(samples);

    % 2. 频率补偿（补偿 Doppler 偏移）
    n            = (0:length(samples)-1)';
    freq_comp    = exp(-1j * 2 * pi * doppler_hz * n / fs);
    samples_comp = samples .* freq_comp;

    % 3. 生成本地 PRN 序列（PRN 1，从捕获码相位对齐）
    prn_chips   = generate_ca_code(meta.prn_id);          % +/-1，1023 chip
    prn_samples = repelem(prn_chips, round(samples_per_chip));
    prn_one_ms  = prn_samples(1:samples_per_ms);          % 1 ms 的本地 PRN

    % 4. 从捕获码相位处开始处理（MATLAB 1-indexed）
    start_idx = code_phase + 1;

    % 5. 逐 bit 积分（每 bit = 20 ms = 20 个 C/A 码周期）
    num_bits     = floor((length(samples_comp) - start_idx + 1) / samples_per_bit);
    bits         = zeros(num_bits, 1);
    timestamps_s = zeros(num_bits, 1);

    for k = 1:num_bits
        bit_start = start_idx + (k - 1) * samples_per_bit;
        bit_end   = bit_start + samples_per_bit - 1;
        if bit_end > length(samples_comp)
            break;
        end
        bit_segment = samples_comp(bit_start:bit_end);

        % 对 20 个 C/A 码周期做相关累加（仅取实部，BPSK 信号 Q = 0）
        corr_sum = 0;
        for ms = 1:20
            ms_start = (ms - 1) * samples_per_ms + 1;
            ms_end   = ms * samples_per_ms;
            corr_sum = corr_sum + sum(real(bit_segment(ms_start:ms_end)) .* prn_one_ms);
        end

        bits(k)         = sign(corr_sum);
        timestamps_s(k) = (bit_start - 1) / fs;
    end

    % 去掉末尾未填充的零（sign(0) = 0）
    valid        = bits ~= 0;
    bits         = bits(valid);
    timestamps_s = timestamps_s(valid);
end
