#!/bin/bash
# TUKF09-455 v2r13: is pip actually transferring bytes. Read only.
set -o pipefail
ROOT=/data1/home/sunyiq/kalmannet_tukf09_455_basin_zero_validation_target_variance_revision_v1_a800_exclusive_v2r13_20260909
echo "TIME=$(date -Is)"
PID=$(pgrep -f "pip download" | head -1)
echo "PIP_PID=${PID:-<none>}"
if [ -n "$PID" ]; then
  ps -o pid,etime,time,stat,rss,wchan:20 -p "$PID" 2>&1
  echo "--- io ---"; cat /proc/$PID/io 2>/dev/null | head -6
  echo "--- open files (non-lib) ---"; ls -l /proc/$PID/fd 2>/dev/null | grep -vE "\.so|/dev/|pipe:|anon_inode" | head -10
  echo "--- tcp ---"; ss -tnp 2>/dev/null | grep -w "$PID" | head -5 || cat /proc/$PID/net/tcp 2>/dev/null | head -3
  echo "--- cwd/tmp ---"; readlink /proc/$PID/cwd 2>/dev/null; echo "TMPDIR=$(tr \"\0\" \"\n\" < /proc/$PID/environ 2>/dev/null | grep ^TMPDIR= || echo unset)"
fi
echo "--- pip temp dirs ---"
du -sh /tmp/pip-* 2>/dev/null | tail -5 || echo "no /tmp/pip-*"
du -sh ${TMPDIR:-/tmp}/pip-* 2>/dev/null | tail -5
find /data1/home/sunyiq -maxdepth 2 -name "pip-*" -newermt "-1 hour" 2>/dev/null | head -5
echo "--- wheelhouse ---"
ls -la "$ROOT"/offline_inputs_v2r13.pending.*/wheelhouse/ 2>&1 | head -8
echo "--- what is it downloading (first lines of the lock) ---"
head -8 "$ROOT/bundle/kalmannet/hpc/tukf09_455_basin_revision_a800_exclusive_v2r13/runtime-binary.lock"
echo "--- throughput probe: fetch a 10 MB wheel head ---"
timeout 40 curl -sS -o /dev/null -m 35 -w "code=%{http_code} size=%{size_download} speed=%{speed_download}B/s time=%{time_total}s\n" https://files.pythonhosted.org/packages/source/n/numpy/numpy-1.26.4.tar.gz 2>&1
echo TUKF09_455_V2R13_PIP_DIAGNOSTIC
