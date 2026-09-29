#!/usr/bin/env bash
set -eo pipefail
overrides=$(env | awk -F= '$1 ~ /^SBATCH_/ {print $1}')
if [ -n "$overrides" ]; then printf 'REFUSE_SBATCH_ENV_OVERRIDE\n%s\n' "$overrides"; exit 64; fi
bash /data1/home/sunyiq/hpc_mailbox/inbox/kalmannet-wrr-closeout-20260928/read_three_method_analysis.sh
state=$(sacct -n -X -P -j 231134 -o JobID,State | awk -F'|' '$1==231134 {print $2}')
case "$state" in
  COMPLETED|FAILED|CANCELLED*|TIMEOUT|OUT_OF_MEMORY|NODE_FAIL|PREEMPTED|BOOT_FAIL|DEADLINE)
    bash /data1/home/sunyiq/hpc_mailbox/inbox/kalmannet-wrr-closeout-20260928/submit_corrected_array_audit.sh 441dcba1d0e7dee5e5d1f8125c10220343e464c6bb0bd60e7c7eb6b39f91fa77 ;;
  *) echo "CORRECTED_AUDIT_NOT_SUBMITTED_PRECEDING_CPU_JOB=$state" ;;
esac
