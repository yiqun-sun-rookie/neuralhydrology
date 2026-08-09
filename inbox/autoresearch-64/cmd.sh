#!/bin/bash
set -o pipefail
cd ~/hpc_mailbox || exit 1

echo "=== SUBMIT NARROW-FIX VALIDATION ==="
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
echo "=== JOB STDOUT ==="
tail -160 "outbox/slurm_${JID}.out" 2>/dev/null
echo "=== JOB STDERR ==="
tail -120 "outbox/slurm_${JID}.err" 2>/dev/null
echo "=== PRESERVED EVIDENCE ==="
EVIDENCE=~/autoresearch64/runs/unified_autoresearch/dlopen_fix_validation_20260809_seq21/evidence
[ -f "$EVIDENCE/SUMMARY.json" ] && echo "summary=$EVIDENCE/SUMMARY.json"
[ -f "$EVIDENCE/MANIFEST.sha256" ] && echo "manifest=$EVIDENCE/MANIFEST.sha256"
[ -f "$EVIDENCE/ERROR.json" ] && cat "$EVIDENCE/ERROR.json"
