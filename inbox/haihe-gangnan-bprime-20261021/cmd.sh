#!/bin/bash
# read-only status for haihe Gangnan B' jobs 245997,245998
ROOT=/data1/home/sunyiq/haihe_gangnan_bprime
date -Is
echo "=== SACCT ==="
sacct -X -n -P -j 245997,245998 --format=JobID,State,ExitCode,NodeList,Elapsed 2>&1
echo "=== SQUEUE ==="
squeue -j 245997,245998 -h -o '%i|%T|%R' 2>&1
echo "=== DONE ==="
find "$ROOT/done" -maxdepth 1 -name '*.ok' | wc -l
echo "=== SMOKE ==="
grep -hE 'SMOKE_OK|SMOKE_DONE|Error|error|Traceback' "$ROOT"/logs/smoke_245970.out "$ROOT"/logs/smoke_245970.err 2>/dev/null | tail -5
echo "=== AGG ==="
[ -f "$ROOT/results/bprime_peryear.csv" ] && cat "$ROOT/results/bprime_peryear.csv"
echo "=== FAILED TASK ERR TAILS ==="
for f in $(grep -l -E 'Traceback|Error|STALE_RUN|AMBIGUOUS|NO_TASK' "$ROOT"/logs/train_245997_*.err 2>/dev/null | head -3); do echo "--- $f"; tail -4 "$f"; done
echo END_STATUS
