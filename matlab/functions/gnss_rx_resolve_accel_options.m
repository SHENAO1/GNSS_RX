function accel = gnss_rx_resolve_accel_options(accel_options)
%GNSS_RX_RESOLVE_ACCEL_OPTIONS 统一解析 MATLAB 离线分析链的加速配置。
%
%   accel = gnss_rx_resolve_accel_options()
%   accel = gnss_rx_resolve_accel_options(accel_options)
%
% 支持字段：
%   backend     - 'cpu' | 'gpu' | 'auto'
%   precision   - 'single' | 'double'
%   batch_ms    - 长样本分批窗口（正整数）
%   use_parfor  - 是否允许在 CPU 路径使用 parfor
%   device_index - 可选 GPU 设备序号
%
% 设计目标 ：
% 1) 给调用方一个“可预测”的统一配置结构体；
% 2) 自动处理默认值、非法输入、GPU 不可用时的回退；
% 3) 避免上层脚本到处写 if-else 判断硬件能力。
%
% 从介绍角度看，这个函数可以理解成“加速策略翻译器”：
% 调用方只需表达“我想用 CPU / GPU / 自动模式”，
% 它负责把这个意图翻译成一组可以直接执行的细化配置。

    % 未传配置时，使用空结构体进入“默认参数 + 局部覆盖”流程。
    if nargin < 1 || isempty(accel_options)
        accel_options = struct();
    end

    % 若调用方已经传入“解析后”的结构体，直接复用。
    % 这样可以避免重复执行 gpuDevice()，减少启动开销，也避免重复切设备。
    if isstruct(accel_options) ...
            && isfield(accel_options, 'resolved_backend') ...
            && isfield(accel_options, 'gpu_enabled') ...
            && isfield(accel_options, 'precision')
        accel = accel_options;
        return;
    end

    % 默认配置：偏保守（CPU + double），兼顾稳定性与可复现性。
    defaults = struct( ...
        'backend', 'cpu', ...
        'precision', 'double', ...
        'batch_ms', 2000, ...
        'use_parfor', false, ...
        'device_index', []);

    % 先复制默认值，再按字段逐项覆盖（仅覆盖调用方显式提供且非空的字段）。
    % 这种写法能确保新字段加入 defaults 后，旧调用方也能自动兼容。
    accel = defaults;
    option_names = fieldnames(defaults);
    for k = 1:numel(option_names)
        name = option_names{k};
        if isfield(accel_options, name) && ~isempty(accel_options.(name))
            accel.(name) = accel_options.(name);
        end
    end

    % 规范化输入类型与格式，减少后续分支判断复杂度：
    % - backend/precision 统一转小写字符串
    % - batch_ms 统一为 >=1 的整数
    % - use_parfor 强制转为逻辑值
    accel.requested_backend = lower(char(string(accel.backend)));
    accel.precision = lower(char(string(accel.precision)));
    accel.batch_ms = max(1, round(double(accel.batch_ms)));
    accel.use_parfor = logical(accel.use_parfor);

    % 校验 backend 合法性，尽早报错（fail fast），避免后面出现隐蔽行为。
    valid_backends = {'cpu', 'gpu', 'auto'};
    if ~ismember(accel.requested_backend, valid_backends)
        error('GNSS_RX:InvalidAccelBackend', ...
            'ACCEL_OPTIONS.backend 必须是 cpu / gpu / auto 之一，当前为 %s。', ...
            accel.requested_backend);
    end

    % 校验精度选项。
    valid_precisions = {'single', 'double'};
    if ~ismember(accel.precision, valid_precisions)
        error('GNSS_RX:InvalidAccelPrecision', ...
            'ACCEL_OPTIONS.precision 必须是 single / double 之一，当前为 %s。', ...
            accel.precision);
    end

    % 检测并行工具箱可用性：
    % - ver('parallel') 可检查安装信息
    % - license('test', ...) 可检查许可状态
    % 任一条件满足即可认为可用。
    accel.parallel_toolbox_available = ~isempty(ver('parallel')) ...
        || license('test', 'Distrib_Computing_Toolbox');

    % 先初始化一组状态字段，保证返回结构体字段稳定。
    % 上层代码可直接读取这些字段，不必担心“字段不存在”。
    accel.gpu_available = false;
    accel.gpu_device_name = '';
    accel.gpu_device_index = [];
    accel.gpu_enabled = false;
    accel.fallback_reason = '';

    % 独立封装 GPU 数量探测，内部已做版本兼容和异常兜底。
    gpu_count = discover_gpu_count();
    accel.gpu_available = gpu_count > 0;

    % 根据请求后端做最终决策：
    % - cpu: 强制 CPU
    % - auto: 有 GPU 就用 GPU，否则回退 CPU 并记录原因
    % - gpu: 必须使用 GPU，不可用时直接报错
    switch accel.requested_backend
        case 'cpu'
            accel.resolved_backend = 'cpu';
        case 'auto'
            if accel.gpu_available
                try
                    accel = attach_gpu_device(accel);
                catch ME
                    accel.resolved_backend = 'cpu';
                    accel.gpu_enabled = false;
                    accel.fallback_reason = sprintf( ...
                        '检测到 GPU，但初始化失败：%s 已自动回退到 CPU。', ...
                        ME.message);
                end
            else
                accel.resolved_backend = 'cpu';
                accel.fallback_reason = '未检测到可用 GPU，已自动回退到 CPU。';
            end
        case 'gpu'
            if ~accel.gpu_available
                error('GNSS_RX:GpuUnavailable', ...
                    'ACCEL_OPTIONS.backend=gpu，但当前 MATLAB 未检测到可用 GPU。');
            end
            accel = attach_gpu_device(accel);
    end

    % 便于调用方使用的派生字段：
    % - use_single: 常见的 if 分支判断
    % - precision_class: 直接可用于 cast(..., precision_class)
    accel.use_single = strcmp(accel.precision, 'single');
    accel.precision_class = accel.precision;

    % parfor 仅在 CPU 路径开启：
    % GPU 计算时再开 parfor 通常收益不稳定，且资源竞争复杂，因此默认禁用。
    if accel.gpu_enabled
        accel.parfor_enabled = false;
    else
        accel.parfor_enabled = accel.use_parfor && accel.parallel_toolbox_available;
    end
