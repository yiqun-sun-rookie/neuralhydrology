#!/bin/bash
set -eo pipefail
cd "$HOME/hpc_mailbox"
echo '=== input preflight ==='
PAYLOAD="$HOME/hpc_mailbox/inbox/id25-coarse-label-audit-20260922/payload"
test -f "$PAYLOAD/coarse_metadata.tar.gz"
test -f "$PAYLOAD/audit_metadata.py"
test -f "$PAYLOAD/audit_metadata.slurm"
sha256sum "$PAYLOAD/coarse_metadata.tar.gz" "$PAYLOAD/audit_metadata.py"
echo '=== isolated output root ==='
AUDIT_ROOT=/data1/home/sunyiq/id25_coarse_label_audit_20260922
if [ -e "$AUDIT_ROOT" ]; then
  echo "ROOT_ALREADY_EXISTS $AUDIT_ROOT"
  exit 1
fi
mkdir "$AUDIT_ROOT"
echo "$AUDIT_ROOT"
echo '=== submit ==='
out=$(sbatch "$PAYLOAD/audit_metadata.slurm" 2>&1)
echo "$out"
JID=$(echo "$out" | grep -oE 'Submitted batch job [0-9]+' | grep -oE '[0-9]+')
if [ -z "$JID" ]; then
  echo 'SUBMIT_FAILED'
  exit 1
fi
echo "JOB_ID=$JID"
squeue -j "$JID" -h -o '%i %T %R'
