# GNSS_RX 测试目录

这里存放 `GNSS_RX` 的 Python 单元测试和集成测试入口。修改 `src/` 或
`scripts/` 后，建议至少跑一遍这里的测试。

## 一次跑完整套测试

```bash
cd /home/shen/projects/GNSS_RX
PYTHONPATH=src python3 -m unittest discover -s tests -v
```

## 按文件运行

```bash
cd /home/shen/projects/GNSS_RX
PYTHONPATH=src python3 -m unittest tests.test_writer -v
PYTHONPATH=src python3 -m unittest tests.test_runtime -v
PYTHONPATH=src python3 -m unittest tests.test_metadata -v
PYTHONPATH=src python3 -m unittest tests.test_record_rx -v
PYTHONPATH=src python3 -m unittest tests.test_flowgraph -v
```

## 什么时候跑这些测试

- 改了 `runtime.py`、配置加载或路径拼接逻辑
- 改了 SC16 写盘格式
- 改了 JSON sidecar 字段
- 改了 `record_rx.py` 的命令行行为
- 提交前想快速确认当前 Python 版本没有回归
