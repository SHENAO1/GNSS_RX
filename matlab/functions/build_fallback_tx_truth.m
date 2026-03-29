function truth = build_fallback_tx_truth(tx_pattern_pm1, meta, acq_result)
% BUILD_FALLBACK_TX_TRUTH 当未提供 TX truth JSON 时，构造一个“兜底真值”结构体。
%
% 这个函数解决的问题是：
% 如果发送端没有导出标准 truth JSON，后面的 BER/对齐代码仍然需要一个
% 结构统一的参考对象才能继续运行。于是我们基于“默认比特模式 + 若干合理假设”
% 生成一个 fallback truth，让旧流程至少可以继续跑通。
%
% 要注意：
%   1. fallback truth 主要用于兼容和排查，不代表真实 TX 状态一定如此；
%   2. 用它得到的 BER 结果只适合做粗诊断，不适合替代真实 truth 做严格结论。
%
% 输入参数：
%   tx_pattern_pm1 - 发送比特模式，使用 +1/-1 表示
%   meta           - 采集元数据，至少包含 sample_rate_hz
%   acq_result     - 捕获结果，若包含 PRN 信息会优先复用

    % 把输入模式统一整理成列向量，便于后续索引和与接收比特逐项比较。
    pattern_pm1 = double(tx_pattern_pm1(:));

    % 初始化 truth 结构体。字段名尽量和 JSON truth 保持一致，
    % 这样后面的代码就可以把两者当成同一种“契约对象”来使用。
    truth = struct();

    % 没有真实来源文件，因此 source_path 留空。
    truth.source_path = '';

    % 显式标记这是 fallback 模式，方便后续日志和图中区分。
    truth.truth_mode = 'fallback';

    % 保存双极性格式的原始参考比特。
    truth.nav_bits_pattern_pm1 = pattern_pm1;

    % 同时补一份 0/1 形式，兼容可能使用二进制表示的旧代码。
    truth.nav_bits_pattern_01 = double(pattern_pm1 > 0);

    % 以下几个字段在没有真实 truth 时无法准确获知，只能采用“从 0 开始”的保守假设。
    truth.initial_code_phase = 0;       % 初始 C/A 码相位
    truth.initial_nav_epoch = 0;        % 初始 1 ms epoch 计数
    truth.initial_nav_bit_index = 0;    % 起始落在参考 pattern 的第 0 个 bit

    % GPS L1 C/A 码速率固定为 1.023 MHz，因此可直接由采样率换算采样点/码片。
    truth.samples_per_chip = meta.sample_rate_hz / 1.023e6;

    % 保存采样率，便于后续模块无需回头再查 meta。
    truth.sample_rate = meta.sample_rate_hz;

    % GPS L1 C/A 导航 bit 长度为 20 ms，而一个 C/A 码周期是 1 ms，
    % 所以一个导航 bit 恰好对应 20 个 epoch。
    truth.epochs_per_bit = 20;

    % 尽量把 PRN 编号也补齐，便于后续日志和绘图知道当前参考的是哪颗星。
    % 这里优先兼容旧字段 prn_id，其次回退到 meta.prn_id，最后默认 PRN1。
    if isfield(acq_result, 'prn_id')
        truth.prn_id = acq_result.prn_id;
    elseif isfield(meta, 'prn_id')
        truth.prn_id = meta.prn_id;
    else
        truth.prn_id = 1;
    end
end
