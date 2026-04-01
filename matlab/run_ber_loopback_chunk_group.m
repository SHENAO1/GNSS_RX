function batch_result = run_ber_loopback_chunk_group(capture_input, options)
%RUN_BER_LOOPBACK_CHUNK_GROUP Batch BER analysis over one or many chunked captures.
%
%   batch_result = RUN_BER_LOOPBACK_CHUNK_GROUP(capture_group_dir)
%   batch_result = RUN_BER_LOOPBACK_CHUNK_GROUP(single_chunk_stem)
%   batch_result = RUN_BER_LOOPBACK_CHUNK_GROUP(..., options)
%
%   The input may be either a chunk-group directory or one chunk stem/.json/.sc16
%   path. The function then runs BER on every discovered chunk stem and aggregates
%   total errors and total bits.

if nargin < 1 || strlength(string(capture_input)) == 0
    error('GNSS_RX:MissingChunkGroupDir', ...
        'run_ber_loopback_chunk_group requires a chunk-group directory or chunk path.');
end
if nargin < 2 || isempty(options)
    options = struct();
end

matlab_root = fileparts(mfilename('fullpath'));
functions_dir = fullfile(matlab_root, 'functions');
if exist(functions_dir, 'dir') == 7
    addpath(functions_dir);
end

options = apply_default_options(options, matlab_root);
capture_input = char(string(capture_input));
[chunk_entries, capture_group_dir, input_mode] = resolve_chunk_entries(capture_input);
[~, capture_group_id] = fileparts(capture_group_dir);
fprintf('=== Chunk Group BER 汇总 ===\n');
fprintf('input    : %s\n', capture_input);
fprintf('mode     : %s\n', input_mode);
fprintf('group dir: %s\n', capture_group_dir);
fprintf('group id : %s\n', capture_group_id);
fprintf('chunk 数 : %d\n', numel(chunk_entries));

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
    'error_message', ''), 0, 1);

aggregate_errors = 0;
aggregate_bits = 0;
successful_chunks = 0;
failed_chunks = {};

core_options = struct();
core_options.ber_mode = options.ber_mode;
core_options.tx_truth_path = options.tx_truth_path;
core_options.tracking_options = options.tracking_options;
core_options.accel_options = options.accel_options;
core_options.workspace_tx_truth_fallback_path = options.workspace_tx_truth_fallback_path;
core_options.plot_results = options.plot_each_chunk;
core_options.prompt_save = options.prompt_save_each_chunk;
core_options.save_choice = options.save_choice_each_chunk;

for k = 1:numel(chunk_entries)
    chunk_entry = chunk_entries(k);
    fprintf('\n--- chunk %d/%d: %s ---\n', ...
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
        'error_message', '');

    try
        chunk_result = run_ber_loopback_capture(chunk_entry.stem_path, core_options);
        chunk_summary.success = true;
        chunk_summary.errors = chunk_result.errors;
        chunk_summary.total_bits = chunk_result.total_bits;
        chunk_summary.ber = chunk_result.ber;
        chunk_summary.match_rate = chunk_result.selected_result.match_rate;
        chunk_summary.bit_offset_ms = chunk_result.selected_result.bit_offset_ms;
        chunk_summary.pattern_offset = chunk_result.selected_result.pattern_offset;
        chunk_summary.doppler_hz = chunk_result.acq_result.best_doppler_hz;
        chunk_summary.acq_peak_ratio = chunk_result.acq_peak_ratio;

        aggregate_errors = aggregate_errors + chunk_result.errors;
        aggregate_bits = aggregate_bits + chunk_result.total_bits;
        successful_chunks = successful_chunks + 1;
    catch ME
        chunk_summary.error_message = ME.message;
        failed_chunks{end+1, 1} = struct( ... %#ok<AGROW>
            'chunk_index', chunk_entry.chunk_index, ...
            'capture_path', chunk_entry.stem_path, ...
            'message', ME.message);
        warning('Chunk %d 失败：%s', chunk_entry.chunk_index, ME.message);
        if ~options.continue_on_error
            per_chunk(end+1, 1) = chunk_summary; %#ok<AGROW>
            rethrow(ME);
        end
    end

    per_chunk(end+1, 1) = chunk_summary; %#ok<AGROW>
