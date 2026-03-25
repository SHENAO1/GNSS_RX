#!/usr/bin/env bash
# 将 matlab/ 目录同步到共享文件夹中的 MATLAB 工作区。
#
# 用法：
#   ./scripts/sync_matlab.sh <目标目录>
#
# 示例：
#   ./scripts/sync_matlab.sh /mnt/hgfs/GongXiangDocument/GNSS_RX_matlab
#
# 运行后，在宿主机 MATLAB 中 addpath 对应的 Windows 路径，
# 或直接打开 scripts/run_capture_analysis.m 即可使用最新代码。

set -euo pipefail

DEST="${1:-}"
if [ -z "$DEST" ]; then
    echo "用法：$0 <目标目录>" >&2
    echo "示例：$0 /mnt/hgfs/GongXiangDocument/GNSS_RX_matlab" >&2
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC="$SCRIPT_DIR/../matlab"

echo "同步 MATLAB 工作区"
echo "  来源：$SRC"
echo "  目标：$DEST"
rsync -av --delete "$SRC/" "$DEST/"
echo "同步完成。"
