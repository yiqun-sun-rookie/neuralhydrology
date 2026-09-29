#!/usr/bin/env bash
set -eo pipefail
payload_sha=${1:-}
if [ "$#" -ne 1 ] || ! [[ "$payload_sha" =~ ^[0-9a-f]{64}$ ]]; then echo INVALID_PACKAGE_PIN; exit 64; fi
overrides=$(env | cut -d= -f1 | grep '^SBATCH_' || true)
if [ -n "$overrides" ]; then printf 'REFUSE_SBATCH_ENV_OVERRIDES\n%s\n' "$overrides"; exit 64; fi
previous=$(sacct -n -X -P -j 231169 -o JobID,State,ExitCode | awk -F'|' '$1==231169 {print $2 "|" $3}')
test "$previous" = 'FAILED|1:0'
bash /data1/home/sunyiq/hpc_mailbox/inbox/kalmannet-wrr-closeout-20260928/submit_corrected_array_audit_003.sh "$payload_sha"
