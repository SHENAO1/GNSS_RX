function stem_path = find_latest_capture(root_dir)
%FIND_LATEST_CAPTURE 返回共享目录下最新的一组有效采集 stem。

if nargin < 1 || strlength(string(root_dir)) == 0
    root_dir = gnss_rx_resolve_data_dir();
end

root_dir = char(string(root_dir));
if exist(root_dir, 'dir') ~= 7
    error('GNSS_RX:CaptureRootMissing', 'Capture root does not exist: %s', root_dir);
end

listing = dir(fullfile(root_dir, '**', '*.json'));
listing = listing(~[listing.isdir]);

valid = false(size(listing));
for idx = 1:numel(listing)
    folder = listing(idx).folder;
    % analysis/ 目录里存的是后处理结果，不应被当成原始采集输入。
    if contains(folder, [filesep 'analysis'])
        continue;
    end
    json_path = fullfile(listing(idx).folder, listing(idx).name);
    stem_name = erase(listing(idx).name, '.json');
    sc16_path = fullfile(listing(idx).folder, [stem_name '.sc16']);
    if isfile(sc16_path)
        valid(idx) = true;
    end
end

listing = listing(valid);
if isempty(listing)
    error('GNSS_RX:NoCaptureFound', ...
        'No paired .sc16 + .json capture files were found under %s', root_dir);
end

% 以 JSON 文件时间为准选最新 stem；由于要求成对存在，因此同名 .sc16 一定可用。
[~, latest_idx] = max([listing.datenum]);
latest = listing(latest_idx);
latest_stem = erase(latest.name, '.json');
stem_path = fullfile(latest.folder, latest_stem);
end
