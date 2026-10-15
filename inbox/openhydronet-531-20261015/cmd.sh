#!/bin/bash
set -o pipefail
# read-only: ID18 data build status
ROOT=/data1/home/sunyiq/openhydronet_531_20261015
date --iso-8601=seconds
if pgrep -f "src/build_id18_data.py" > /dev/null; then echo "BUILD RUNNING"; else echo "BUILD NOT RUNNING"; fi
tail -n 12 "$ROOT/logs/build_id18.log" | cut -c1-220
du -sh "$ROOT/data/id18_maurer" 2>/dev/null
ls "$ROOT/data/id18_maurer" 2>/dev/null
exit 0
