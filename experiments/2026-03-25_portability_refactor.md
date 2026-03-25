# 路径可移植性改造记录

**日期**：2026-03-25
**分支/状态**：feat/portability（待 git 初始化）
**目标**：将项目中所有硬编码路径收敛到单一配置入口，使代码可直接分享给他人，无需逐个修改多个文件。

---

## 背景

原项目在以下 5 处硬编码了 VMware 共享目录路径（`C:\VMwareVirtualMachines\...` / `/mnt/hgfs/...`）：

| 文件 | 位置 |
|------|------|
| `matlab/scripts/run_capture_analysis.m` | `build_default_cfg()`，2 处 |
| `matlab/functions/find_latest_capture.m` | 默认参数，2 处 |
| `src/gnss_rx/runtime.py` | `DEFAULT_OUTPUT_BASE_DIR`，1 处 |

新用户拿到代码后，需要逐一找到并修改这些文件，容易遗漏。

额外问题：MATLAB 代码位于 Linux VM 的 git 仓库中，而 MATLAB 运行在 Windows 宿主机上，每次修改代码后需手动复制到共享文件夹，没有工具支持。

---

## 改动详情

### 1. `matlab/gnss_rx_user_paths.m.example`（新建）

用户本地路径配置的**模板文件**，纳入 git。用户首次使用时执行：

```bash
cp matlab/gnss_rx_user_paths.m.example matlab/gnss_rx_user_paths.m
# 编辑 GNSS_RX_DATA_DIR 填入本地路径
```

`gnss_rx_user_paths.m`（真正的本地配置）已加入 `.gitignore`，不会被提交。

---

### 2. `matlab/functions/gnss_rx_resolve_data_dir.m`（新建）

三级路径解析函数，供 MATLAB 端所有脚本调用：

```
优先级 1：matlab/gnss_rx_user_paths.m（用户本地配置文件）
优先级 2：环境变量 GNSS_RX_DATA_DIR
优先级 3：平台默认值（向后兼容，与改动前行为完全一致）
```

---

### 3. `matlab/scripts/run_capture_analysis.m`（修改）

将函数内 2 处平台判断块替换为：

```matlab
cfg.capture_root_dir = gnss_rx_resolve_data_dir();
```

---

### 4. `matlab/functions/find_latest_capture.m`（修改）

将默认参数中的平台判断块替换为：

```matlab
root_dir = gnss_rx_resolve_data_dir();
```

---

### 5. `src/gnss_rx/runtime.py`（修改）

支持环境变量覆盖 Python 侧默认路径：

```python
DEFAULT_OUTPUT_BASE_DIR = os.environ.get(
    "GNSS_RX_DATA_DIR",
    "/mnt/hgfs/GongXiangDocument/GNSS_RX_Data",
)
```

无 `GNSS_RX_DATA_DIR` 时行为与改动前完全一致。

---

### 6. `scripts/sync_matlab.sh`（新建）

将 `matlab/` 目录 rsync 同步到共享文件夹的一键脚本：

```bash
./scripts/sync_matlab.sh /mnt/hgfs/GongXiangDocument/GNSS_RX_matlab
```

解决"VM 里改了代码，MATLAB 读到的还是旧版本"问题。

---

### 7. `.gitignore`（修改）

新增：`matlab/gnss_rx_user_paths.m`

---

### 8. `README.md`（修改）

在"快速开始"前新增"首次配置"章节，说明：
1. 复制 `gnss_rx_user_paths.m.example` 并配置路径
2. 运行 `sync_matlab.sh` 同步代码到共享文件夹
3. 目录布局约定（`gnss_tx` 与 `GNSS_RX` 为兄弟目录）

---

## 测试结果

运行 `PYTHONPATH=src python3 -m unittest discover -s tests -v`：

```
11 passed, 1 skipped (需要 GNU Radio), 1 pre-existing failure
```

**预先存在的失败**：`test_resolve_capture_paths_uses_shared_folder_date_hierarchy`
原因：测试期望日期目录格式 `2026-03-23`（连字符），而 `runtime.py` 中 `DATE_DIRECTORY_FORMAT = "%Y_%m_%d"` 实际输出 `2026_03_23`（下划线）。此 bug 与本次改动无关，未修改。

---

## 新用户首次使用流程

```bash
# 1. 克隆仓库后，配置本地路径（只需做一次）
cp matlab/gnss_rx_user_paths.m.example matlab/gnss_rx_user_paths.m
# 编辑 gnss_rx_user_paths.m，填入你的数据目录

# 2. 同步 MATLAB 代码到宿主机可见位置（每次修改 .m 文件后执行）
./scripts/sync_matlab.sh /mnt/hgfs/GongXiangDocument/GNSS_RX_matlab

# 3. 在 MATLAB 中分析采集数据
result = run_capture_analysis();
```

---

## 已知后续工作

- `test_resolve_capture_paths_uses_shared_folder_date_hierarchy` 测试与实现不一致（日期格式 + 目录结构），应统一修正。