end

aggregate_ber = NaN;
if aggregate_bits > 0
    aggregate_ber = aggregate_errors / aggregate_bits;
end

fprintf('\n=== Chunk Group 汇总结果 ===\n');
fprintf('成功 chunk 数：%d / %d\n', successful_chunks, numel(chunk_entries));
fprintf('累计误码数  ：%d\n', aggregate_errors);
fprintf('累计比特数  ：%d\n', aggregate_bits);
fprintf('汇总 BER    ：%.2e\n', aggregate_ber);
if ~isempty(failed_chunks)
    fprintf('失败 chunk 数：%d\n', numel(failed_chunks));
end

batch_result = struct();
batch_result.capture_group_dir = capture_group_dir;
batch_result.capture_group_id = capture_group_id;
batch_result.input_mode = input_mode;
batch_result.ber_mode = options.ber_mode;
batch_result.chunk_count = numel(chunk_entries);
batch_result.successful_chunks = successful_chunks;
batch_result.failed_chunks = failed_chunks;
batch_result.aggregate_errors = aggregate_errors;
batch_result.aggregate_bits = aggregate_bits;
batch_result.aggregate_ber = aggregate_ber;
batch_result.per_chunk = per_chunk;
batch_result.options = options;
batch_result.summary_path = '';

if options.save_batch_summary
    summary_dir = options.summary_dir;
    if exist(summary_dir, 'dir') ~= 7
        mkdir(summary_dir);
    end
    summary_path = fullfile(summary_dir, ...
        sprintf('ber_chunk_group_%s_%s.mat', sanitize_name(capture_group_id), datestr(now, 'yyyymmdd_HHMMSS')));
    save(summary_path, 'batch_result');
    batch_result.summary_path = summary_path;
    fprintf('批量汇总结果已保存：%s\n', summary_path);
end
end


function options = apply_default_options(options, matlab_root)
    if ~isfield(options, 'ber_mode') || isempty(options.ber_mode)
        options.ber_mode = 'tracked_truth';
    end
    if ~isfield(options, 'tx_truth_path') || isempty(options.tx_truth_path)
        options.tx_truth_path = '';
    end
    if ~isfield(options, 'tracking_options') || isempty(options.tracking_options)
        options.tracking_options = struct();
    end
    if ~isfield(options, 'accel_options') || isempty(options.accel_options)
        options.accel_options = struct();
    end
    if ~isfield(options, 'workspace_tx_truth_fallback_path') || isempty(options.workspace_tx_truth_fallback_path)
        options.workspace_tx_truth_fallback_path = '';
    end
    if ~isfield(options, 'plot_each_chunk') || isempty(options.plot_each_chunk)
        options.plot_each_chunk = false;
    end
    if ~isfield(options, 'prompt_save_each_chunk') || isempty(options.prompt_save_each_chunk)
        options.prompt_save_each_chunk = false;
    end
    if ~isfield(options, 'save_choice_each_chunk') || isempty(options.save_choice_each_chunk)
        options.save_choice_each_chunk = 'n';
    end
    if ~isfield(options, 'continue_on_error') || isempty(options.continue_on_error)
        options.continue_on_error = true;
    end
    if ~isfield(options, 'save_batch_summary') || isempty(options.save_batch_summary)
        options.save_batch_summary = true;
    end
    if ~isfield(options, 'summary_dir') || isempty(options.summary_dir)
        options.summary_dir = fullfile(matlab_root, 'results');
    end
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


function out = sanitize_name(input_name)
    out = regexprep(char(string(input_name)), '[^A-Za-z0-9_-]', '_');
end
