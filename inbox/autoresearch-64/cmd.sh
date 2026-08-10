#!/bin/bash
set -uo pipefail

cd /data1/home/sunyiq/hpc_mailbox || exit 1
ATTEMPT=/data1/home/sunyiq/autoresearch64/runs/unified_autoresearch/hbv_lite_64_hpc_reproduction_20260810_seq46
JID=202319

echo "=== EXACT JOB ACCOUNTING ==="
sacct -j "$JID" -X --format=JobID%12,JobName%22,NodeList%9,State%14,ExitCode%8,Elapsed%10

echo "=== SAME-NAME JOBS ==="
sacct -S 2026-08-10T17:20:00 -X -n -o JobID,JobName%24,State,ExitCode,Start,End | grep 'a64-hbv64-gate3' || true

echo "=== EXACT SLURM LOG FILES ==="
for path in "outbox/slurm_${JID}.out" "outbox/slurm_${JID}.err"; do
  if [ -e "$path" ]; then
    stat -c '%n|inode=%i|bytes=%s|mtime=%y' "$path"
    tail -80 "$path"
  else
    echo "MISSING $path"
  fi
done

echo "=== ATTEMPT AND EVIDENCE FILES ==="
if [ -d "$ATTEMPT" ]; then
  find "$ATTEMPT/evidence" -maxdepth 1 -type f -printf '%f|bytes=%s|mtime=%TY-%Tm-%TdT%TH:%TM:%TS\n' | sort
else
  echo "MISSING_ATTEMPT $ATTEMPT"
fi

for path in \
  "$ATTEMPT/evidence/TARGETED_GATE.json" \
  "$ATTEMPT/evidence/FULL_GATE.json"; do
  if [ -f "$path" ]; then
    echo "--- $path"
    cat "$path"
  else
    echo "MISSING $path"
  fi
done

echo "=== TARGETED GATE OUTPUT TAIL ==="
tail -120 "$ATTEMPT/evidence/TARGETED_GATE_STDOUT.txt" 2>/dev/null || true

echo "=== RUNNER PROCESS AND SEQUENCE RECORDS ==="
pgrep -af 'hpc_runner_active' || true
grep -n 'channel=autoresearch-64 seq=46' runner2.log | tail -20 || true

echo "=== MAILBOX LOG STATUS ==="
git status --porcelain -- "outbox/slurm_${JID}.out" "outbox/slurm_${JID}.err" || true
exit 0
