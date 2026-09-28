#!/usr/bin/env bash
set -eo pipefail
root=/data1/home/sunyiq/kalmannet_wrr_closeout_20260928_v1
payload=/data1/home/sunyiq/hpc_mailbox/inbox/kalmannet-wrr-closeout-20260928/counter_code_v1.tar
test ! -e "$root"
echo '291121e32e39fb850f2be9015d7a8f3b1f3584e69d92dd56ed2673feee173191  '"$payload" | sha256sum -c -
mkdir "$root"
mkdir "$root/logs" "$root/counter_code_v1"
tar -xf "$payload" -C "$root/counter_code_v1"
cd "$root/counter_code_v1"
echo 'cc93937c613772642a062b20cd1667f528b2f1facd12c802e1ba12a80aaddf39  counter_saved_metrics.py' | sha256sum -c -
echo '5b1eb4988b8843d40d8af1532ca2bddcd199add4c9cb6eeaa08f39e02e34bb01  test_counter_saved_metrics.py' | sha256sum -c -
echo '84bec57f26736f64b86b5e7fbb2c9d95ca4b70fe1c8fc9ec0c02d9ec8105af80  counter_metrics.slurm' | sha256sum -c -
submission=$(sbatch counter_metrics.slurm 2>&1)
echo "$submission"
job=$(printf '%s\n' "$submission" | sed -nE 's/^Submitted batch job ([0-9]+)$/\1/p')
test -n "$job"
printf '%s\n' "$job" > "$root/counter_metrics_jobid.txt"
echo "COUNTER_METRICS_SINGLE_SUBMISSION=$job"
