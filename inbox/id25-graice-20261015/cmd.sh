#!/bin/bash
set -eo pipefail
root=/data1/home/sunyiq/id25_graice_lstmnosif_20261015_001
payload=/data1/home/sunyiq/hpc_mailbox/inbox/id25-graice-20261015/payload/graice_lstmnosif_b02_payload_v001.tar.gz
if [ -e "$root" ]; then echo EXISTING_ROOT_NO_OVERWRITE; exit 1; fi
printf '%s  %s
' '3b7a39959f5fe32b6627f90b4cacf68c9184e178eca7ea69d1884c46a68f155d' "$payload" | sha256sum -c -
mkdir -p "$root/logs" "$root/artifacts"
tar -xzf "$payload" -C "$root"
cd "$root"
out=$(sbatch "$root/code/hpc/graice_lstmnosif_b02_20261015.slurm" 2>&1)
printf '%s
' "$out"
jid=$(printf '%s
' "$out" | awk '/^Submitted batch job [0-9]+$/ {print $4}')
test -n "$jid"
printf '%s
' "$jid" > "$root/job_id.txt"
printf '%s	%s	%s
' "$(date -u +%FT%TZ)" "$jid" 'v001 initial B02 main comparison' > "$root/submissions.tsv"
printf 'CAMPAIGN_ROOT=%s
JOB_ID=%s
' "$root" "$jid"
