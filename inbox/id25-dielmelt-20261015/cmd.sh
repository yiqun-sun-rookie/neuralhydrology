#!/bin/bash
set -eo pipefail
root=/data1/home/sunyiq/id25_dielmelt_20261015_001
payload=/data1/home/sunyiq/hpc_mailbox/inbox/id25-dielmelt-20261015/payload/dielmelt_rds03_payload_v001.tar.gz
if [ -e "$root" ]; then echo EXISTING_ROOT_NO_OVERWRITE; exit 1; fi
if [ -n "$(squeue -h -u sunyiq -n id25_diel_261015 -o '%i')" ]; then echo ACTIVE_OWN_JOB_NO_DUPLICATE; exit 1; fi
printf '%s  %s\n' 'a646d9861240855243e8ed3d3162437038861ab2955dfba90ecdc95a50cfeafc' "$payload" | sha256sum -c -
mkdir -p "$root/logs" "$root/artifacts" "$root/inputs"
tar -xzf "$payload" -C "$root"
cp /data1/home/sunyiq/id25_regional_daily_storage_20261012_001/inputs/inputs.npz "$root/inputs/inputs.npz"
printf '%s  %s\n' 'b6e20598038eccf7a18753619342fdd48e90990f4cde4685eef42929978f2566' "$root/inputs/inputs.npz" | sha256sum -c -
out=$(sbatch "$root/code/hpc/regional_dielmelt_rds03_20261015.slurm" 2>&1)
printf '%s\n' "$out"
jid=$(printf '%s\n' "$out" | awk '/^Submitted batch job [0-9]+$/ {print $4}')
test -n "$jid"
printf '%s\n' "$jid" > "$root/job_id.txt"
printf '%s\t%s\t%s\n' "$(date -u +%FT%TZ)" "$jid" 'v001 fixed-weight forward; zero training' > "$root/submissions.tsv"
printf 'JOB_ID=%s\n' "$jid"
