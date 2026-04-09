function batch_result = run_capture_analysis_chunk_group(capture_input, chunk_selection, cfg)
%RUN_CAPTURE_ANALYSIS_CHUNK_GROUP Run capture analysis over one or many chunked captures.
%
%   batch_result = RUN_CAPTURE_ANALYSIS_CHUNK_GROUP(capture_group_dir)
%   batch_result = RUN_CAPTURE_ANALYSIS_CHUNK_GROUP(capture_group_dir, [1 8 15])
%   batch_result = RUN_CAPTURE_ANALYSIS_CHUNK_GROUP(single_chunk_stem)
%   batch_result = RUN_CAPTURE_ANALYSIS_CHUNK_GROUP(..., cfg)
%
%   The input may be either a chunk-group directory or one chunk stem/.json/.sc16
%   path. When a directory is given, the function discovers all chunked
%   captures, prints the chunk list, and runs run_capture_analysis() on each
%   selected chunk. If chunk_selection is empty or omitted, all chunks are run.

if nargin < 1 || strlength(string(capture_input)) == 0
    error('GNSS_RX:MissingChunkGroupDir', ...
        'run_capture_analysis_chunk_group requires a chunk-group directory or chunk path.');
end
if nargin < 2
    chunk_selection = [];
end
if nargin < 3
    cfg = [];
end
if isstruct(chunk_selection) && isempty(cfg)
    cfg = chunk_selection;
    chunk_selection = [];
end

matlab_root = fileparts(mfilename('fullpath'));
functions_dir = fullfile(matlab_root, 'functions');
if exist(functions_dir, 'dir') == 7
    addpath(functions_dir);
end

capture_input = char(string(capture_input));
[chunk_entries, capture_group_dir, input_mode] = resolve_chunk_entries(capture_input);
selected_entries = filter_chunk_entries(chunk_entries, chunk_selection);
[~, capture_group_id] = fileparts(capture_group_dir);

all_indices = [chunk_entries.chunk_index];
selected_indices = [selected_entries.chunk_index];

fprintf('=== Chunk Capture Analysis ===\n');
fprintf('input    : %s\n', capture_input);
fprintf('mode     : %s\n', input_mode);
fprintf('group dir: %s\n', capture_group_dir);
fprintf('group id : %s\n', capture_group_id);
fprintf('总 chunk 数      : %d\n', numel(chunk_entries));
fprintf('可用 chunk 序号  : %s\n', format_indices(all_indices));
fprintf('本次分析 chunk 数: %d\n', numel(selected_entries));
fprintf('本次分析序号     : %s\n', format_indices(selected_indices));

per_chunk = repmat(struct( ...
    'chunk_index', [], ...
    'chunk_count', [], ...
    'capture_path', '', ...
    'success', false, ...
    'detected', false, ...
    'target_prn', NaN, ...
    'peak_metric', NaN, ...
    'second_peak_ratio', NaN, ...
    'best_doppler_hz', NaN, ...
    'best_code_phase_samples', NaN, ...
    'detected_prns', [], ...
    'analysis_dir', '', ...
    'error_message', ''), 0, 1);

successful_chunks = 0;
failed_chunks = {};

for k = 1:numel(selected_entries)
    chunk_entry = selected_entries(k);
    fprintf('\n--- chunk %d/%d: %s ---\n', ...
        chunk_entry.chunk_index, chunk_entry.chunk_count, chunk_entry.stem_name);

    chunk_summary = struct( ...
        'chunk_index', chunk_entry.chunk_index, ...
        'chunk_count', chunk_entry.chunk_count, ...
        'capture_path', chunk_entry.stem_path, ...
        'success', false, ...
        'detected', false, ...
        'target_prn', NaN, ...
        'peak_metric', NaN, ...
        'second_peak_ratio', NaN, ...
        'best_doppler_hz', NaN, ...
        'best_code_phase_samples', NaN, ...
        'detected_prns', [], ...
        'analysis_dir', '', ...
        'error_message', '');

    try
        if isempty(cfg)
            result = run_capture_analysis(chunk_entry.stem_path);
        else
            result = run_capture_analysis(chunk_entry.stem_path, cfg);
        end

        chunk_summary.success = true;
        chunk_summary.detected = result.acq_result.detected;
        chunk_summary.target_prn = result.acq_result.target_prn;
        chunk_summary.peak_metric = result.acq_result.peak_metric;
        chunk_summary.second_peak_ratio = result.acq_result.second_peak_ratio;
        chunk_summary.best_doppler_hz = result.acq_result.best_doppler_hz;
        chunk_summary.best_code_phase_samples = result.acq_result.best_code_phase_samples;
        if isfield(result, 'survey') && isfield(result.survey, 'prn_list') && isfield(result.survey, 'detected')
            chunk_summary.detected_prns = result.survey.prn_list(result.survey.detected);
        end
        if isfield(result, 'save_info') && isfield(result.save_info, 'analysis_dir')
            chunk_summary.analysis_dir = result.save_info.analysis_dir;
        end

        successful_chunks = successful_chunks + 1;

        fprintf('  捕获结果   : %s\n', ternary_text(chunk_summary.detected, '成功', '失败'));
        fprintf('  目标 PRN   : %d\n', chunk_summary.target_prn);
        fprintf('  峰值指标   : %.3f\n', chunk_summary.peak_metric);
        fprintf('  次峰比     : %.3f\n', chunk_summary.second_peak_ratio);
        fprintf('  最佳多普勒 : %.1f Hz\n', chunk_summary.best_doppler_hz);
        fprintf('  分析输出   : %s\n', chunk_summary.analysis_dir);
    catch ME
        chunk_summary.error_message = ME.message;
        failed_chunks{end+1, 1} = struct( ... %#ok<AGROW>
            'chunk_index', chunk_entry.chunk_index, ...
            'capture_path', chunk_entry.stem_path, ...
            'message', ME.message);
        warning('Chunk %d 分析失败：%s', chunk_entry.chunk_index, ME.message);
    end

    per_chunk(end+1, 1) = chunk_summary; %#ok<AGROW>
