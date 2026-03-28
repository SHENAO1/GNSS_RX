function truth = build_fallback_tx_truth(tx_pattern_pm1, meta, acq_result)
% BUILD_FALLBACK_TX_TRUTH 当未提供 TX truth JSON 时，使用旧默认模式构造回退真值。

    pattern_pm1 = double(tx_pattern_pm1(:));
    truth = struct();
    truth.source_path = '';
    truth.truth_mode = 'fallback';
    truth.nav_bits_pattern_pm1 = pattern_pm1;
    truth.nav_bits_pattern_01 = double(pattern_pm1 > 0);
    truth.initial_code_phase = 0;
    truth.initial_nav_epoch = 0;
    truth.initial_nav_bit_index = 0;
    truth.samples_per_chip = meta.sample_rate_hz / 1.023e6;
    truth.sample_rate = meta.sample_rate_hz;
    truth.epochs_per_bit = 20;
    if isfield(acq_result, 'prn_id')
        truth.prn_id = acq_result.prn_id;
    elseif isfield(meta, 'prn_id')
        truth.prn_id = meta.prn_id;
    else
        truth.prn_id = 1;
    end
end
