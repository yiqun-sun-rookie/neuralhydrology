#!/usr/bin/env bash
set -eo pipefail
parent=/data1/home/sunyiq/kalmannet_wrr_closeout_20260928_v1
root="$parent/plain_preflight_v1"
payload=/data1/home/sunyiq/hpc_mailbox/inbox/kalmannet-wrr-closeout-20260928/plain_preflight_payload_v1.tar.gz
test -d "$parent"
test ! -e "$root"
echo '8169095afd51875b2f9baaf623e5e80363e057a3dc7480cab5a4ef6bb28198f5  '"$payload" | sha256sum -c -
mkdir "$root"
tar -xzf "$payload" -C "$root"
cd "$root"
sha256sum -c package_files.sha256 >/dev/null
echo 'ALL_PACKAGE_FILES_VERIFIED'
mkdir logs numerical_impact/runs
submission=$(sbatch plain_preflight.slurm 2>&1)
echo "$submission"
job=$(printf '%s\n' "$submission" | sed -nE 's/^Submitted batch job ([0-9]+)$/\1/p')
test -n "$job"
printf '%s\n' "$job" > "$parent/plain_preflight_jobid.txt"
echo "PLAIN_SINGLE_SUBMISSION=$job"
squeue -h -j "$job" -o '%i|%j|%T|%P|%R'
