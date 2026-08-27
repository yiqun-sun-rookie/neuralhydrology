#!/bin/bash
set -o pipefail
ROOT=/data1/home/sunyiq/kalmannet_tukf24_20260827
echo "=== LOG FILES ==="
ls -la $ROOT/logs/ 2>/dev/null | head -8 || true
echo "=== ERR TAIL ==="
tail -c 4000 $ROOT/logs/tukf24_anchor_215261*.err 2>/dev/null || true
echo "=== OUT TAIL ==="
tail -c 1500 $ROOT/logs/tukf24_anchor_215261*.out 2>/dev/null || true
