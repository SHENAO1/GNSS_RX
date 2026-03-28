function [bits, timestamps_s, recovery_result] = recover_nav_bits(samples, meta, acq_result, truth)
% RECOVER_NAV_BITS 基于捕获结果进行开环导航比特恢复，并输出结构化诊断结果。
%
% 兼容性：
%   [bits, timestamps_s] = recover_nav_bits(samples, meta, acq_result)
%   [bits, timestamps_s, recovery_result] = recover_nav_bits(samples, meta, acq_result, truth)
%
% 当提供 truth.nav_bits_pattern_pm1 时，函数会进行联合搜索：
%   bit_offset_ms × pattern_offset × polarity
% 并返回结构化评分、诊断和最优候选结果。

    if nargin < 4
        truth = struct();
    end

    fs               = meta.sample_rate_hz;
    chip_rate        = 1.023e6;
    epochs_per_bit   = 20;
    samples_per_chip = fs / chip_rate;
    samples_per_ms   = round(fs * 1e-3);
    code_phase       = acq_result.best_code_phase_samples;
    doppler_hz       = acq_result.best_doppler_hz;

    samples = samples(:) - mean(samples);
    n = (0:length(samples)-1)';
    freq_comp = exp(-1j * 2 * pi * doppler_hz * n / fs);
    samples_comp = samples .* freq_comp;

    prn_chips = generate_ca_code(meta.prn_id);
    prn_samples = repelem(prn_chips, round(samples_per_chip));
    prn_one_ms = prn_samples(1:samples_per_ms)';

    base_start = code_phase + 1;
    num_ms = floor((length(samples_comp) - base_start + 1) / samples_per_ms);
    if num_ms < epochs_per_bit
        bits = zeros(0, 1);
        timestamps_s = zeros(0, 1);
        recovery_result = struct();
        warning('GNSS_RX:NotEnoughMsBlocks', ...
            '码相位对齐后不足 %d 个 1 ms 块，无法恢复一个完整导航 bit。', ...
            epochs_per_bit);
        return;
    end

    corr_ms = complex(zeros(num_ms, 1));
    for k = 1:num_ms
        ms_s = base_start + (k-1) * samples_per_ms;
        ms_e = ms_s + samples_per_ms - 1;
        corr_ms(k) = sum(samples_comp(ms_s:ms_e) .* prn_one_ms);
    end

    n_pre_ms = min(2000, num_ms);
    sq_pre = corr_ms(1:n_pre_ms).^2;
    dphi_pre = angle(conj(sq_pre(1:end-1)) .* sq_pre(2:end));
    df_pre_hz = median(dphi_pre) / (4 * pi * 1e-3);
    fprintf('预估残余频偏（比特边界搜索前）：Δf_pre = %.3f Hz\n', df_pre_hz);

    t_ms = (0:num_ms-1)' * 1e-3;
    corr_ms_fcorr = corr_ms .* exp(-1j * 2 * pi * df_pre_hz * t_ms);

    n_diag_ms = min(8, num_ms);
    fprintf('--- 诊断（前 %d 个 1 ms 相关）---\n', n_diag_ms);
    fprintf('  |corr_ms|:   '); fprintf('%8.1f ', abs(corr_ms_fcorr(1:n_diag_ms))); fprintf('\n');
    fprintf('  相位(°):     '); fprintf('%8.1f ', rad2deg(angle(corr_ms_fcorr(1:n_diag_ms)))); fprintf('\n');

    have_truth = isstruct(truth) && isfield(truth, 'nav_bits_pattern_pm1') ...
        && ~isempty(truth.nav_bits_pattern_pm1);

    if have_truth
        truth_pattern = double(truth.nav_bits_pattern_pm1(:));
        [search_grid_summary, best_candidate] = joint_search_with_truth( ...
            corr_ms_fcorr, base_start, samples_per_ms, fs, epochs_per_bit, truth_pattern);

        bits = best_candidate.rx_bits;
        timestamps_s = best_candidate.bit_times_s;

        fprintf('联合搜索最优：bit 偏移 = %d ms，pattern 偏移 = %d bit，极性 = %+d，匹配率 = %.1f%%\n', ...
            best_candidate.bit_offset_ms, best_candidate.pattern_offset, ...
            best_candidate.polarity, best_candidate.match_rate * 100);
        fprintf('比特边界搜索：最佳偏移 = %d ms，相关能量 = %.2e\n', ...
            best_candidate.bit_offset_ms, best_candidate.mean_bit_energy);

        n_diag = min(8, length(best_candidate.corr_all));
        fprintf('--- 诊断（前 %d bit 复数相关）---\n', n_diag);
        fprintf('  |corr|: '); fprintf('%8.1f ', abs(best_candidate.corr_all(1:n_diag))); fprintf('\n');
        fprintf('  相位(°): '); fprintf('%8.1f ', rad2deg(angle(best_candidate.corr_all(1:n_diag)))); fprintf('\n');
        fprintf('细残余频偏估计：Δf_fine = %.3f Hz\n', best_candidate.df_fine_hz);
        fprintf('--- 诊断（前 %d bit 细频补后）---\n', n_diag);
        fprintf('  相位(°): '); fprintf('%8.1f ', rad2deg(angle(best_candidate.corr_all_fcorr(1:n_diag)))); fprintf('\n');
        fprintf('载波相位估计：φ = %.1f°\n', best_candidate.phi_est_deg);

        n_show = min(40, length(bits));
        fprintf('前 %d bit（+1/-1）: ', n_show);
        fprintf('%+d ', bits(1:n_show));
        fprintf('\n');

        recovery_result = struct();
        recovery_result.rx_bits = bits;
        recovery_result.bit_times_s = timestamps_s;
        recovery_result.ref_bits = best_candidate.ref_bits;
        recovery_result.truth_mode = get_field_or(truth, 'truth_mode', 'none');
        recovery_result.bit_offset_ms = best_candidate.bit_offset_ms;
        recovery_result.pattern_offset = best_candidate.pattern_offset;
        recovery_result.polarity = best_candidate.polarity;
        recovery_result.df_pre_hz = df_pre_hz;
        recovery_result.df_fine_hz = best_candidate.df_fine_hz;
        recovery_result.phi_est_deg = best_candidate.phi_est_deg;
        recovery_result.match_rate = best_candidate.match_rate;
        recovery_result.score = best_candidate.score;
        recovery_result.score_components = best_candidate.score_components;
        recovery_result.ambiguity_flag = best_candidate.ambiguity_flag;
        recovery_result.ambiguity_margin = best_candidate.ambiguity_margin;
        recovery_result.phase_cluster_metrics = best_candidate.phase_cluster_metrics;
        recovery_result.search_grid_summary = search_grid_summary;
        recovery_result.diagnostics = struct( ...
            'corr_ms_fcorr', corr_ms_fcorr, ...
            'corr_ms_mag', abs(corr_ms_fcorr), ...
            'corr_ms_phase_deg', rad2deg(angle(corr_ms_fcorr)), ...
            'corr_all', best_candidate.corr_all, ...
            'corr_all_mag', abs(best_candidate.corr_all), ...
            'corr_all_phase_deg', rad2deg(angle(best_candidate.corr_all)), ...
            'corr_all_fcorr', best_candidate.corr_all_fcorr, ...
            'corr_all_fcorr_phase_deg', rad2deg(angle(best_candidate.corr_all_fcorr)), ...
            'corr_rotated', best_candidate.corr_rotated, ...
            'corr_rotated_phase_deg', rad2deg(angle(best_candidate.corr_rotated)));
    else
        [bits, timestamps_s, legacy_result] = legacy_recover_without_truth( ...
            corr_ms_fcorr, base_start, samples_per_ms, fs, epochs_per_bit);
        recovery_result = legacy_result;
        recovery_result.df_pre_hz = df_pre_hz;
        recovery_result.truth_mode = 'none';
    end
