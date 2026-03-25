function stem_path = find_latest_capture(root_dir)
%FIND_LATEST_CAPTURE 在指定根目录下查找最新的一组完整 GNSS 采集文件，返回其 stem 路径。
%
%   "stem 路径"是指不带文件扩展名的完整路径，例如：
%       /data/GNSS_RX_Data/capture_20260325_120000
%
%   一组完整的采集必须同时包含两个文件：
%       .json  —— 元数据文件（记录采样率、中心频率等参数）
%       .sc16  —— IQ 原始数据文件（存储实际接收到的信号样本）
%
%   用法：
%       stem = find_latest_capture()               % 自动使用默认数据目录
%       stem = find_latest_capture('/path/to/dir') % 指定数据根目录

% 如果调用时没有传入目录参数，或者传入的是空字符串，就自动解析默认数据目录。
if nargin < 1 || strlength(string(root_dir)) == 0
    root_dir = gnss_rx_resolve_data_dir();
end

% 统一转换为 char 类型，确保后续 MATLAB 文件操作函数（如 dir、exist）可以正常使用。
root_dir = char(string(root_dir));

% 检查目录是否真实存在；如果不存在，立刻报错并给出清晰的提示，
% 避免后续产生"找不到文件"等让人困惑的错误信息。
if exist(root_dir, 'dir') ~= 7
    error('GNSS_RX:CaptureRootMissing', ...
        '采集根目录不存在，请检查路径是否正确：\n  %s', root_dir);
end

% 在根目录下递归搜索所有 .json 文件。
% "**" 表示递归进入所有子目录，因此不管采集文件放在几层子目录里都能找到。
listing = dir(fullfile(root_dir, '**', '*.json'));
% 过滤掉目录条目，只保留真正的文件。
listing = listing(~[listing.isdir]);

% 逐一检查每个 .json 文件，判断它是否有配对的 .sc16 文件。
% valid 是一个和 listing 等长的逻辑数组：true 表示该条目有完整配对。
valid = false(size(listing));
for idx = 1:numel(listing)
    folder = listing(idx).folder;

    % 跳过 analysis/ 子目录——那里存放的是 MATLAB 后处理产物（图片、摘要 JSON 等），
    % 不是原始采集数据，不能被误认为输入来源。
    if contains(folder, [filesep 'analysis'])
        continue;
    end

    % 用 fileparts 从文件名中提取 stem（去掉 .json 扩展名），
    % 再拼出同名 .sc16 文件的完整路径，检查该文件是否存在。
    [~, stem_name, ~] = fileparts(listing(idx).name);
    sc16_path = fullfile(folder, [stem_name '.sc16']);
    if isfile(sc16_path)
        valid(idx) = true;
    end
end

% 过滤后若列表为空，说明目录下没有完整的采集文件对，直接报错。
listing = listing(valid);
if isempty(listing)
    error('GNSS_RX:NoCaptureFound', ...
        '在以下目录下未找到完整的 .sc16 + .json 采集文件对：\n  %s', root_dir);
end

% 以 .json 文件的修改时间（datenum 是 MATLAB 内部时间戳格式）为准，选出最新的那组。
% 因为已确认 .sc16 配对存在，所以最新 .json 对应的 .sc16 也一定可用。
[~, latest_idx] = max([listing.datenum]);
latest = listing(latest_idx);
[~, latest_stem, ~] = fileparts(latest.name);
stem_path = fullfile(latest.folder, latest_stem);
end
