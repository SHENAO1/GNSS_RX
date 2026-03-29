function result = run_prn1_acquisition(samples, meta, cfg)
%RUN_PRN1_ACQUISITION 对一段基带 IQ 样本执行 GPS L1 C/A PRN1 信号捕获搜索。
%
%   向后兼容封装：强制将 meta.prn_id 设为 1，然后委托给通用化的 run_prn_acquisition。
%   如需搜索其他 PRN，请直接调用 run_prn_acquisition 并在 meta 中设置正确的 prn_id。
%
%   保留这个函数的主要原因是兼容早期只处理 PRN1 的脚本和讲义；
%   新代码更推荐直接使用 run_prn_acquisition。
%
%   输入：
%     samples  —— 复数基带样本列向量（已归一化到 [-1, 1]）
%     meta     —— 元数据结构体，须包含 sample_rate_hz 字段
%     cfg      —— 可选配置结构体
%
%   输出：result 结构体，包含捕获结论、峰值位置、多普勒估计和搜索图数据

if nargin < 3
    cfg = struct();
end

% 强制使用 PRN 1（向后兼容保证）。
prn1_meta        = meta;
prn1_meta.prn_id = 1;

result = run_prn_acquisition(samples, prn1_meta, cfg);
end
