#!/usr/bin/env bash
set -eo pipefail
parent=/data1/home/sunyiq/kalmannet_wrr_closeout_20260928_v1
root="$parent/adaptive_preflight_v1"
payload=/data1/home/sunyiq/hpc_mailbox/inbox/kalmannet-wrr-closeout-20260928/adaptive_preflight_payload_v1.tar.gz
test -d "$parent"
test ! -e "$root"
test "$(cat "$parent/plain_preflight_jobid.txt")" = 228835
echo '29bd0aa1832d046bcd5a6761a24a7fe2735993450634383efd2d25cd76c97756  '"$payload" | sha256sum -c -
mkdir "$root"
tar -xzf "$payload" -C "$root" 2>"$root/deployment_extract.log"
cd "$root"
sha256sum -c package_files.sha256 >/dev/null
echo 'ALL_ADAPTIVE_PACKAGE_FILES_VERIFIED'
mkdir logs adaptive_comparison/runs
export PLAIN_PREFLIGHT_JOBID=228835
submission=$(sbatch --dependency=afterany:228835 --export=ALL,PLAIN_PREFLIGHT_JOBID=228835 adaptive_preflight.slurm 2>&1)
echo "$submission"
job=$(printf '%s\n' "$submission" | sed -nE 's/^Submitted batch job ([0-9]+)$/\1/p')
test -n "$job"
printf '%s\n' "$job" > "$parent/adaptive_preflight_jobid.txt"
echo "ADAPTIVE_SINGLE_SUBMISSION=$job"
scontrol show job "$job"
sacct -n -P -j 228835 -o JobID,JobName,State,ExitCode,Elapsed,NodeList
find "$parent/plain_preflight_v1/numerical_impact/runs" -mindepth 2 -maxdepth 2 -name completion.json -printf '%P\n' | sort
find "$parent/plain_preflight_v1/numerical_impact/runs" -maxdepth 2 -name failure.json -exec cat {} \;
