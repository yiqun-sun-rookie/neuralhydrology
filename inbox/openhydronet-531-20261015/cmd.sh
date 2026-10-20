#!/bin/bash
set -o pipefail
# seq 28: hyperparameter screening (4 single-GPU jobs, own root only). Held-out window = 2006-10..2008-09 inside the ID18 training period.
ROOT=/data1/home/sunyiq/openhydronet_531_20261015
P5="$HOME/hpc_mailbox/inbox/openhydronet-531-20261015/payload/v5"
date --iso-8601=seconds
for V in v0 v1 v2 v3; do [ -f "$P5/tune_$V.yml" ] || { echo "MISSING tune_$V.yml"; exit 1; }; cp "$P5/tune_$V.yml" "$ROOT/configs/"; sed -i 's/\r$//' "$ROOT/configs/tune_$V.yml"; done
grep -hE '^(experiment_name|hidden_size|seq_length|forecast_overlap|initial_forget_bias|learning_rate_drop_factor|target_noise_std|train_end_date|test_start_date|test_end_date|seed):' "$ROOT"/configs/tune_v3.yml
echo "=== free GPUs ==="
for P in hgpu8 hgpu4 hgpu2p; do sinfo -p $P -N -h -O nodelist:10,gres:10,gresused:22 2>/dev/null | tr '\n' ';'; echo; done
submit() {  # name partition
  local name=$1 part=$2 out jid
  if squeue -u sunyiq -h -o '%j' | grep -qx "ohn_$name"; then echo "ohn_$name already queued/running"; return 0; fi
  out=$(sbatch --job-name="ohn_$name" -p "$part" -t 1-12:00:00 --export=ALL,CONFIG="$name" "$ROOT/run_ohn.slurm" 2>&1); echo "$out"
  jid=$(echo "$out" | grep -oE 'Submitted batch job [0-9]+' | grep -oE '[0-9]+')
  [ -n "$jid" ] || { echo "SUBMIT_FAILED $name"; return 1; }
  echo "jobid[$name]=$jid"
}
submit tune_v0 hgpu8
submit tune_v1 hgpu8
submit tune_v2 hgpu4
submit tune_v3 hgpu4
squeue -u sunyiq -h -o '%.10i %.16j %.9T %R' | grep -E ' ohn_tune' || true
exit 0
