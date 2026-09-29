#!/usr/bin/env bash
set -eo pipefail
parent=/data1/home/sunyiq/kalmannet_wrr_closeout_20260928_v1
inbox=/data1/home/sunyiq/hpc_mailbox/inbox/kalmannet-wrr-closeout-20260928
bash "$inbox/read_domain_diagnostic.sh"
job=$(cat "$parent/domain_diagnostic_jobid_001.txt")
if ! [[ "$job" =~ ^[0-9]+$ ]]; then echo INVALID_DIAGNOSTIC_JOB; exit 64; fi
state=$(sacct -n -X -P -j "$job" -o State)
case "$state" in
 COMPLETED|FAILED|CANCELLED*|TIMEOUT|OUT_OF_MEMORY|NODE_FAIL|PREEMPTED|BOOT_FAIL|DEADLINE)
  echo "DIAGNOSTIC_TERMINAL=$job:$state"
  echo SEVEN_ORIGINALS_ALREADY_INDEPENDENTLY_ACCEPTED_DIAGNOSTIC_DOES_NOT_ADMIT_EXCLUDED_CASES
  bash "$inbox/submit_corrected_fourteen.sh" 271fe17b48818f793483f44633642f6ee50a9aed7ad32780149a4eead912988c
  ;;
 *) echo "CORRECTED_FOURTEEN_NOT_SUBMITTED_DIAGNOSTIC_STILL_ACTIVE=$state" ;;
esac
