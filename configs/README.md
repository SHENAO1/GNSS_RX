# GNSS_RX 配置目录

这个目录存放接收端运行时 YAML 配置文件。配置本身不能单独“运行”，但所有
采集命令都会通过 `--config` 读取这里的文件。

## 当前配置文件

- `rx_prn1_capture.yaml`
  默认基线配置，适合标准 PRN1 零中频采集。
- `rx_prn1_sn193982.yaml`
  固定到 `serial=193982` 的 OTA 配置，避免双 USRP 环境选错设备。

## 如何使用配置文件

标准采集：

```bash
cd /home/shen/projects/GNSS_RX
PYTHONPATH=src python3 scripts/record_rx.py --config configs/rx_prn1_capture.yaml
```

OTA 空收：

```bash
cd /home/shen/projects/GNSS_RX
PYTHONPATH=src python3 scripts/record_rx.py --config configs/rx_prn1_sn193982.yaml
```

无硬件生成合成数据时，也可以复用同一个配置：

```bash
cd /home/shen/projects/GNSS_RX
PYTHONPATH=/home/shen/projects/gnss_tx/src:src \
  python3 scripts/gen_synthetic_capture.py \
  --config configs/rx_prn1_sn193982.yaml \
  --snr-db 10 \
  --duration 2
```

## 常改字段

- `usrp_addr`：选择设备，可写 `type=b200`、`serial=...`
- `center_freq_hz`：中心频率
- `sample_rate_hz`：采样率
- `rx_gain_db`：接收增益
- `duration_s`：录制时长
- `output_base_dir`：输出根目录

修改配置后，推荐先做一次 dry-run：

```bash
cd /home/shen/projects/GNSS_RX
PYTHONPATH=src python3 scripts/record_rx.py --config configs/rx_prn1_capture.yaml --dry-run
```
