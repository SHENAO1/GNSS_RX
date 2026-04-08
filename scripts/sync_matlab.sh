#!/usr/bin/env bash
# 将仓库中的 MATLAB 工作区镜像到共享目录。
#
# 用法：
#   ./scripts/sync_matlab.sh <目标目录>
#
# 示例：
#   ./scripts/sync_matlab.sh /mnt/hgfs/GongXiangDocument/GNSS_RX_matlab
#
# 运行后，共享目录中的受管 MATLAB 代码会与 GNSS_RX 仓库保持同步。
# 运行期产物（如 tx_truth.json）会被保留，不会因同步被删除。

set -euo pipefail

DEST="${1:-}"
if [ -z "$DEST" ]; then
    echo "用法：$0 <目标目录>" >&2
    echo "示例：$0 /mnt/hgfs/GongXiangDocument/GNSS_RX_matlab" >&2
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC="$SCRIPT_DIR/../matlab"
ROOT_ENTRY="$SRC/ber.m"
IQ_DIAGNOSTIC_ENTRY="$SRC/run_capture_iq_diagnostic.m"
CHUNK_BER_SELECTION_ENTRY="$SRC/run_ber_loopback_chunk_selection.m"
CHUNK_ANALYSIS_ENTRY="$SRC/run_capture_analysis_chunk_group.m"
CHUNK_GROUP_ENTRY="$SRC/run_ber_loopback_chunk_group.m"

echo "同步 MATLAB 工作区"
echo "  来源：$SRC"
echo "  目标：$DEST"
mkdir -p "$DEST"

rsync -av --delete "$SRC/functions/" "$DEST/functions/"
rsync -av --delete "$SRC/scripts/" "$DEST/scripts/"
rsync -av "$SRC/README.md" "$DEST/README.md"
rsync -av "$SRC/architecture.drawio" "$DEST/architecture.drawio"
rsync -av "$SRC/gnss_rx_user_paths.m.example" "$DEST/gnss_rx_user_paths.m.example"
rsync -av "$ROOT_ENTRY" "$DEST/ber.m"
rsync -av "$IQ_DIAGNOSTIC_ENTRY" "$DEST/run_capture_iq_diagnostic.m"
rsync -av "$CHUNK_BER_SELECTION_ENTRY" "$DEST/run_ber_loopback_chunk_selection.m"
rsync -av "$CHUNK_ANALYSIS_ENTRY" "$DEST/run_capture_analysis_chunk_group.m"
rsync -av "$CHUNK_GROUP_ENTRY" "$DEST/run_ber_loopback_chunk_group.m"
echo "同步完成。"
