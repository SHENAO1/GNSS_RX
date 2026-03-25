function data_dir = gnss_rx_resolve_data_dir()
%GNSS_RX_RESOLVE_DATA_DIR 按优先级解析采集数据根目录路径。
%
%   解析优先级（从高到低）：
%     1. matlab/gnss_rx_user_paths.m — 用户本地配置文件（不纳入 git）
%     2. 环境变量 GNSS_RX_DATA_DIR
%     3. 平台默认值（向后兼容）
%
%   首次使用时，请复制 matlab/gnss_rx_user_paths.m.example 为
%   matlab/gnss_rx_user_paths.m，并填入本地路径。

this_dir = fileparts(mfilename('fullpath'));    % matlab/functions/
matlab_root = fileparts(this_dir);             % matlab/
config_file = fullfile(matlab_root, 'gnss_rx_user_paths.m');

if exist(config_file, 'file')
    % 在独立函数工作区中执行配置脚本，读取 GNSS_RX_DATA_DIR 变量。
    run(config_file);
    data_dir = GNSS_RX_DATA_DIR;
    return;
end

env_val = getenv('GNSS_RX_DATA_DIR');
if ~isempty(env_val)
    data_dir = env_val;
    return;
end

% 平台默认值（向后兼容，建议通过上述两种方式覆盖）
if ispc
    data_dir = 'C:\VMwareVirtualMachines\GongXiangDocument\GNSS_RX_Data';
else
    data_dir = '/mnt/hgfs/GongXiangDocument/GNSS_RX_Data';
end
end
