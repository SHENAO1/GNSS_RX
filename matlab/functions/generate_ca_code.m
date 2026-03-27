function prn = generate_ca_code(prn_id)
% GENERATE_CA_CODE  生成 GPS L1 C/A PRN 码（双极性，+1/-1，1023 chip）
%
% 输入：
%   prn_id  - PRN 编号（整数，1~32）
%
% 输出：
%   prn     - C/A 码序列（行向量，+1/-1，长度 1023）
%
% 算法：双 LFSR（G1 + G2），与 gnss_tx/src/gnss_tx/ca/prn_generator.py 逻辑一致。
% 0 → +1，1 → -1（双极性约定）。

    % G2 移位寄存器抽头表（索引对应 PRN 1~32）
    G2_taps = {
        [2,6],[3,7],[4,8],[5,9],[1,9],[2,10],[1,8],[2,9],[3,10],...
        [2,3],[3,4],[5,6],[6,7],[7,8],[8,9],[9,10],[1,4],[2,5],...
        [3,6],[4,7],[5,8],[6,9],[1,3],[4,6],[5,7],[6,8],[7,9],...
        [8,10],[1,6],[2,7],[3,8],[4,9]
    };

    if prn_id < 1 || prn_id > 32
        error('generate_ca_code: prn_id 必须在 1~32 之间，当前值：%d', prn_id);
    end

    G1 = ones(1, 10);
    G2 = ones(1, 10);
    taps = G2_taps{prn_id};
    prn = zeros(1, 1023);

    for i = 1:1023
        g1_out  = G1(10);
        g2_out  = xor(G2(taps(1)), G2(taps(2)));
        prn(i)  = xor(g1_out, g2_out);

        % G1：反馈多项式 1 + x^3 + x^10（抽头 3、10）
        G1 = [xor(G1(3), G1(10)), G1(1:9)];

        % G2：反馈多项式 1 + x^2 + x^3 + x^6 + x^8 + x^9 + x^10（抽头 2,3,6,8,9,10）
        G2 = [xor(xor(xor(xor(xor(G2(2), G2(3)), G2(6)), G2(8)), G2(9)), G2(10)), G2(1:9)];
    end

    % 二进制 0/1 转双极性 +1/-1
    prn = 1 - 2 * prn;
end