end

fprintf('\n=== Chunk Capture Analysis 汇总 ===\n');
fprintf('成功 chunk 数：%d / %d\n', successful_chunks, numel(selected_entries));
fprintf('失败 chunk 数：%d\n', numel(failed_chunks));

batch_result = struct();
batch_result.capture_group_dir = capture_group_dir;
batch_result.capture_group_id = capture_group_id;
batch_result.input_mode = input_mode;
batch_result.chunk_count = numel(chunk_entries);
batch_result.available_chunk_indices = all_indices;
batch_result.selected_chunk_indices = selected_indices;
batch_result.successful_chunks = successful_chunks;
batch_result.failed_chunks = failed_chunks;
batch_result.per_chunk = per_chunk;
end


function filtered_entries = filter_chunk_entries(chunk_entries, chunk_selection)
    if isempty(chunk_selection)
        filtered_entries = chunk_entries;
        return;
    end

    if isstring(chunk_selection) || ischar(chunk_selection)
        selection_text = strtrim(char(string(chunk_selection)));
        if isempty(selection_text) || strcmpi(selection_text, 'all')
            filtered_entries = chunk_entries;
            return;
        end
        requested_tokens = regexp(selection_text, '\d+', 'match');
        requested_indices = str2double(requested_tokens);
    else
        requested_indices = double(chunk_selection(:).');
    end

    if isempty(requested_indices)
        error('GNSS_RX:EmptyChunkSelection', ...
            'chunk_selection 为空，无法确定要分析哪些 chunk。');
    end
    if any(~isfinite(requested_indices)) || any(requested_indices < 1) || ...
            any(abs(requested_indices - round(requested_indices)) > 0)
        error('GNSS_RX:InvalidChunkSelection', ...
            'chunk_selection 必须是正整数序号，例如 [1 8 15]。');
    end

    requested_indices = unique(round(requested_indices), 'stable');
    available_indices = [chunk_entries.chunk_index];
    missing_indices = requested_indices(~ismember(requested_indices, available_indices));
    if ~isempty(missing_indices)
        error('GNSS_RX:ChunkSelectionOutOfRange', ...
            '请求的 chunk 序号不存在：%s；可用序号：%s', ...
            format_indices(missing_indices), format_indices(available_indices));
    end

    filtered_entries = chunk_entries(ismember(available_indices, requested_indices));
end


function chunk_entries = collect_chunk_entries(capture_group_dir)
    listing = dir(fullfile(capture_group_dir, '*_chunk*.json'));
    chunk_entries = repmat(struct( ...
        'stem_name', '', ...
        'stem_path', '', ...
        'chunk_index', [], ...
        'chunk_count', []), 0, 1);

    for k = 1:numel(listing)
        file_name = listing(k).name;
        token = regexp(file_name, '^(.*)_chunk(\d+)of(\d+)\.json$', 'tokens', 'once');
        if isempty(token)
            continue;
        end
        stem_name = sprintf('%s_chunk%sof%s', token{1}, token{2}, token{3});
        chunk_entries(end+1, 1) = struct( ... %#ok<AGROW>
            'stem_name', stem_name, ...
            'stem_path', fullfile(capture_group_dir, stem_name), ...
            'chunk_index', str2double(token{2}), ...
            'chunk_count', str2double(token{3}));
    end

    if isempty(chunk_entries)
        return;
    end

    sort_key = [[chunk_entries.chunk_count].' [chunk_entries.chunk_index].'];
    [~, sort_idx] = sortrows(sort_key, [1 2]);
    chunk_entries = chunk_entries(sort_idx);
end


function [chunk_entries, capture_group_dir, input_mode] = resolve_chunk_entries(capture_input)
    if exist(capture_input, 'dir') == 7
        chunk_entries = collect_chunk_entries(capture_input);
        if isempty(chunk_entries)
            error('GNSS_RX:NoChunkEntries', ...
                '目录下未找到 chunk0001ofNNNN 这类 capture 文件：%s', capture_input);
        end
        capture_group_dir = capture_input;
        input_mode = 'group_dir';
        return;
    end

    chunk_entry = resolve_single_chunk_entry(capture_input);
    chunk_entries = chunk_entry;
    capture_group_dir = fileparts(chunk_entry.stem_path);
    input_mode = 'single_chunk';
end


function chunk_entry = resolve_single_chunk_entry(capture_input)
    input_str = char(string(capture_input));
    [folder, name, ext] = fileparts(input_str);
    if strcmpi(ext, '.json') || strcmpi(ext, '.sc16')
        stem_name = name;
        stem_path = fullfile(folder, name);
    else
        stem_name = name;
        stem_path = input_str;
    end

    token = regexp(stem_name, '^(.*)_chunk(\d+)of(\d+)$', 'tokens', 'once');
    if isempty(token)
        error('GNSS_RX:InvalidChunkStem', ...
            '输入不是 chunked capture stem/.json/.sc16：%s', input_str);
    end

    chunk_entry = struct( ...
        'stem_name', stem_name, ...
        'stem_path', stem_path, ...
        'chunk_index', str2double(token{2}), ...
        'chunk_count', str2double(token{3}));
end


function text = format_indices(indices)
    if isempty(indices)
        text = '(none)';
        return;
    end
    text = strjoin(arrayfun(@num2str, indices, 'UniformOutput', false), ', ');
end


function out = ternary_text(condition, true_text, false_text)
    if condition
        out = true_text;
    else
        out = false_text;
    end
end
