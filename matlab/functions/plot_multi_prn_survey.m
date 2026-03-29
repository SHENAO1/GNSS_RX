function fig = plot_multi_prn_survey(survey, paths, cfg)
%PLOT_MULTI_PRN_SURVEY 绘制多星捕获对比柱状图。
%
%   柱状图直观地展示了对 PRN1~32 进行搜索的结论：
%     - X 轴：PRN 编号（每颗卫星的唯一标识码）
%     - Y 轴：次峰比（主峰功率 / 次峰功率），次峰比越高说明信号峰越突出
%     - 红色虚线：判决门限，超过门限的 PRN 被判定为捕获成功
%     - 绿色柱：捕获成功的 PRN；蓝色柱：未捕获的 PRN
%
%   输入：
%     survey  —— run_multi_prn_survey 的返回值
%     paths   —— load_gnss_rx_capture 的 paths 结构体（用于图标题），可省略
%     cfg     —— 可选配置（目前仅支持 cfg.figure_visibility）
%
%   这张图特别适合做“信号来源解释”：
%   如果某个 PRN 的柱子显著高于门限，而其他 PRN 接近噪底，
%   那么就可以很直观地说明当前采集最像哪颗卫星。

if nargin < 2
    paths = struct('stem_name', '');
end
if nargin < 3
    cfg = struct();
end
if ~isfield(cfg, 'figure_visibility') || isempty(cfg.figure_visibility)
    cfg.figure_visibility = 'on';
end

prn_list  = survey.prn_list;
ratio     = survey.second_peak_ratio;
detected  = survey.detected;
threshold = survey.detection_threshold;

% 将 inf（无次峰情况）截断为有限显示值，避免图形坐标轴被拉到无穷大。
% 截断值 = 门限的 4 倍，足以在视觉上区分"远超门限"和"恰好超门限"两种情况。
ratio_display = min(ratio, threshold * 4);

fig = figure('Visible', cfg.figure_visibility, 'Position', [100, 100, 900, 420]);

% 为每根柱分配颜色：捕获成功 → 绿色，未捕获 → 蓝色。
% repmat 把单行颜色向量扩展成 n_prn 行的颜色矩阵。
colors = repmat([0.27, 0.52, 0.79], numel(prn_list), 1);             % 默认：蓝色
colors(detected, :) = repmat([0.18, 0.63, 0.34], sum(detected), 1); % 成功：绿色

% 逐柱绘制（不能用 bar(prn_list, ...) 一次画完，因为那样无法实现分色）。
hold on;
for k = 1:numel(prn_list)
    bar(prn_list(k), ratio_display(k), 0.6, ...
        'FaceColor', colors(k, :), 'EdgeColor', 'none');
end

% 绘制判决门限水平虚线（红色），超过该线即判为捕获成功。
yline(threshold, 'r--', 'LineWidth', 1.5, ...
    'Label', sprintf('门限 %.1f', threshold), ...
    'LabelHorizontalAlignment', 'right', 'FontSize', 9);

% 对捕获成功的 PRN，在柱顶标注次峰比数值（显示原始值而非截断后的值）。
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
ylabel('次峰比（主峰 / 次峰）', 'FontSize', 11);

% 从 paths 中读取 stem_name 用于副标题（若未提供 paths 则为空字符串）。
stem_name = '';
if isstruct(paths) && isfield(paths, 'stem_name')
    stem_name = paths.stem_name;
end

% 根据捕获结果动态生成标题字符串。
n_detected = sum(detected);
if n_detected > 0
    detected_prns = prn_list(detected);
    prn_str       = strjoin(arrayfun(@(x) num2str(x), detected_prns, 'UniformOutput', false), ', ');
    title_str     = sprintf('多星捕获结果：PRN %s 捕获成功（共 %d/%d）', ...
        prn_str, n_detected, numel(prn_list));
else
    title_str = sprintf('多星捕获结果：全部 %d 颗星未捕获', numel(prn_list));
end

if ~isempty(stem_name)
    title({title_str, stem_name}, 'FontSize', 10, 'Interpreter', 'none');
else
    title(title_str, 'FontSize', 10);
end

% 坐标轴范围：X 轴两侧留出空白；Y 轴保证门限线和最高柱都在视野内。
xlim([min(prn_list) - 0.8,  max(prn_list) + 0.8]);
ylim([0, max(max(ratio_display) * 1.2, threshold * 1.5)]);
xticks(prn_list);
end
