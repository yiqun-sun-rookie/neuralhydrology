#!/bin/bash
# read-only: progress counters + GPU index of the running E-arm DA tasks (246243_0 looks ~3x slower than _2)
cd /data1/home/sunyiq/ohn_da_vs_ar_531_20261021 || exit 1
date --iso-8601=seconds
for T in 0 1 2; do
  echo "=== 246243_$T ==="
  scontrol -d show job "246243_$T" 2>/dev/null | grep -oE '(JobState|RunTime|NodeList|GRES|TresPerNode)=[^ ]*' | tr '\n' ' '; echo
  for f in logs/ohn_p2_da-246243_$T.out logs/ohn_p2_da-246243_$T.err; do
    [ -f "$f" ] || continue
    echo "--- $f ($(stat -c %s $f) bytes)"
    tr '\r' '\n' < "$f" | grep -E '[0-9]+/[0-9]+ \[' | tail -2
    tr '\r' '\n' < "$f" | grep -E 'torch|cuda|samples=|EVAL_DONE' | tail -3
  done
done
echo "=== NODE ==="
sinfo -N -n ngu002 -h -O nodelist:10,statecompact:10,gres:14,gresused:24 2>&1
echo END_STATUS
