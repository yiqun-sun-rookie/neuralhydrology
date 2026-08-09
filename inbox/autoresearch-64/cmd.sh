#!/bin/bash
set -o pipefail
cd ~/hpc_mailbox || exit 1

echo "=== SUBMIT ONE BOUNDED DIAGNOSTIC BATCH ==="
JID=$(sbatch --parsable inbox/autoresearch-64/dlopen_probe.slurm 2>&1)
STATUS=$?
echo "sbatch_exit=$STATUS jobid=$JID"
[ "$STATUS" -eq 0 ] || exit "$STATUS"

echo "=== WAIT AT MOST 50 SECONDS ==="
for i in $(seq 1 10); do
  STATE=$(squeue -j "$JID" -h -o "%T" 2>/dev/null | head -1)
  [ -z "$STATE" ] && break
  echo "t=$((i * 5))s state=$STATE"
  sleep 5
done

echo "=== SCHEDULER RECORD ==="
sacct -j "$JID" -X --format=JobID%12,JobName%20,State%14,ExitCode%8,Elapsed%10 2>&1

echo "=== JOB STDOUT TAIL ==="
tail -80 "outbox/slurm_${JID}.out" 2>/dev/null
echo "=== JOB STDERR TAIL ==="
tail -80 "outbox/slurm_${JID}.err" 2>/dev/null

echo "=== PRESERVED EVIDENCE STATUS ==="
EVIDENCE=~/autoresearch64/runs/unified_autoresearch/dlopen_dependency_probe_20260809_seq19
if [ -f "$EVIDENCE/SUMMARY.json" ]; then
  grep -E '"diagnostic_complete"|"package"|"process_exit_code"|"ctypes_dlopen_denied"' \
    "$EVIDENCE/SUMMARY.json" | head -40
  echo "summary=$EVIDENCE/SUMMARY.json"
  echo "manifest=$EVIDENCE/MANIFEST.sha256"
elif [ -f "$EVIDENCE/ERROR.json" ]; then
  cat "$EVIDENCE/ERROR.json"
else
  echo "diagnostic still pending or failed before evidence-root creation"
fi
