#!/usr/bin/env bash
set -eo pipefail
overrides=$(env | cut -d= -f1 | grep '^SBATCH_' || true)
if [ -n "$overrides" ]; then printf 'REFUSE_SBATCH_ENV_OVERRIDES\n%s\n' "$overrides"; exit 64; fi
previous=$(sacct -n -X -P -j 231144 -o JobID,State,ExitCode | awk -F'|' '$1==231144 {print $2 "|" $3}')
test "$previous" = 'FAILED|1:0'
bash /data1/home/sunyiq/hpc_mailbox/inbox/kalmannet-wrr-closeout-20260928/submit_corrected_array_audit_002.sh 4285236a6728312e556665f131f56cf5452698d51265aa4cfafa763cbc7f24d0
