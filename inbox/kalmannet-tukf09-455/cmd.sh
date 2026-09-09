#!/bin/bash
# TUKF09-455 v2r13: measure the real download rate. Read only.
set -o pipefail
ROOT=/data1/home/sunyiq/kalmannet_tukf09_455_basin_zero_validation_target_variance_revision_v1_a800_exclusive_v2r13_20260909
echo "TIME=$(date -Is)"
PID=$(pgrep -f "pip download" | head -1); echo "PIP_PID=${PID:-none}"
[ -n "$PID" ] && ps -o pid,etime,time,stat -p "$PID" --no-headers 2>&1
[ -n "$PID" ] && grep -E "^(read_bytes|write_bytes)" /proc/$PID/io 2>/dev/null
A=$(du -sb "$ROOT"/offline_inputs_v2r13.pending.* 2>/dev/null | cut -f1)
B=$(du -sb /tmp/pip-unpack-* 2>/dev/null | awk "{s+=\$1} END {print s+0}")
sleep 60
C=$(du -sb "$ROOT"/offline_inputs_v2r13.pending.* 2>/dev/null | cut -f1)
D=$(du -sb /tmp/pip-unpack-* 2>/dev/null | awk "{s+=\$1} END {print s+0}")
echo "pending ${A:-0} -> ${C:-0}  delta $(( ${C:-0} - ${A:-0} )) bytes / 60 s"
echo "piptmp  ${B:-0} -> ${D:-0}  delta $(( ${D:-0} - ${B:-0} )) bytes / 60 s"
echo "=== download.pytorch.org, 20 MB range ==="
timeout 60 curl -sS -o /dev/null -m 55 -r 0-20000000 -w "code=%{http_code} got=%{size_download}B speed=%{speed_download}B/s time=%{time_total}s\n" "https://download.pytorch.org/whl/cu121/torch-2.2.2%2Bcu121-cp311-cp311-linux_x86_64.whl" 2>&1
echo TUKF09_455_V2R13_RATE_PROBE
