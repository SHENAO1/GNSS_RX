function [samples, meta, paths] = load_gnss_rx_capture(stem_or_json_path, output_precision)
%LOAD_GNSS_RX_CAPTURE 读取一组 GNSS_RX 采集文件，输出复数基带样本、元数据和路径信息。
%
%   GNSS 接收机的数据采集结果由两个文件组成：
%       .sc16  —— 原始 IQ 数据（SC16 格式：每个复数样本由两个 int16 整数组成，
%                 分别代表 I 分量和 Q 分量，交织存储）
%       .json  —— 元数据（记录采样率、中心频率、采集时长等参数）
%
%   本函数同时接受以下三种输入形式：
%       load_gnss_rx_capture('/path/to/capture')       % stem 路径（不带扩展名）
%       load_gnss_rx_capture('/path/to/capture.json')  % .json 路径
%       load_gnss_rx_capture('/path/to/capture.sc16')  % .sc16 路径
%
%   输出：
%       samples  —— 复数基带样本列向量，归一化到 [-1, 1]（I 为实部，Q 为虚部）
%       meta     —— 元数据结构体（解析自 .json，包含 sample_rate_hz 等字段）
%       paths    —— 路径信息结构体（包含各文件路径和分析结果目录）
%
%   这是整个 MATLAB 分析链从“磁盘文件”进入“内存对象”的桥梁函数。
%   后续几乎所有分析函数都默认输入已经是这里整理好的 samples / meta / paths。

% 检查输入参数，不允许为空，否则无从知道要读哪组文件。
if nargin < 1 || strlength(string(stem_or_json_path)) == 0
    error('GNSS_RX:MissingCapturePath', ...
        '请提供采集文件的 stem 路径或 .json 路径。');
end
if nargin < 2 || isempty(output_precision)
    output_precision = 'double';
end
output_precision = lower(char(string(output_precision)));
if ~ismember(output_precision, {'single', 'double'})
    error('GNSS_RX:InvalidOutputPrecision', ...
        'output_precision 必须是 single 或 double，当前为 %s。', output_precision);
end

% 转换为 string 类型并去除前后空格，避免因误输入空格导致路径解析失败。
input_path = strip(string(stem_or_json_path));

% 根据文件扩展名判断用户传入的是哪种路径，统一推导出 stem_path 和 json_path。
% 使用 fileparts 而不是字符串替换，避免路径中目录名包含 .json 时出错。
[folder, name, ext] = fileparts(char(input_path));
ext_lower = lower(ext);
if strcmp(ext_lower, '.json')
    % 传入的是 .json 路径
    json_path = input_path;
    stem_path = string(fullfile(folder, name));
elseif strcmp(ext_lower, '.sc16')
    % 传入的是 .sc16 路径
    stem_path = string(fullfile(folder, name));
    json_path = stem_path + ".json";
else
    % 传入的是 stem 路径（不带扩展名），直接补全即可
    stem_path = input_path;
    json_path = stem_path + ".json";
end

% 推导 .sc16 文件路径（统一在推导出 stem_path 之后拼出）。
sc16_path = stem_path + ".sc16";

% 强制要求 .json 和 .sc16 成对存在，避免读到"半组"文件而产生误导性结果。
if ~isfile(json_path)
    error('GNSS_RX:MissingJson', '未找到元数据文件：%s', json_path);
end
if ~isfile(sc16_path)
    error('GNSS_RX:MissingSc16', '未找到 IQ 数据文件：%s', sc16_path);
end

% 读取并解析 .json 元数据文件。
% jsondecode 会把 JSON 对象转成 MATLAB 结构体，字段名与 JSON 键名一一对应。
meta = jsondecode(fileread(char(json_path)));

% 以二进制模式打开 .sc16 文件，指定字节序为 little-endian（低字节在前）。
% 这与 Python 端 GNU Radio 写入时的字节序一致。
fid = fopen(char(sc16_path), 'rb', 'ieee-le');
if fid < 0
    error('GNSS_RX:OpenFailed', '无法打开 IQ 数据文件：%s', sc16_path);
end
% 使用 onCleanup 确保即使后续发生错误，文件句柄也一定会被关闭，避免资源泄漏。
file_cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>

% 读取所有 int16 数据并转换为指定精度，兼顾长采集内存压力。
% SC16 格式：奇数位置为 I 分量，偶数位置为 Q 分量，交织存储。
raw_iq = fread(fid, inf, sprintf('int16=>%s', output_precision));

% 检查样本数是否为偶数。SC16 格式每个复数样本由 I 和 Q 各一个 int16 组成，
% 若总数为奇数，说明文件不完整或写入时出错。
if mod(numel(raw_iq), 2) ~= 0
    error('GNSS_RX:MalformedSc16', ...
        'IQ 数据文件中 int16 数值数量为奇数，文件可能不完整：%s', sc16_path);
end

% 将交织的 int16 分离为 I、Q 分量，并归一化到 [-1, 1]。
% GNSS_RX 使用 32767 作为满量程值（int16 最大正值为 32767）。
% 奇数下标（1, 3, 5, ...）为 I 分量，偶数下标（2, 4, 6, ...）为 Q 分量。
scale = cast(32767.0, output_precision);
i_samples = raw_iq(1:2:end) ./ scale;
q_samples = raw_iq(2:2:end) ./ scale;

% 组合成复数基带信号：实部 = I，虚部 = Q。
% 这是软件无线电（SDR）领域的标准表示方式，后续频谱、相关、去载波都基于这种复数形式。
samples = complex(i_samples, q_samples);

% 交叉验证：元数据中记录的样本数应与实际读取的复数样本数一致。
% 如果不一致，发出警告（不直接报错，以便后续分析仍能继续进行）。
if isfield(meta, 'samples_captured') && meta.samples_captured ~= numel(samples)
    warning('GNSS_RX:SampleCountMismatch', ...
        '元数据记录样本数 %d，但实际读取到 %d 个复数样本，两者不符。', ...
        meta.samples_captured, numel(samples));
end

% 整理路径信息结构体，将后续分析和保存结果时需要用到的路径统一打包。
% analysis_dir 使用 stem_name 作为子目录，确保不同采集文件的分析结果互不覆盖。
capture_dir = string(fileparts(char(json_path)));
[~, stem_name_only, ~] = fileparts(char(stem_path));

paths = struct();
paths.capture_dir  = char(capture_dir);
paths.stem_name    = stem_name_only;
paths.stem_path    = char(stem_path);
paths.json_path    = char(json_path);
paths.sc16_path    = char(sc16_path);
paths.analysis_dir = fullfile(char(capture_dir), 'analysis', stem_name_only);
end
