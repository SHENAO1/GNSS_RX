function plot_ber_loopback(analysis_result)
% PLOT_BER_LOOPBACK 绘制 open-loop 与 tracked BER 对照及 tracking 稳定性图。
%
% 这张总览图的目标不是只给出“一个 BER 数字”，而是帮助回答更关键的问题：
%   - 错误是均匀分布，还是集中在某些时间段？
%   - tracking 是一直稳定，还是中途发生了失锁/重同步？
%   - open-loop 和 tracked 对同一段数据的判断是否一致？
%
% 因此图中同时放了 bit 对照、误码时间分布、滑窗 BER、码相位/频率轨迹、
% 相位误差以及结构化摘要，方便调试时一眼定位问题层级。

    % 从统一分析结果中拆出各个子模块输出，便于后续按图块分别使用。
    truth = analysis_result.truth;
    acq_result = analysis_result.acq_result;
    acq_peak_ratio = analysis_result.acq_peak_ratio;
    open_loop_result = analysis_result.open_loop_result;
    tracked_result = analysis_result.tracked_result;
    selected_result = analysis_result.selected_result;
    ber = analysis_result.ber;

    % 使用 3x2 的总览布局，把比特对照、误码分布、局部 BER 和锁定状态放在同一窗口中。
    fig = figure('Name', 'BER Loopback 分析', 'NumberTitle', 'off', ...
                 'Position', [60 40 1500 1050]);
    tl = tiledlayout(fig, 3, 2, 'Padding', 'compact', 'TileSpacing', 'compact');

    %% 图 1：tracked 比特对照
    ax1 = nexttile(tl, 1);
    % 只展示前 200 bit，避免长序列把局部错误和对齐关系压缩得难以观察。
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
    % 误码时间轴直接从完整 tracked 比特序列中提取，便于观察错误是否成簇出现。
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
    % open-loop 结果可能已经携带滑窗 BER，也可能需要从原始比特重算，这里统一做兼容。
    open_loop_window = compute_window_curve(open_loop_result);
    tracked_window = tracked_result.window_ber;
    hold(ax3, 'on');
    if ~isempty(open_loop_window.time_s)
        plot(ax3, open_loop_window.time_s, open_loop_window.ber * 100, ...
            'Color', [0.85 0.33 0.10], 'LineWidth', 1.1, 'DisplayName', 'open-loop');
    end
    % 有效窗口表示当前锁定质量正常，可用于估计“可信”的 tracked BER。
    if isfield(tracked_window, 'valid')
        valid_mask = logical(tracked_window.valid);
    else
        valid_mask = true(size(tracked_window.time_s));
    end
    plot(ax3, tracked_window.time_s(valid_mask), tracked_window.ber(valid_mask) * 100, ...
        'Color', [0.00 0.45 0.74], 'LineWidth', 1.3, 'DisplayName', 'tracked');
    % 无效窗口一般来自 overflow、短时失锁或重同步扰动，单独标出以免误读成稳定 BER。
    if any(~valid_mask)
        plot(ax3, tracked_window.time_s(~valid_mask), tracked_window.ber(~valid_mask) * 100, ...
            'r.', 'MarkerSize', 8, 'DisplayName', '失锁污染');
    end
    % 仅使用有效窗口计算代表性 BER，让图上的均值线更接近稳定锁定后的真实表现。
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
    % lock_metrics 以毫秒为步长记录，因此这里直接构造秒级时间轴用于与 BER 图对照。
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
    % 同时叠加 PLL 相位与相位误差，用来区分“相位在转”与“环路已经偏离”的情况。
    plot(ax5, ms_time, tracked_result.lock_metrics.pll_phase_deg, ...
        'Color', [0.49 0.18 0.56], 'LineWidth', 1.0, 'DisplayName', 'PLL 相位');
    plot(ax5, ms_time, tracked_result.lock_metrics.phase_error_deg, ...
        'Color', [0.93 0.69 0.13], 'LineWidth', 1.0, 'DisplayName', '相位误差');
    reacq_time_s = [];
    for k = 1:numel(tracked_result.reacq_events)
        % reacq_events 记录的是毫秒索引，这里转换成秒并画成竖线标记局部重同步时刻。
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
    % window_match_rate 中可能混有 NaN（例如无效窗口），先剔除再计算更稳健的中位数。
    valid_lock = tracked_result.lock_metrics.window_match_rate(~isnan(tracked_result.lock_metrics.window_match_rate));
    if isempty(valid_lock)
        lock_median = NaN;
    else
        lock_median = median(valid_lock);
    end

    % 把关键判据压缩成文本摘要，便于截图或批量扫结果时快速定位异常项。
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
    % 如果上游已经给出了窗口 BER，则直接复用，避免重复计算。
    % 否则就在本地临时生成一条滑窗 BER 曲线，供对照图使用。
    if isfield(result, 'window_ber') && isstruct(result.window_ber)
        window_curve = result.window_ber;
        return;
    end

    rx_bits = result.rx_bits;
    ref_bits = result.ref_bits;
    bit_times = result.bit_times_s;
    n_bits = length(rx_bits);
    % 默认窗口大小取“最多 100 bit，且不超过总长度的 1/5”，兼顾平滑度和时间分辨率。
    win_bits = min(100, floor(n_bits / 5));
    % 使用重叠滑窗，步长约为窗口的 1/4，这样曲线更平滑，也更容易看出 BER 变化趋势。
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