end

function gpu_count = discover_gpu_count()
    % 统一封装 GPU 数量探测，兼容不同 MATLAB 版本接口差异。
    gpu_count = 0;
    try
        % 新接口：仅统计可用设备（更符合“能不能用”的语义）。
        gpu_count = gpuDeviceCount("available");
        return;
    catch
        % 老版本 MATLAB 可能不支持字符串参数，继续尝试无参版本。
    end

    try
        % 旧接口：返回总设备数。
        gpu_count = gpuDeviceCount;
    catch
        % 任意异常都按“不可用”处理，避免硬件/驱动问题中断主流程。
        gpu_count = 0;
    end
end

function accel = attach_gpu_device(accel)
    % 尝试绑定 GPU 设备，并把设备信息写入返回结构体。
    try
        if isempty(accel.device_index)
            % 未指定设备时，让 MATLAB 自动选择默认 GPU。
            device = gpuDevice;
        else
            % 显式指定设备索引时，强制绑定到对应设备。
            device = gpuDevice(double(accel.device_index));
        end
    catch ME
        % 统一转成业务错误码，方便上层捕获并做提示。
        error('GNSS_RX:GpuAttachFailed', ...
            'GPU 初始化失败：%s', ME.message);
    end

    % 绑定成功后写入最终状态。
    accel.resolved_backend = 'gpu';
    accel.gpu_enabled = true;
    accel.gpu_device_name = char(string(device.Name));
    accel.gpu_device_index = double(device.Index);
end
