# GNSS_RX 测试目录

本目录存放 GNSS_RX 的 Python 单元测试。修改 `src/` 或 `scripts/` 后，建议至少跑一遍这里的测试。

---

## 一次跑完整套测试

```bash
cd /home/shen/projects/GNSS_RX
PYTHONPATH=src python3 -m unittest discover -s tests -v
```

---

## 按文件运行

```bash
cd /home/shen/projects/GNSS_RX

PYTHONPATH=src python3 -m unittest tests.test_writer -v
PYTHONPATH=src python3 -m unittest tests.test_runtime -v
PYTHONPATH=src python3 -m unittest tests.test_metadata -v
PYTHONPATH=src python3 -m unittest tests.test_record_rx -v
PYTHONPATH=src python3 -m unittest tests.test_flowgraph -v
```

---

## 测试覆盖范围

| 测试文件 | 覆盖范围 |
|----------|----------|
| `test_writer.py` | SC16 写盘格式、文件大小、字节序 |
| `test_runtime.py` | 配置加载、路径解析、stem 命名、PRN 范围校验、`all_prns` 模式、`prn_all32` stem 标签 |
| `test_metadata.py` | JSON sidecar 字段、`all_prns`/`prn_ids` 序列化 |
| `test_record_rx.py` | `record_rx.py` CLI 参数解析与 dry-run 行为 |
| `test_flowgraph.py` | GNU Radio 流图组装（需 gnuradio 可导入，否则跳过） |

---

## 何时跑测试

- 改了 `runtime.py`（配置加载、路径拼接）
- 改了 `metadata.py`（JSON 字段）
- 改了 `writer.py`（SC16 写盘格式）
- 改了 `record_rx.py` 的 CLI 行为
- 提交前快速确认无回归
