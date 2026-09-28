#!/usr/bin/env bash
set -eo pipefail
parent=/data1/home/sunyiq/kalmannet_wrr_closeout_20260928_v1
plain="$parent/plain_preflight_v1"
adaptive="$parent/adaptive_preflight_v1"
payload=/data1/home/sunyiq/hpc_mailbox/inbox/kalmannet-wrr-closeout-20260928
test -d "$plain"
test -d "$adaptive"
test ! -e "$plain/formal_admission_001"
test ! -e "$plain/formal_launch_001"
test ! -e "$adaptive/formal_admission_001"
test ! -e "$parent/plain_original_formal_jobid.txt"
test ! -e "$parent/adaptive_validation_formal_jobid.txt"
for predecessor in 228835 228839; do
  state=$(sacct -n -X -P -j "$predecessor" -o State | head -n 1 | cut -d'|' -f1)
  case "$state" in COMPLETED|FAILED|CANCELLED*|TIMEOUT|OUT_OF_MEMORY|NODE_FAIL|PREEMPTED|BOOT_FAIL|DEADLINE) ;; *) echo "PREDECESSOR_NOT_TERMINAL=$predecessor:$state"; exit 64;; esac
done
echo 'eb5103f88c24e744212d6dfbf596c622f4d74e70b7ea683c1d6baf70be4b5e43  '"$payload/plain_original_launch_001.tar" | sha256sum -c -
echo '8ad00f4395b479c6773fb3b9686aea6befe7ca7890120fcbce069fa21fca2958  '"$payload/adaptive_validation_launch_001.tar" | sha256sum -c -
tar --keep-old-files -xf "$payload/plain_original_launch_001.tar" -C "$plain"
tar --keep-old-files -xf "$payload/adaptive_validation_launch_001.tar" -C "$adaptive"
cd "$plain"
sha256sum -c formal_launch_001/launch_files.sha256
mkdir formal_launch_001/logs
cd "$adaptive/formal_admission_001"
sha256sum -c launch_files.sha256
cd "$plain"
submission=$(sbatch formal_launch_001/original_nine.slurm 2>&1)
echo "$submission"
plain_job=$(printf '%s\n' "$submission" | sed -nE 's/^Submitted batch job ([0-9]+)$/\1/p')
test -n "$plain_job"
(set -o noclobber; printf '%s\n' "$plain_job" > "$parent/plain_original_formal_jobid.txt")
echo "PLAIN_ORIGINAL_FORMAL_SINGLE_SUBMISSION=$plain_job"
cd "$adaptive"
submission=$(sbatch --dependency="afterany:$plain_job" formal_admission_001/validation_five.slurm 2>&1)
echo "$submission"
adaptive_job=$(printf '%s\n' "$submission" | sed -nE 's/^Submitted batch job ([0-9]+)$/\1/p')
test -n "$adaptive_job"
(set -o noclobber; printf '%s\n' "$adaptive_job" > "$parent/adaptive_validation_formal_jobid.txt")
echo "ADAPTIVE_VALIDATION_FORMAL_SINGLE_SUBMISSION=$adaptive_job"
scontrol show job "$plain_job"
scontrol show job "$adaptive_job"
sacct -n -P -j "$plain_job,$adaptive_job" -o JobID,JobName,State,ExitCode,Elapsed,NodeList
