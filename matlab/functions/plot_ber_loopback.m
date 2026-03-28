function plot_ber_loopback(analysis_result)
% PLOT_BER_LOOPBACK 绘制 open-loop 与 tracked BER 对照及 tracking 稳定性图。

    truth = analysis_result.truth;
    acq_result = analysis_result.acq_result;
    acq_peak_ratio = analysis_result.acq_peak_ratio;
    open_loop_result = analysis_result.open_loop_result;
    tracked_result = analysis_result.tracked_result;
    selected_result = analysis_result.selected_result;
    ber = analysis_result.ber;

    fig = figure('Name', 'BER Loopback 分析', 'NumberTitle', 'off', ...
                 'Position', [60 40 1500 1050]);
    tl = tiledlayout(fig, 3, 2, 'Padding', 'compact', 'TileSpacing', 'compact');

    %% 图 1：tracked 比特对照
    ax1 = nexttile(tl, 1);
    n_show = min(200, length(tracked_result.rx_bits));
    t_show = tracked_result.bit_times_s(1:n_show);
    err_mask = sign(tracked_result.rx_bits(1:n_show)) ~= sign(tracked_result.ref_bits(1:n_show));
    hold(ax1, 'on');
    stairs(ax1, t_show, tracked_result.ref_bits(1:n_show) * 1.05, 'b-', 'LineWidth', 1.1, ...
        'DisplayName', 'TX（truth）');
    stairs(ax1, t_show, tracked_result.rx_bits(1:n_show) * 0.95, 'r--', 'LineWidth', 1.0, ...
        'DisplayName', 'RX（tracked）');
    if any(err_mask)
        plot(ax1, t_show(err_mask), zeros(sum(err_mask), 1), 'kx', ...
            'MarkerSize', 7, 'LineWidth', 1.4, 'DisplayName', '误码');
    end
    hold(ax1, 'off');
    ylim(ax1, [-1.5 1.5]);
    xlabel(ax1, '时间 (s)');
    ylabel(ax1, '比特值');
    title(ax1, sprintf('Tracked TX vs RX（前 %d bit）', n_show));
    legend(ax1, 'Location', 'best');
    grid(ax1, 'on');

    %% 图 2：tracked 误码位置
    ax2 = nexttile(tl, 2);
    err_times = tracked_result.bit_times_s(sign(tracked_result.rx_bits) ~= sign(tracked_result.ref_bits));
    if ~isempty(err_times)
        stem(ax2, err_times, ones(size(err_times)), 'r', 'Marker', 'none', 'LineWidth', 0.8);
    else
        text(ax2, 0.5, 0.5, '无误码', 'Units', 'normalized', ...
            'HorizontalAlignment', 'center', 'FontSize', 14);
    end
    xlabel(ax2, '时间 (s)');
    ylabel(ax2, '误码');
    title(ax2, sprintf('Tracked 误码位置（总误码 %d / %d bit）', ...
        sum(sign(tracked_result.rx_bits) ~= sign(tracked_result.ref_bits)), ...
        length(tracked_result.rx_bits)));
    xlim(ax2, [tracked_result.bit_times_s(1), tracked_result.bit_times_s(end)]);
    ylim(ax2, [0 1.5]);
    grid(ax2, 'on');

    %% 图 3：局部 BER 对比
    ax3 = nexttile(tl, 3);
    open_loop_window = compute_window_curve(open_loop_result);
    tracked_window = tracked_result.window_ber;
    hold(ax3, 'on');
    if ~isempty(open_loop_window.time_s)
        plot(ax3, open_loop_window.time_s, open_loop_window.ber * 100, ...
            'Color', [0.85 0.33 0.10], 'LineWidth', 1.1, 'DisplayName', 'open-loop');
    end
    % 有效窗口（锁定质量正常）
    if isfield(tracked_window, 'valid')
        valid_mask = logical(tracked_window.valid);
    else
        valid_mask = true(size(tracked_window.time_s));
    end
    plot(ax3, tracked_window.time_s(valid_mask), tracked_window.ber(valid_mask) * 100, ...
        'Color', [0.00 0.45 0.74], 'LineWidth', 1.3, 'DisplayName', 'tracked');
    % 无效窗口（受 overflow/失锁污染）用红色标注
    if any(~valid_mask)
        plot(ax3, tracked_window.time_s(~valid_mask), tracked_window.ber(~valid_mask) * 100, ...
            'r.', 'MarkerSize', 8, 'DisplayName', '失锁污染');
    end
    % 仅用有效窗口计算有效 BER
    if any(valid_mask)
        valid_ber = mean(tracked_window.ber(valid_mask));
        yline(ax3, valid_ber * 100, 'b--', sprintf('有效段 BER=%.2f%%', valid_ber * 100), 'LineWidth', 1.0);
    end
    yline(ax3, ber * 100, 'k--', sprintf('全段 BER=%.2f%%', ber * 100), 'LineWidth', 1.1);
    hold(ax3, 'off');
    xlabel(ax3, '时间 (s)');
    ylabel(ax3, '局部 BER (%)');
    title(ax3, '局部 BER：open-loop vs tracked');
    grid(ax3, 'on');

    %% 图 4：tracking 状态
    ax4 = nexttile(tl, 4);
    ms_time = (0:length(tracked_result.lock_metrics.code_phase_samples)-1)' * 1e-3;
    yyaxis(ax4, 'left');
    plot(ax4, ms_time, tracked_result.lock_metrics.code_phase_samples - tracked_result.lock_metrics.code_phase_samples(1), ...
        'Color', [0.00 0.45 0.74], 'LineWidth', 1.0, 'DisplayName', '码相位漂移');
    ylabel(ax4, '码相位漂移 (samples)');
    yyaxis(ax4, 'right');
    plot(ax4, ms_time, tracked_result.lock_metrics.fll_freq_hz, ...
        'Color', [0.47 0.67 0.19], 'LineWidth', 1.0, 'DisplayName', 'FLL 频率');
    ylabel(ax4, '频率估计 (Hz)');
    xlabel(ax4, '时间 (s)');
    title(ax4, 'Tracking 状态：码相位漂移 + 频率估计');
    grid(ax4, 'on');

    %% 图 5：相位误差与局部重同步
    ax5 = nexttile(tl, 5);
    hold(ax5, 'on');
    plot(ax5, ms_time, tracked_result.lock_metrics.pll_phase_deg, ...
        'Color', [0.49 0.18 0.56], 'LineWidth', 1.0, 'DisplayName', 'PLL 相位');
    plot(ax5, ms_time, tracked_result.lock_metrics.phase_error_deg, ...
        'Color', [0.93 0.69 0.13], 'LineWidth', 1.0, 'DisplayName', '相位误差');
    reacq_time_s = [];
    for k = 1:numel(tracked_result.reacq_events)
        reacq_time_s(end+1, 1) = tracked_result.reacq_events(k).ms_index * 1e-3; %#ok<AGROW>
    end
    if ~isempty(reacq_time_s)
        xline(ax5, reacq_time_s, ':', 'Color', [0.85 0.33 0.10], 'LineWidth', 0.8);
    end
    hold(ax5, 'off');
    xlabel(ax5, '时间 (s)');
    ylabel(ax5, '角度 (°)');
    title(ax5, '载波相位与重同步事件');
    legend(ax5, 'Location', 'best');
    grid(ax5, 'on');

    %% 图 6：结构化摘要
    ax6 = nexttile(tl, 6);
    axis(ax6, 'off');
    valid_lock = tracked_result.lock_metrics.window_match_rate(~isnan(tracked_result.lock_metrics.window_match_rate));
    if isempty(valid_lock)
        lock_median = NaN;
    else
        lock_median = median(valid_lock);
    end

    summary_lines = {
        sprintf('ber_mode: %s', analysis_result.ber_mode)
        sprintf('truth_mode: %s', truth.truth_mode)
        sprintf('open_loop_match: %.1f%%', open_loop_result.match_rate * 100)
        sprintf('tracked_match: %.1f%%', tracked_result.match_rate * 100)
        sprintf('selected_ber: %.2e', ber)
        sprintf('tracked bit_offset_ms: %d', tracked_result.bit_offset_ms)
        sprintf('tracked pattern_offset: %d', tracked_result.pattern_offset)
        sprintf('tracked polarity: %+d', tracked_result.polarity)
        sprintf('open_loop ambiguity: %d', open_loop_result.ambiguity_flag)
        sprintf('tracked ambiguity: %d', tracked_result.ambiguity_flag)
        sprintf('tracked reacq_events: %d', numel(tracked_result.reacq_events))
        sprintf('cluster prompt/fll/pll/bit: %.3f / %.3f / %.3f / %.3f', ...
            tracked_result.phase_cluster_metrics.pre_fll_cluster_strength, ...
            tracked_result.phase_cluster_metrics.post_fll_cluster_strength, ...
            tracked_result.phase_cluster_metrics.post_pll_cluster_strength, ...
            tracked_result.phase_cluster_metrics.bit_corr_cluster_strength)
        sprintf('selected lock metric median: %.3f', lock_median)
        };
    text(ax6, 0.0, 1.0, strjoin(summary_lines, newline), ...
        'Units', 'normalized', 'VerticalAlignment', 'top', ...
        'FontName', 'Consolas', 'FontSize', 10);

    sgtitle(fig, sprintf( ...
        'BER 闭环分析 | mode=%s | truth=%s | BER=%.2e | Doppler=%.1f Hz | 次峰比=%.2f', ...
        analysis_result.ber_mode, truth.truth_mode, ber, ...
        acq_result.best_doppler_hz, acq_peak_ratio), ...
        'FontSize', 12, 'FontWeight', 'bold');
end

function window_curve = compute_window_curve(result)
    if isfield(result, 'window_ber') && isstruct(result.window_ber)
        window_curve = result.window_ber;
        return;
    end

    rx_bits = result.rx_bits;
    ref_bits = result.ref_bits;
    bit_times = result.bit_times_s;
    n_bits = length(rx_bits);
    win_bits = min(100, floor(n_bits / 5));
    step = max(1, floor(win_bits / 4));
    centers = [];
    ber_values = [];
    for i = 1:step:(n_bits - win_bits + 1)
        i_end = i + win_bits - 1;
        centers(end+1, 1) = bit_times(round((i + i_end) / 2)); %#ok<AGROW>
        ber_values(end+1, 1) = mean(sign(rx_bits(i:i_end)) ~= sign(ref_bits(i:i_end))); %#ok<AGROW>
    end
    window_curve = struct('time_s', centers, 'ber', ber_values);
end
