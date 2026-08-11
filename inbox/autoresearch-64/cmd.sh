#!/bin/bash
set -uo pipefail

MAILBOX=/data1/home/sunyiq/hpc_mailbox
ROOT=/data1/home/sunyiq/autoresearch64
RECEIPT=/tmp/autoresearch64-unseen64-seq65.receipt
LOCK=/tmp/autoresearch64-unseen64-seq65.lock
SUBMIT_SCRIPT=/tmp/autoresearch64-unseen64-seq65.slurm
PAYLOAD="$MAILBOX/inbox/autoresearch-64/payload/unseen64_builder_85ae470c_seq65.tar.gz"
ATTEMPT="$ROOT/runs/unified_autoresearch/hbv_lite_unseen_64_confirmation_20260811_seq65"

echo "=== RUNNER PROCESSES ==="
pgrep -af hpc_runner_active || true
echo "=== SUBMISSION ARTIFACTS ==="
for path in "$RECEIPT" "$LOCK" "$SUBMIT_SCRIPT" "$PAYLOAD"; do
  if [ -e "$path" ]; then
    stat -c '%n size=%s mode=%a mtime=%y' "$path"
  else
    echo "MISSING $path"
  fi
done
if [ -s "$RECEIPT" ]; then
  echo "=== RECEIPT ==="
  cat "$RECEIPT"
fi
echo "=== FETCHED SOURCE IDENTITY ==="
cd "$MAILBOX"
git rev-parse FETCH_HEAD 2>&1 || true
git ls-remote origin refs/heads/codex/unified-autoresearch-vertical 2>&1 || true
echo "=== ACTIVE MATCHING JOBS ==="
squeue -u sunyiq -o '%.18i %.24j %.10T %.10M %.30R' | grep -E 'JOBID|a64-hbv64-new' || true
echo "=== ACCOUNTING MATCHING JOBS ==="
sacct -u sunyiq -S 2026-08-11 -X -n -o JobID,JobName%24,State,ExitCode,Elapsed,Start,End \
  | grep 'a64-hbv64-new' || true
echo "=== ATTEMPT ROOT ==="
if [ -e "$ATTEMPT" ]; then
  stat -c '%n size=%s mode=%a mtime=%y' "$ATTEMPT"
  find "$ATTEMPT" -maxdepth 2 -type f -printf '%p size=%s mtime=%TY-%Tm-%TdT%TH:%TM:%TS\n' | sort | tail -30
else
  echo "MISSING $ATTEMPT"
fi
