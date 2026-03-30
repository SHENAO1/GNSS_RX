#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/../.."

python3 -m venv --clear --system-site-packages .venv
source .venv/bin/activate

python3 -m pip install --upgrade pip
python3 -m pip install -r env/ubuntu/requirements.txt
python3 -m pip install -e .

echo ""
echo "[INFO] Running post-install quick check..."
if ! PYTHONPATH=src python3 scripts/quick_check.py; then
    echo ""
    echo "[ERROR] Post-install validation failed."
    echo "[ERROR] On Ubuntu, install system packages first:"
    echo "[ERROR]   sudo apt install -y gnuradio python3-gnuradio uhd-host python3-pip python3-venv"
    exit 1
fi

echo ""
echo "[OK] Virtual environment is ready."
echo "[OK] GNU Radio / UHD bindings are visible inside .venv."
echo "[OK] Project installed in editable mode."
echo "Activate with: source .venv/bin/activate"
