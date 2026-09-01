#!/bin/bash
# Read-only: locate the finished (Zhenjiang/Jiangyin) family's impact products.
set -o pipefail
ROOT=/data1/home/sunyiq/zhenjiang_oyv_v1
echo "--- top level ---"
ls -la "$ROOT" | head -50
echo "--- candidate files: ranking / cost_summary / verdict, <200k ---"
find "$ROOT" -maxdepth 3 -type f \( -name "*ranking*" -o -name "*cost_summary*" -o -name "*verdict*" -o -name "*impact*summary*" \) -size -200k 2>/dev/null | xargs -r ls -la | head -40
echo "=== DONE ==="