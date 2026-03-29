function truth = load_tx_truth_json(path)
% LOAD_TX_TRUTH_JSON 读取由 gnss_tx 导出的 BER truth JSON 契约。
%
% 对新手来说，可以把这个 JSON 理解为“发送端留下的标准答案”：
% 它告诉接收端离线分析脚本，发送时到底用了哪一串导航比特、
% 起始码相位和起始 bit 索引在哪里。后续 BER 计算能否可信，
% 很大程度上取决于这个 truth 文件是否和当前采集一一对应。

    % 读取并解析 JSON 文件。jsondecode 会把 JSON 对象映射为 MATLAB 结构体，
    % 后续字段访问都基于这个原始结构体进行。
    raw = jsondecode(fileread(path));

    % 定义下游 BER/对齐分析所依赖的必需字段。
    % 各字段含义如下：
    %   nav_bits_pattern_pm1   : 导航比特序列，使用 +1/-1 表示
    %   nav_bits_pattern_01    : 同一序列的 0/1 表示形式
    %   initial_code_phase     : 采集起点对应的初始码相位
    %   initial_nav_epoch      : 采集起点对应的初始导航 epoch（通常按 1 ms 计）
    %   initial_nav_bit_index  : 采集起点对应的导航比特索引
    %   samples_per_chip       : 每个 PRN 码片对应的采样点数
    %   sample_rate            : IQ 数据采样率
    %   epochs_per_bit         : 每个导航比特包含的 epoch 数
    %   prn_id                 : 对应卫星的 PRN 编号
    % 这里显式列出字段名，便于在输入契约变化时尽早报错。
    required_fields = { ...
        'nav_bits_pattern_pm1', ...
        'nav_bits_pattern_01', ...
        'initial_code_phase', ...
        'initial_nav_epoch', ...
        'initial_nav_bit_index', ...
        'samples_per_chip', ...
        'sample_rate', ...
        'epochs_per_bit', ...
        'prn_id'};

    % 逐个检查必需字段是否存在，避免后面在访问缺失字段时抛出更难定位的错误。
    for k = 1:numel(required_fields)
        field_name = required_fields{k};
        if ~isfield(raw, field_name)
            error('GNSS_RX:MissingTruthField', ...
                'TX truth JSON 缺少字段：%s', field_name);
        end
    end

    % 将原始 JSON 内容整理成项目内部统一使用的 truth 结构体。
    % 同时把数值字段转换为 double，并把比特模式强制整理为列向量，
    % 方便后续 MATLAB 代码按统一形状进行索引和运算。
    truth = struct();
    truth.source_path = char(string(path));
    truth.truth_mode = 'json';
    truth.nav_bits_pattern_pm1 = double(raw.nav_bits_pattern_pm1(:));
    truth.nav_bits_pattern_01 = double(raw.nav_bits_pattern_01(:));
    truth.initial_code_phase = double(raw.initial_code_phase);
    truth.initial_nav_epoch = double(raw.initial_nav_epoch);
    truth.initial_nav_bit_index = double(raw.initial_nav_bit_index);
    truth.samples_per_chip = double(raw.samples_per_chip);
    truth.sample_rate = double(raw.sample_rate);
    truth.epochs_per_bit = double(raw.epochs_per_bit);
    truth.prn_id = double(raw.prn_id);
end
