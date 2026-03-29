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

    if nargin < 1 || isempty(accel_options)
        accel_options = struct();
    end

    % 若调用方已经传入解析后的结构体，直接复用，避免重复触发 gpuDevice。
    if isstruct(accel_options) ...
            && isfield(accel_options, 'resolved_backend') ...
            && isfield(accel_options, 'gpu_enabled') ...
            && isfield(accel_options, 'precision')
        accel = accel_options;
        return;
    end

    defaults = struct( ...
        'backend', 'cpu', ...
        'precision', 'double', ...
        'batch_ms', 2000, ...
        'use_parfor', false, ...
        'device_index', []);

    accel = defaults;
    option_names = fieldnames(defaults);
    for k = 1:numel(option_names)
        name = option_names{k};
        if isfield(accel_options, name) && ~isempty(accel_options.(name))
            accel.(name) = accel_options.(name);
        end
    end

    accel.requested_backend = lower(char(string(accel.backend)));
    accel.precision = lower(char(string(accel.precision)));
    accel.batch_ms = max(1, round(double(accel.batch_ms)));
    accel.use_parfor = logical(accel.use_parfor);

    valid_backends = {'cpu', 'gpu', 'auto'};
    if ~ismember(accel.requested_backend, valid_backends)
        error('GNSS_RX:InvalidAccelBackend', ...
            'ACCEL_OPTIONS.backend 必须是 cpu / gpu / auto 之一，当前为 %s。', ...
            accel.requested_backend);
    end

    valid_precisions = {'single', 'double'};
    if ~ismember(accel.precision, valid_precisions)
        error('GNSS_RX:InvalidAccelPrecision', ...
            'ACCEL_OPTIONS.precision 必须是 single / double 之一，当前为 %s。', ...
            accel.precision);
    end

    accel.parallel_toolbox_available = ~isempty(ver('parallel')) ...
        || license('test', 'Distrib_Computing_Toolbox');
    accel.gpu_available = false;
    accel.gpu_device_name = '';
    accel.gpu_device_index = [];
    accel.gpu_enabled = false;
    accel.fallback_reason = '';

    gpu_count = discover_gpu_count();
    accel.gpu_available = gpu_count > 0;

    switch accel.requested_backend
        case 'cpu'
            accel.resolved_backend = 'cpu';
        case 'auto'
            if accel.gpu_available
                accel = attach_gpu_device(accel);
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

    accel.use_single = strcmp(accel.precision, 'single');
    accel.precision_class = accel.precision;

    if accel.gpu_enabled
        accel.parfor_enabled = false;
    else
        accel.parfor_enabled = accel.use_parfor && accel.parallel_toolbox_available;
    end
end

function gpu_count = discover_gpu_count()
    gpu_count = 0;
    try
        gpu_count = gpuDeviceCount("available");
        return;
    catch
        % 老版本 MATLAB 可能不支持字符串参数，继续尝试无参版本。
    end

    try
        gpu_count = gpuDeviceCount;
    catch
        gpu_count = 0;
    end
end

function accel = attach_gpu_device(accel)
    try
        if isempty(accel.device_index)
            device = gpuDevice;
        else
            device = gpuDevice(double(accel.device_index));
        end
    catch ME
        error('GNSS_RX:GpuAttachFailed', ...
            'GPU 初始化失败：%s', ME.message);
    end

    accel.resolved_backend = 'gpu';
    accel.gpu_enabled = true;
    accel.gpu_device_name = char(string(device.Name));
    accel.gpu_device_index = double(device.Index);
end
