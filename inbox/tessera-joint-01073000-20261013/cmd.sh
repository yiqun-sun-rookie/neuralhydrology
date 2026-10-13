#!/bin/bash
set -eo pipefail
ROOT=/data1/home/sunyiq/tessera_joint_01073000_20261013_001
PAYLOAD="$HOME/hpc_mailbox/inbox/tessera-joint-01073000-20261013/payload/pilot_v1.tar.gz"
test ! -e "$ROOT" || { echo ROOT_ALREADY_EXISTS_REFUSE_OVERWRITE; exit 1; }
printf '%s  %s\n' 533a1934c368c4ab057730943560f7d8117034f97f786d16ba5234e29e90fc7f "$PAYLOAD" | sha256sum -c -
mkdir "$ROOT"
mkdir "$ROOT/logs"
tar -xzf "$PAYLOAD" -C "$ROOT"
cd "$ROOT"
sha256sum -c MANIFEST.sha256 > logs/deployment_input_verification.txt
mkdir submission_once
/usr/local/globle/softs/slurm/19.05.4.1/bin/sbatch src/tessera_joint/hpc/temporal_01073000.slurm > submission_receipt.txt 2>&1
cat submission_receipt.txt
JID=$(awk '/Submitted batch job [0-9]+/ {print $NF}' submission_receipt.txt)
case "$JID" in ''|*[!0-9]*) echo SUBMISSION_NOT_CONFIRMED_INSPECT_BEFORE_RETRY; exit 1;; esac
printf '%s' "$JID" > job_id.txt
echo "EXPERIMENT_ROOT=$ROOT"
echo "JOB_ID=$JID"
squeue -j "$JID" -h -o '%i %j %T %R' || true
echo SUBMISSION_CONFIRMED