end

function [search_grid_summary, best_candidate] = joint_search_with_truth( ...
    corr_ms_fcorr, base_start, samples_per_ms, fs, epochs_per_bit, truth_pattern)

    pattern_len = length(truth_pattern);
    num_ms = length(corr_ms_fcorr);
    bit_offsets = 0:(epochs_per_bit - 1);

    score_by_bit_offset_pattern = -inf(epochs_per_bit, pattern_len);
    match_rate_by_bit_offset_pattern = nan(epochs_per_bit, pattern_len);
    best_polarity_by_bit_offset_pattern = zeros(epochs_per_bit, pattern_len);
    phi_est_deg_by_bit_offset_pattern = nan(epochs_per_bit, pattern_len);
    df_fine_hz_by_bit_offset_pattern = nan(epochs_per_bit, pattern_len);
    mean_bit_energy_by_offset = nan(epochs_per_bit, 1);
    phase_cluster_pre_by_offset = nan(epochs_per_bit, 1);
    phase_cluster_post_by_offset = nan(epochs_per_bit, 1);

    best_candidate = struct('score', -inf);
    top_scores = -inf(2, 1);
    top_matches = -inf(2, 1);

    for bp = bit_offsets
        [corr_all, bit_times_s] = integrate_bit_correlations( ...
            corr_ms_fcorr, base_start, samples_per_ms, fs, epochs_per_bit, bp);
        num_bits = length(corr_all);
        if num_bits < 1
            continue;
        end

        df_fine_hz = estimate_bit_domain_df_hz(corr_all, epochs_per_bit * 1e-3);
        t_bits = (0:num_bits-1)' * (epochs_per_bit * 1e-3);
        corr_all_fcorr = corr_all .* exp(-1j * 2 * pi * df_fine_hz * t_bits);

        mean_bit_energy = mean(abs(corr_all));
        cluster_pre = bpsk_cluster_strength(corr_all);
        cluster_post = bpsk_cluster_strength(corr_all_fcorr);

        mean_bit_energy_by_offset(bp + 1) = mean_bit_energy;
        phase_cluster_pre_by_offset(bp + 1) = cluster_pre;
        phase_cluster_post_by_offset(bp + 1) = cluster_post;

        for pattern_offset = 0:(pattern_len - 1)
            local_best = struct('score', -inf);
            for polarity = [1, -1]
                ref_bits = build_reference_bits(truth_pattern, num_bits, pattern_offset, polarity);
                corr_ref = corr_all_fcorr .* ref_bits;
                phi_est = angle(sum(corr_ref));
                corr_ref_rot = corr_ref .* exp(-1j * phi_est);
                projected = real(corr_ref_rot);

                rx_bits_candidate = sign(real(corr_all_fcorr .* exp(-1j * phi_est)));
                rx_bits_candidate(rx_bits_candidate == 0) = 1;

                match_rate = mean(sign(rx_bits_candidate) == sign(ref_bits));
                projection_margin = mean(projected) / max(mean(abs(corr_all_fcorr)), eps);
                score = 1e6 * match_rate + 1e3 * projection_margin + 10 * cluster_post + 1e-3 * mean_bit_energy;

                if score > local_best.score
                    local_best = struct( ...
                        'score', score, ...
                        'bit_offset_ms', bp, ...
                        'pattern_offset', pattern_offset, ...
                        'polarity', polarity, ...
                        'df_fine_hz', df_fine_hz, ...
                        'phi_est_deg', rad2deg(phi_est), ...
                        'match_rate', match_rate, ...
                        'mean_bit_energy', mean_bit_energy, ...
                        'score_components', struct( ...
                            'match_rate', match_rate, ...
                            'projection_margin', projection_margin, ...
                            'phase_cluster_pre', cluster_pre, ...
                            'phase_cluster_post', cluster_post, ...
                            'mean_bit_energy', mean_bit_energy), ...
                        'phase_cluster_metrics', struct( ...
                            'pre_fine_cluster_strength', cluster_pre, ...
                            'post_fine_cluster_strength', cluster_post), ...
                        'ref_bits', ref_bits, ...
                        'rx_bits', rx_bits_candidate, ...
                        'bit_times_s', bit_times_s, ...
                        'corr_all', corr_all, ...
                        'corr_all_fcorr', corr_all_fcorr, ...
                        'corr_rotated', corr_all_fcorr .* exp(-1j * phi_est));
                end
            end

            score_by_bit_offset_pattern(bp + 1, pattern_offset + 1) = local_best.score;
            match_rate_by_bit_offset_pattern(bp + 1, pattern_offset + 1) = local_best.match_rate;
            best_polarity_by_bit_offset_pattern(bp + 1, pattern_offset + 1) = local_best.polarity;
            phi_est_deg_by_bit_offset_pattern(bp + 1, pattern_offset + 1) = local_best.phi_est_deg;
            df_fine_hz_by_bit_offset_pattern(bp + 1, pattern_offset + 1) = local_best.df_fine_hz;

            if local_best.score > best_candidate.score
                top_scores = update_top_two(top_scores, local_best.score);
                top_matches = update_top_two(top_matches, local_best.match_rate);
                best_candidate = local_best;
            else
                top_scores = update_top_two(top_scores, local_best.score);
                top_matches = update_top_two(top_matches, local_best.match_rate);
            end
        end
    end

    best_candidate.ambiguity_margin = top_scores(1) - top_scores(2);
    best_candidate.ambiguity_flag = (top_matches(1) - top_matches(2) < 0.01) ...
        || (best_candidate.ambiguity_margin < 2e4);

    search_grid_summary = struct();
    search_grid_summary.bit_offsets_ms = bit_offsets(:);
    search_grid_summary.pattern_offsets = (0:pattern_len - 1)';
    search_grid_summary.score_by_bit_offset_pattern = score_by_bit_offset_pattern;
    search_grid_summary.match_rate_by_bit_offset_pattern = match_rate_by_bit_offset_pattern;
    search_grid_summary.best_polarity_by_bit_offset_pattern = best_polarity_by_bit_offset_pattern;
    search_grid_summary.phi_est_deg_by_bit_offset_pattern = phi_est_deg_by_bit_offset_pattern;
    search_grid_summary.df_fine_hz_by_bit_offset_pattern = df_fine_hz_by_bit_offset_pattern;
    search_grid_summary.mean_bit_energy_by_offset = mean_bit_energy_by_offset;
    search_grid_summary.phase_cluster_pre_by_offset = phase_cluster_pre_by_offset;
    search_grid_summary.phase_cluster_post_by_offset = phase_cluster_post_by_offset;
