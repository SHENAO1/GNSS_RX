# GNSS_RX 配置目录

本目录存放接收端运行时 YAML 配置文件。配置文件通过 `--config` 参数传给 `scripts/record_rx.py`
或 `scripts/gen_synthetic_capture.py`，CLI 参数可覆盖任意字段。

---

## 配置文件一览

| 文件 | 模式 | 说明 |
|------|------|------|
| `rx_prn1_capture.yaml` | 单星 PRN1 | 默认基线配置，标准单星零中频采集 |
| `rx_prn1_sn193982.yaml` | 单星 PRN1 | 固定设备 serial=193982，双 USRP 环境避免选错设备 |
| `rx_all32prn.yaml` | 32星叠加 | 对应 TX 端 `tx_b210_all32prn.yaml` 或 `tx_b210_prn_subset.yaml`，采集多星叠加信号供 MATLAB 多星扫描 |

---

## 关键字段说明

| 字段 | 说明 | 示例值 |
|------|------|--------|
| `usrp_addr` | UHD 设备地址，`type=b200` 自动发现，或 `serial=...` 固定设备 | `"type=b200"` |
| `center_freq_hz` | 中心频率（Hz），须与 TX 端一致 | `100000000.0` |
| `sample_rate_hz` | 采样率（Hz） | `4092000.0` |
| `rx_gain_db` | 接收增益（dB） | `20.0` |
| `bandwidth_hz` | RF 带宽（Hz），通常与 `sample_rate_hz` 相同 | `4092000.0` |
| `antenna` | 天线端口（B210 接收用 "RX2"） | `"RX2"` |
| `duration_s` | 录制时长（秒） | `2.0` |
| `output_base_dir` | 输出根目录，可被 `--output-base-dir` 覆盖 | `"/mnt/hgfs/..."` |
| `prn_id` | 目标 PRN（单星模式，1~32）；`all_prns: true` 时仅作兼容保留 | `1` |
| `all_prns` | `true` = 多星叠加模式，元数据记录 PRN 1~32 全部 | `false` |
| `tx_profile_reference` | 对应的 TX 配置文件路径（写入 JSON 元数据，便于回溯） | `"../gnss_tx/configs/..."` |

---

## 如何使用配置文件

### 标准单星采集

```bash
cd /home/shen/projects/GNSS_RX

# 干运行（验证配置）
PYTHONPATH=src python3 scripts/record_rx.py \
    --config configs/rx_prn1_capture.yaml --dry-run

# 正式采集
PYTHONPATH=src python3 scripts/record_rx.py \
    --config configs/rx_prn1_capture.yaml

# 临时切换目标 PRN（不改 YAML）
PYTHONPATH=src python3 scripts/record_rx.py \
    --config configs/rx_prn1_capture.yaml --prn-id 7
```

### 32星或子集叠加采集

```bash
# 干运行
PYTHONPATH=src python3 scripts/record_rx.py \
    --config configs/rx_all32prn.yaml --dry-run

# 正式采集（TX 端运行 tx_b210_all32prn.yaml 或 --prn-ids 子集）
PYTHONPATH=src python3 scripts/record_rx.py \
    --config configs/rx_all32prn.yaml
```

> TX 端发射 PRN 子集（如 `--prn-ids 1,5,10,15`）时，RX 端仍使用 `rx_all32prn.yaml` 采集；
> MATLAB 多星扫描结果中只有发射的那几颗 PRN 会出现捕获峰，可用于验证收发链路对齐。

### OTA 空收（固定设备序列号）

```bash
PYTHONPATH=src python3 scripts/record_rx.py \
    --config configs/rx_prn1_sn193982.yaml
```

### 无硬件合成数据生成

```bash
# 单星合成（PRN 1，默认）
PYTHONPATH=/home/shen/projects/gnss_tx/src:src \
    python3 scripts/gen_synthetic_capture.py \
    --config configs/rx_prn1_capture.yaml --snr-db 10

# 指定 PRN 合成
PYTHONPATH=/home/shen/projects/gnss_tx/src:src \
    python3 scripts/gen_synthetic_capture.py \
    --config configs/rx_prn1_capture.yaml --prn-id 7 --snr-db 10

# 32星叠加合成
PYTHONPATH=/home/shen/projects/gnss_tx/src:src \
    python3 scripts/gen_synthetic_capture.py \
    --config configs/rx_all32prn.yaml --all-prns --snr-db 10
```

---

## 常改字段

修改后推荐先做 dry-run 验证：

```bash
PYTHONPATH=src python3 scripts/record_rx.py \
    --config configs/rx_prn1_capture.yaml --dry-run
```

也可以直接用 CLI 参数临时覆盖，不修改 YAML：

```bash
PYTHONPATH=src python3 scripts/record_rx.py \
    --duration 5 --rx-gain 30 --output-base-dir /tmp/gnss_test
```
