function fig = plot_multi_prn_survey(survey, paths, cfg)
%PLOT_MULTI_PRN_SURVEY 绘制多星捕获对比柱状图。
%
%   fig = plot_multi_prn_survey(survey, paths, cfg)
%
%   X 轴：PRN 编号
%   Y 轴：次峰比（second_peak_ratio），超过阈值线说明捕获成功
%   绿色柱：捕获成功的 PRN；蓝色柱：未捕获；红色虚线：判决门限
%
%   输入：
%     survey  - run_multi_prn_survey 的返回值
%     paths   - load_gnss_rx_capture 的 paths 结构体（用于图标题）
%     cfg     - 可选配置（目前仅用 cfg.figure_visibility）

if nargin < 2
    paths = struct('stem_name', '');
end
if nargin < 3
    cfg = struct();
end
if ~isfield(cfg, 'figure_visibility') || isempty(cfg.figure_visibility)
    cfg.figure_visibility = 'on';
end

prn_list   = survey.prn_list;
ratio      = survey.second_peak_ratio;
detected   = survey.detected;
threshold  = survey.detection_threshold;

% 将 inf 截断为有限显示值（对应无次峰的纯噪声情况）
ratio_display = min(ratio, threshold * 4);

fig = figure('Visible', cfg.figure_visibility, 'Position', [100, 100, 900, 420]);

% 按捕获状态分配颜色：成功=绿，失败=蓝
colors = repmat([0.27, 0.52, 0.79], numel(prn_list), 1);   % 默认蓝色
colors(detected, :) = repmat([0.18, 0.63, 0.34], sum(detected), 1);  % 成功绿色

% 逐柱绘制以实现分色
hold on;
for k = 1:numel(prn_list)
    bar(prn_list(k), ratio_display(k), 0.6, 'FaceColor', colors(k, :), 'EdgeColor', 'none');
end

% 判决阈值线
yline(threshold, 'r--', 'LineWidth', 1.5, ...
    'Label', sprintf('门限 %.1f', threshold), ...
    'LabelHorizontalAlignment', 'right', 'FontSize', 9);

% 对捕获成功的 PRN 标注数值
for k = 1:numel(prn_list)
    if detected(k)
        text(prn_list(k), ratio_display(k) + 0.1, ...
            sprintf('%.1f', ratio(k)), ...
            'HorizontalAlignment', 'center', 'FontSize', 8, ...
            'Color', [0.1, 0.4, 0.2], 'FontWeight', 'bold');
    end
end

hold off;
grid on;
box on;

xlabel('PRN 编号', 'FontSize', 11);
ylabel('次峰比（peak / second\_peak）', 'FontSize', 11);

stem_name = '';
if isstruct(paths) && isfield(paths, 'stem_name')
    stem_name = paths.stem_name;
end

n_detected = sum(detected);
if n_detected > 0
    detected_prns = prn_list(detected);
    prn_str = strjoin(arrayfun(@(x) num2str(x), detected_prns, 'UniformOutput', false), ', ');
    title_str = sprintf('多星捕获结果：PRN %s 捕获成功（共 %d/%d）', ...
        prn_str, n_detected, numel(prn_list));
else
    title_str = sprintf('多星捕获结果：全部 %d 颗星未捕获', numel(prn_list));
end

if ~isempty(stem_name)
    title({title_str, stem_name}, 'FontSize', 10, 'Interpreter', 'none');
else
    title(title_str, 'FontSize', 10);
end

xlim([min(prn_list) - 0.8, max(prn_list) + 0.8]);
ylim([0, max(max(ratio_display) * 1.2, threshold * 1.5)]);
xticks(prn_list);
end