end

function [corr_all, bit_times_s] = integrate_bit_correlations( ...
    corr_ms_fcorr, base_start, samples_per_ms, fs, epochs_per_bit, bit_offset_ms)

    start_ms = bit_offset_ms + 1;
    num_bits = floor((length(corr_ms_fcorr) - bit_offset_ms) / epochs_per_bit);
    corr_all = complex(zeros(num_bits, 1));
    bit_times_s = zeros(num_bits, 1);

    for k = 1:num_bits
        ms_s = start_ms + (k-1) * epochs_per_bit;
        ms_e = ms_s + epochs_per_bit - 1;
        corr_all(k) = sum(corr_ms_fcorr(ms_s:ms_e));
        bit_times_s(k) = ((base_start - 1) + (ms_s - 1) * samples_per_ms) / fs;
    end
end

function df_fine_hz = estimate_bit_domain_df_hz(corr_all, bit_period_s)
    if length(corr_all) < 2
        df_fine_hz = 0;
        return;
    end

    t_bits = (0:length(corr_all)-1)' * bit_period_s;
    phi_sq = unwrap(angle(corr_all.^2));
    fit_coeff = polyfit(t_bits, phi_sq, 1);
    df_fine_hz = fit_coeff(1) / (4 * pi);
end

function cluster_strength = bpsk_cluster_strength(corr_values)
    if isempty(corr_values)
        cluster_strength = 0;
        return;
    end
    cluster_strength = abs(mean(exp(1j * 2 * angle(corr_values))));
