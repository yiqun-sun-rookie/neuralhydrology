#!/bin/bash
set -eo pipefail
root=/data1/home/sunyiq/id25_daily_lstm_matched_20261015_001
payload=/data1/home/sunyiq/hpc_mailbox/inbox/id25-lstm-matched-20261015/payload/daily_lstm_matched_b03_payload_v001.tar.gz
if [ -e "$root" ]; then echo EXISTING_ROOT_NO_OVERWRITE; exit 1; fi
if [ -n "$(squeue -h -u sunyiq -n id25_lstm_m_261015 -o '%i')" ]; then echo ACTIVE_OWN_JOB_NO_DUPLICATE; exit 1; fi
printf '%s  %s\n' '28af259ae9b97ec9a6afbcb0bbf34248203e7b89511d1825ffdb19b048311a83' "$payload" | sha256sum -c -
mkdir -p "$root/logs" "$root/artifacts" "$root/inputs"
tar -xzf "$payload" -C "$root"
cp /data1/home/sunyiq/id25_regional_daily_storage_20261012_001/inputs/inputs.npz "$root/inputs/inputs.npz"
printf '%s  %s\n' 'b6e20598038eccf7a18753619342fdd48e90990f4cde4685eef42929978f2566' "$root/inputs/inputs.npz" | sha256sum -c -
out=$(sbatch "$root/code/hpc/daily_lstm_matched_b03_20261015.slurm" 2>&1)
printf '%s\n' "$out"
jid=$(printf '%s\n' "$out" | awk '/^Submitted batch job [0-9]+$/ {print $4}')
test -n "$jid"
printf '%s\n' "$jid" > "$root/job_id.txt"
printf '%s\t%s\t%s\n' "$(date -u +%FT%TZ)" "$jid" 'v001 single B03 fit, fixed reviewed budget' > "$root/submissions.tsv"
printf 'JOB_ID=%s\n' "$jid"
