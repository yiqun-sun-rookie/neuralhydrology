#!/bin/bash
set -o pipefail
# read-only status of the background data build
ROOT=/data1/home/sunyiq/openhydronet_531_20261015
date --iso-8601=seconds
if pgrep -f "openhydronet_531_20261015/src/build_data.py" > /dev/null; then echo "BUILD RUNNING"; else echo "BUILD NOT RUNNING"; fi
tail -n 25 "$ROOT/logs/build_data.log" | cut -c1-240
du -sh "$ROOT/data" 2>/dev/null
ls "$ROOT/data/camels-updated-2025" 2>/dev/null
exit 0
