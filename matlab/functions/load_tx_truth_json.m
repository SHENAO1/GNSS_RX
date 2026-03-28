function truth = load_tx_truth_json(path)
% LOAD_TX_TRUTH_JSON 读取由 gnss_tx 导出的 BER truth JSON 契约。

    raw = jsondecode(fileread(path));
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

    for k = 1:numel(required_fields)
        field_name = required_fields{k};
        if ~isfield(raw, field_name)
            error('GNSS_RX:MissingTruthField', ...
                'TX truth JSON 缺少字段：%s', field_name);
        end
    end

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
