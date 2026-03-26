"""
utils/io.py — 文件读写工具函数

这个模块提供通用的文件 I/O 辅助函数，目前主要用于读取 YAML 配置文件。

背景知识：
  YAML 是一种人类友好的配置文件格式（类似 JSON 但更易读），本项目用它来
  存储接收机运行参数（采样率、中心频率等）。
"""

from __future__ import annotations

from pathlib import Path  # Python 标准库：面向对象的文件路径操作，比字符串更安全
from typing import Any    # 类型提示：表示"任意类型"，用于描述字典值类型

import yaml  # PyYAML 库：读取 .yaml / .yml 配置文件


def load_yaml_file(path: str | Path) -> dict[str, Any]:
    """从磁盘读取一个 YAML 文件，将其解析为 Python 字典后返回。

    典型使用场景：
        config_dict = load_yaml_file("configs/rx_b210.yaml")
        # config_dict 类似 {"sample_rate_hz": 4092000, "center_freq_hz": 1e8, ...}

    参数：
        path: YAML 文件的路径，可以是字符串（如 "configs/rx.yaml"）
              或 Path 对象（如 Path("configs/rx.yaml")）。

    返回：
        解析后的字典；如果 YAML 文件为空则返回空字典 {}。

    异常：
        ValueError: 当 YAML 文件顶层结构不是键值映射（dict）时抛出，
                    例如文件内容是一个列表 [1, 2, 3] 而不是 key: value。
    """
    yaml_path = Path(path)  # 统一转换为 Path 对象，方便后续操作

    # read_text 读取文件全部内容为字符串；yaml.safe_load 将 YAML 字符串
    # 解析为 Python 对象（通常是 dict）。
    # 使用 safe_load 而不是 load，可以防止 YAML 文件中潜在的恶意代码执行。
    data = yaml.safe_load(yaml_path.read_text(encoding="utf-8"))

    # 空文件或只有注释的文件，yaml.safe_load 返回 None，这里将其统一为空字典
    if data is None:
        return {}

    # 确保顶层是字典（键值对），而非列表或其他类型
    if not isinstance(data, dict):
        raise ValueError(f"YAML 文件中应为映射结构：{yaml_path}")

    return data


__all__ = ["load_yaml_file"]
