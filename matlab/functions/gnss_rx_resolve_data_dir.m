function data_dir = gnss_rx_resolve_data_dir()
%GNSS_RX_RESOLVE_DATA_DIR 按优先级自动解析 GNSS 采集数据的根目录路径。
%
%   解析优先级（从高到低）：
%     1. matlab/gnss_rx_user_paths.m  —— 用户本地配置文件（不纳入 git，个人专用）
%     2. 环境变量 GNSS_RX_DATA_DIR    —— 适合在脚本或 CI 环境中统一设置
%     3. 平台默认路径                  —— 向后兼容，仅作兜底
%
%   首次使用前，请复制 matlab/gnss_rx_user_paths.m.example 为
%   matlab/gnss_rx_user_paths.m，并在其中填写本地数据目录路径。

% 找到当前函数文件所在的目录（matlab/functions/），进而推导出 matlab/ 目录。
this_dir    = fileparts(mfilename('fullpath'));   % matlab/functions/
matlab_root = fileparts(this_dir);               % matlab/

% 拼出用户本地配置文件的路径。
config_file = fullfile(matlab_root, 'gnss_rx_user_paths.m');

% 优先级 1：检查用户本地配置文件是否存在。
% run() 在当前函数的工作区中执行该脚本，脚本中定义的变量在本函数中可见。
if exist(config_file, 'file')
    run(config_file);
    % 检查脚本是否真的定义了 GNSS_RX_DATA_DIR，避免因配置文件写错
    % 而产生"未定义变量"这类让人困惑的错误信息。
    if ~exist('GNSS_RX_DATA_DIR', 'var') || isempty(GNSS_RX_DATA_DIR)
        error('GNSS_RX:ConfigMissingVar', ...
            '配置文件 %s 中未定义 GNSS_RX_DATA_DIR 变量，请参考示例文件填写。', ...
            config_file);
    end
    data_dir = GNSS_RX_DATA_DIR;
    return;
end

% 优先级 2：读取环境变量 GNSS_RX_DATA_DIR。
% 适合在启动脚本或持续集成环境中通过 setenv('GNSS_RX_DATA_DIR', '/path') 统一配置。
env_val = getenv('GNSS_RX_DATA_DIR');
if ~isempty(env_val)
    data_dir = env_val;
    return;
end

% 优先级 3：平台默认路径（向后兼容，不推荐长期依赖）。
% 建议通过以上两种方式覆盖，以避免在不同机器上路径不一致的问题。
if ispc
    % Windows 平台默认路径（VMware 共享文件夹路径）
    data_dir = 'C:\VMwareVirtualMachines\GongXiangDocument\GNSS_RX_Data';
else
    % Linux/macOS 平台默认路径（VMware hgfs 挂载点）
    data_dir = '/mnt/hgfs/GongXiangDocument/GNSS_RX_Data';
end
end
