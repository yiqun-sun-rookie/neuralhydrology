#!/bin/bash
set -euo pipefail

MAILBOX=/data1/home/sunyiq/hpc_mailbox
TEMPLATE="$MAILBOX/inbox/autoresearch-64/hbv_lite_unseen_64_confirmation_seq67.slurm"
PAYLOAD="$MAILBOX/inbox/autoresearch-64/payload/unseen64_builder_85ae470c_seq67.tar.gz"
PAYLOAD_SHA256=2633567e3193d9161c4d4394bf960b1ff53f0eb6f57f684e88d4b3ea722baf4e
RECEIPT=/tmp/autoresearch64-unseen64-seq67.receipt
LOCK=/tmp/autoresearch64-unseen64-seq67.lock

exec 9>"$LOCK"
flock 9
if [ -s "$RECEIPT" ]; then
  cat "$RECEIPT"
  exit 0
fi

ACTIVE=$(squeue -h -u sunyiq -n a64-hbv64-new -o '%i %T' || true)
if [ -n "$ACTIVE" ]; then
  echo "existing_active_job=$ACTIVE"
  exit 0
fi
HISTORICAL=$(sacct -u sunyiq -S 2026-08-11 -X -n -o JobIDRaw,JobName%24,State \
  | awk '$2 == "a64-hbv64-new" {print $1 " " $3}')
if [ -n "$HISTORICAL" ]; then
  echo "existing_accounting_job=$HISTORICAL"
  exit 0
fi

test "$(sha256sum "$PAYLOAD" | awk '{print $1}')" = "$PAYLOAD_SHA256"
bash -n "$TEMPLATE"
JOB_ID=$(sbatch --parsable "$TEMPLATE")
printf 'job_id=%s\nbuilder_payload_sha256=%s\n' "$JOB_ID" "$PAYLOAD_SHA256" > "$RECEIPT"
cat "$RECEIPT"
