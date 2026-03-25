function [samples, meta, paths] = load_gnss_rx_capture(stem_or_json_path)
%LOAD_GNSS_RX_CAPTURE 读取一组 GNSS_RX 采集文件并还原为复数基带。

if nargin < 1 || strlength(string(stem_or_json_path)) == 0
    error('GNSS_RX:MissingCapturePath', ...
        'Provide a capture stem path or a .json path.');
end

input_path = string(stem_or_json_path);
input_path = strip(input_path);

if endsWith(lower(input_path), ".json")
    json_path = input_path;
    stem_path = erase(input_path, ".json");
elseif endsWith(lower(input_path), ".sc16")
    stem_path = erase(input_path, ".sc16");
    json_path = stem_path + ".json";
else
    stem_path = input_path;
    json_path = stem_path + ".json";
end

sc16_path = stem_path + ".sc16";

% MATLAB 侧强制要求 .json 和 .sc16 成对存在，避免只分析到半组文件。
if ~isfile(json_path)
    error('GNSS_RX:MissingJson', 'JSON sidecar not found: %s', json_path);
end
if ~isfile(sc16_path)
    error('GNSS_RX:MissingSc16', 'SC16 file not found: %s', sc16_path);
end

meta = jsondecode(fileread(json_path));

% Python 侧导出的是 little-endian 交织 int16，这里按 I/Q 成对读回。
fid = fopen(sc16_path, 'rb', 'ieee-le');
if fid < 0
    error('GNSS_RX:OpenFailed', 'Failed to open SC16 file: %s', sc16_path);
end
raw_iq = fread(fid, inf, 'int16=>double');
fclose(fid);

if mod(numel(raw_iq), 2) ~= 0
    error('GNSS_RX:MalformedSc16', ...
        'SC16 file has an odd number of int16 values: %s', sc16_path);
end

% GNSS_RX 当前把满量程复数样本映射到 [-32767, 32767]，这里再归一化回 [-1, 1]。
i_samples = raw_iq(1:2:end) ./ 32767.0;
q_samples = raw_iq(2:2:end) ./ 32767.0;
samples = complex(i_samples, q_samples);

% 元数据里的 samples_captured 应与实际复数样本数匹配；不一致时发 warning。
if isfield(meta, 'samples_captured') && meta.samples_captured ~= numel(samples)
    warning('GNSS_RX:SampleCountMismatch', ...
        'samples_captured=%d but loaded complex sample count=%d', ...
        meta.samples_captured, numel(samples));
end

capture_dir = string(fileparts(json_path));
[~, stem_name_only, ~] = fileparts(char(stem_path));
% paths 统一整理后续分析与结果保存要用到的所有关键路径。
paths = struct();
paths.capture_dir = char(capture_dir);
paths.stem_name = stem_name_only;
paths.stem_path = char(stem_path);
paths.json_path = char(json_path);
paths.sc16_path = char(sc16_path);
paths.analysis_dir = fullfile(paths.capture_dir, 'analysis');
end
