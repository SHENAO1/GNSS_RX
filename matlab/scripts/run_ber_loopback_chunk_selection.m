function selection_result = run_ber_loopback_chunk_selection(capture_group_dir, chunk_selection, options)
%RUN_BER_LOOPBACK_CHUNK_SELECTION Run BER sequentially for selected chunks.
%
%   selection_result = RUN_BER_LOOPBACK_CHUNK_SELECTION(capture_group_dir)
%   selection_result = RUN_BER_LOOPBACK_CHUNK_SELECTION(capture_group_dir, 2:15)
%   selection_result = RUN_BER_LOOPBACK_CHUNK_SELECTION(capture_group_dir, [1 8 15], options)
%
%   This helper is convenient when you want per-chunk BER results in order,
%   instead of only one whole-group aggregate.

if nargin < 1 || strlength(string(capture_group_dir)) == 0
    error('GNSS_RX:MissingChunkGroupDir', ...
        'run_ber_loopback_chunk_selection requires a chunk-group directory.');
end
if nargin < 2
    chunk_selection = [];
end
if nargin < 3 || isempty(options)
    options = struct();
end

matlab_root = fileparts(mfilename('fullpath'));
functions_dir = fullfile(matlab_root, 'functions');
if exist(functions_dir, 'dir') == 7
    addpath(functions_dir);
end

capture_group_dir = char(string(capture_group_dir));
chunk_entries = collect_chunk_entries(capture_group_dir);
if isempty(chunk_entries)
    error('GNSS_RX:NoChunkEntries', ...
        '目录下未找到 chunk0001ofNNNN 这类 capture 文件：%s', capture_group_dir);
end

selected_entries = filter_chunk_entries(chunk_entries, chunk_selection);
[~, capture_group_id] = fileparts(capture_group_dir);

fprintf('=== Chunk BER Sequential ===\n');
fprintf('group dir : %s\n', capture_group_dir);
fprintf('group id  : %s\n', capture_group_id);
fprintf('总 chunk 数      : %d\n', numel(chunk_entries));
fprintf('本次分析序号     : %s\n', format_indices([selected_entries.chunk_index]));

per_chunk = repmat(struct( ...
    'chunk_index', [], ...
    'chunk_count', [], ...
    'capture_path', '', ...
    'success', false, ...
    'errors', NaN, ...
    'total_bits', NaN, ...
    'ber', NaN, ...
    'match_rate', NaN, ...
    'bit_offset_ms', NaN, ...
    'pattern_offset', NaN, ...
    'doppler_hz', NaN, ...
    'acq_peak_ratio', NaN, ...
    'summary_path', '', ...
    'error_message', ''), 0, 1);

aggregate_errors = 0;
aggregate_bits = 0;
successful_chunks = 0;
failed_chunks = {};

for k = 1:numel(selected_entries)
    chunk_entry = selected_entries(k);
    fprintf('\n--- BER chunk %d/%d: %s ---\n', ...
        chunk_entry.chunk_index, chunk_entry.chunk_count, chunk_entry.stem_name);

    chunk_summary = struct( ...
        'chunk_index', chunk_entry.chunk_index, ...
        'chunk_count', chunk_entry.chunk_count, ...
        'capture_path', chunk_entry.stem_path, ...
        'success', false, ...
        'errors', NaN, ...
        'total_bits', NaN, ...
        'ber', NaN, ...
        'match_rate', NaN, ...
        'bit_offset_ms', NaN, ...
        'pattern_offset', NaN, ...
        'doppler_hz', NaN, ...
        'acq_peak_ratio', NaN, ...
        'summary_path', '', ...
        'error_message', '');

    try
        single_result = run_ber_loopback_chunk_group(chunk_entry.stem_path, options);

        chunk_summary.success = true;
        chunk_summary.errors = single_result.aggregate_errors;
        chunk_summary.total_bits = single_result.aggregate_bits;
        chunk_summary.ber = single_result.aggregate_ber;
        chunk_summary.summary_path = single_result.summary_path;

        if ~isempty(single_result.per_chunk)
            chunk_result = single_result.per_chunk(1);
            chunk_summary.match_rate = chunk_result.match_rate;
            chunk_summary.bit_offset_ms = chunk_result.bit_offset_ms;
            chunk_summary.pattern_offset = chunk_result.pattern_offset;
            chunk_summary.doppler_hz = chunk_result.doppler_hz;
            chunk_summary.acq_peak_ratio = chunk_result.acq_peak_ratio;
        end

        aggregate_errors = aggregate_errors + chunk_summary.errors;
        aggregate_bits = aggregate_bits + chunk_summary.total_bits;
        successful_chunks = successful_chunks + 1;

        fprintf('  errors      : %d\n', chunk_summary.errors);
        fprintf('  total_bits  : %d\n', chunk_summary.total_bits);
        fprintf('  ber         : %.6e\n', chunk_summary.ber);
        fprintf('  match_rate  : %.6f\n', chunk_summary.match_rate);
    catch ME
        chunk_summary.error_message = ME.message;
        failed_chunks{end+1, 1} = struct( ... %#ok<AGROW>
            'chunk_index', chunk_entry.chunk_index, ...
            'capture_path', chunk_entry.stem_path, ...
            'message', ME.message);
        warning('Chunk %d BER 失败：%s', chunk_entry.chunk_index, ME.message);
    end

    per_chunk(end+1, 1) = chunk_summary; %#ok<AGROW>
end

aggregate_ber = NaN;
if aggregate_bits > 0
    aggregate_ber = aggregate_errors / aggregate_bits;
end

fprintf('\n=== Selected Chunk BER 汇总 ===\n');
fprintf('成功 chunk 数：%d / %d\n', successful_chunks, numel(selected_entries));
fprintf('累计误码数  ：%d\n', aggregate_errors);
fprintf('累计比特数  ：%d\n', aggregate_bits);
fprintf('汇总 BER    ：%.6e\n', aggregate_ber);
fprintf('失败 chunk 数：%d\n', numel(failed_chunks));

selection_result = struct();
selection_result.capture_group_dir = capture_group_dir;
selection_result.capture_group_id = capture_group_id;
selection_result.chunk_count = numel(chunk_entries);
selection_result.selected_chunk_indices = [selected_entries.chunk_index];
selection_result.successful_chunks = successful_chunks;
selection_result.failed_chunks = failed_chunks;
selection_result.aggregate_errors = aggregate_errors;
selection_result.aggregate_bits = aggregate_bits;
selection_result.aggregate_ber = aggregate_ber;
selection_result.per_chunk = per_chunk;
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
            'chunk_selection 必须是正整数序号，例如 [2 3 4]。');
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


function text = format_indices(indices)
    if isempty(indices)
        text = '(none)';
        return;
    end
    text = strjoin(arrayfun(@num2str, indices, 'UniformOutput', false), ', ');
end
