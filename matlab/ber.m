%% ber.m -- BER 分析快捷入口
%
% 规范源码位置：
%   GNSS_RX/matlab/ber.m
%
% 部署位置：
%   GNSS_RX_matlab 根目录（与 functions/、scripts/ 同级）
%
% 用法（在 MATLAB 命令行中）：
%   ber
%       自动分析最新采集文件，并默认使用同目录下的 tx_truth.json。
%
%   CAPTURE_PATH = 'xxx.json'; ber
%       分析指定采集文件。
%
%   clear CAPTURE_PATH; ber
%       清除手动指定路径，回到“自动分析最新采集”的模式。
%
% 说明：
%   - 若未手动设置 TX_TRUTH_PATH，则默认指向当前目录下的 tx_truth.json。
%   - 若未手动设置 BER_MODE，则默认使用 tracked_truth。
%   - 当 CAPTURE_PATH 未设置时，run_ber_loopback.m 内部仍可继续走交互式选文件流程。

here = fileparts(mfilename('fullpath'));

% 每次调用都刷新搜索路径，确保共享目录中的部署副本更新后能立刻生效。
addpath(fullfile(here, 'functions'));
addpath(fullfile(here, 'scripts'));
clear functions %#ok<CLFUNC>
rehash

% 若调用前未显式指定 truth JSON，则默认使用当前目录下的 tx_truth.json。
if ~exist('TX_TRUTH_PATH', 'var') || isempty(TX_TRUTH_PATH)
    TX_TRUTH_PATH = fullfile(here, 'tx_truth.json');
end

% 默认走 tracked BER 主链；如需 open-loop 基线，可在调用前手工覆盖。
if ~exist('BER_MODE', 'var') || isempty(BER_MODE)
    BER_MODE = 'tracked_truth';
end

% 统一委托给主脚本执行；本文件只负责入口变量与路径准备。
run(fullfile(here, 'scripts', 'run_ber_loopback.m'));
