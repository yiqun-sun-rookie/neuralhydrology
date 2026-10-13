#!/bin/bash
set -eo pipefail
root=/data1/home/sunyiq/id25_regional_snowloss_20261013_001
parent=/data1/home/sunyiq/id25_regional_daily_storage_20261012_001
payload=/data1/home/sunyiq/hpc_mailbox/inbox/id25-snowloss-20261013/payload/snowloss_payload_v001.tar.gz
if [ -e "$root" ]; then echo "EXISTING_ROOT_NO_OVERWRITE $root"; exit 1; fi
test -f "$parent/inputs/inputs.npz"
test -f "$parent/inputs/input_receipt.json"
printf '%s  %s\n' '35de45524ff7a69da4fbac886140c051a878a7f746ca326eff4ce0ca5798cbee' "$payload" | sha256sum -c -
mkdir -p "$root/logs" "$root/inputs" "$root/artifacts"
tar -xzf "$payload" -C "$root"
ln -s "$parent/inputs/inputs.npz" "$root/inputs/inputs.npz"
ln -s "$parent/inputs/input_receipt.json" "$root/inputs/input_receipt.json"
cd "$root"
out=$(sbatch "$root/code/hpc/regional_daily_storage_rds02_snowloss01_20261013.slurm" 2>&1)
printf '%s\n' "$out"
jid=$(printf '%s\n' "$out" | sed -n 's/^Submitted batch job \([0-9][0-9]*\)$/\1/p')
test -n "$jid"
printf '%s\n' "$jid" > "$root/job_id.txt"
printf '%s\t%s\t%s\n' "$(date -u +%FT%TZ)" "$jid" 'v001 initial calibration' > "$root/submissions.tsv"
printf 'CAMPAIGN_ROOT=%s\nJOB_ID=%s\n' "$root" "$jid"
