from __future__ import annotations

from pathlib import Path
from typing import Any

import yaml


def load_yaml_file(path: str | Path) -> dict[str, Any]:
    yaml_path = Path(path)
    data = yaml.safe_load(yaml_path.read_text(encoding="utf-8"))
    if data is None:
        return {}
    if not isinstance(data, dict):
        raise ValueError(f"YAML 文件中应为映射结构：{yaml_path}")
    return data


__all__ = ["load_yaml_file"]