end

function ref_bits = build_reference_bits(pattern, num_bits, pattern_offset, polarity)
    pattern = double(pattern(:));
    pattern_cyc = repmat(pattern, ceil(num_bits / length(pattern)) + 1, 1);
    ref_bits = polarity * pattern_cyc(pattern_offset + 1 : pattern_offset + num_bits);
end

function top_two = update_top_two(top_two, candidate_score)
    if candidate_score > top_two(1)
        top_two = [candidate_score; top_two(1)];
    elseif candidate_score > top_two(2)
        top_two(2) = candidate_score;
    end
end

function value = get_field_or(s, field_name, fallback)
    if isstruct(s) && isfield(s, field_name)
        value = s.(field_name);
    else
        value = fallback;
    end
end

function [bits, timestamps_s, recovery_result] = legacy_recover_without_truth( ...
    corr_ms_fcorr, base_start, samples_per_ms, fs, epochs_per_bit)

    best_bit_offset = 0;
    best_energy = -1;
    n_probe = 50;
    for bp = 0:19
        start_ms = bp + 1;
        n_trial = min(n_probe, floor((length(corr_ms_fcorr) - bp) / epochs_per_bit));
        if n_trial < 1
            continue;
        end
        energy = 0;
        for k = 1:n_trial
            ms_s = start_ms + (k-1) * epochs_per_bit;
            ms_e = ms_s + epochs_per_bit - 1;
            energy = energy + abs(sum(corr_ms_fcorr(ms_s:ms_e)));
        end
        if energy > best_energy
            best_energy = energy;
            best_bit_offset = bp;
        end
    end

    [corr_all, timestamps_s] = integrate_bit_correlations( ...
        corr_ms_fcorr, base_start, samples_per_ms, fs, epochs_per_bit, best_bit_offset);
    df_fine_hz = estimate_bit_domain_df_hz(corr_all, epochs_per_bit * 1e-3);
    t_bits = (0:length(corr_all)-1)' * (epochs_per_bit * 1e-3);
    corr_all_fcorr = corr_all .* exp(-1j * 2 * pi * df_fine_hz * t_bits);
    phi_est = angle(sum(corr_all_fcorr.^2)) / 2;
    corr_rotated = corr_all_fcorr .* exp(-1j * phi_est);

    bits = sign(real(corr_rotated));
    bits(bits == 0) = 1;

    recovery_result = struct();
    recovery_result.rx_bits = bits;
    recovery_result.bit_times_s = timestamps_s;
    recovery_result.ref_bits = [];
    recovery_result.bit_offset_ms = best_bit_offset;
    recovery_result.pattern_offset = 0;
    recovery_result.polarity = 1;
    recovery_result.df_fine_hz = df_fine_hz;
    recovery_result.phi_est_deg = rad2deg(phi_est);
    recovery_result.match_rate = nan;
    recovery_result.score = best_energy;
    recovery_result.score_components = struct('match_rate', nan, 'mean_bit_energy', mean(abs(corr_all)));
    recovery_result.ambiguity_flag = false;
    recovery_result.ambiguity_margin = nan;
    recovery_result.phase_cluster_metrics = struct( ...
        'pre_fine_cluster_strength', bpsk_cluster_strength(corr_all), ...
        'post_fine_cluster_strength', bpsk_cluster_strength(corr_all_fcorr));
    recovery_result.search_grid_summary = struct();
    recovery_result.diagnostics = struct( ...
        'corr_ms_fcorr', corr_ms_fcorr, ...
        'corr_all', corr_all, ...
        'corr_all_fcorr', corr_all_fcorr, ...
        'corr_rotated', corr_rotated);
end
