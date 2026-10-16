#!/bin/bash
set -o pipefail
# seq 25: four more seeds of the ID18-protocol OpenHydroNet NSE-loss run (one single-GPU job each, own root only)
ROOT=/data1/home/sunyiq/openhydronet_531_20261015
date --iso-8601=seconds
grep -nE '^(seed|experiment_name|loss|head):' "$ROOT/configs/id18_nse.yml"
submit() {  # seed partition
  local seed=$1 part=$2 name="id18_nse_s$1"
  sed -e "s/^experiment_name: .*/experiment_name: $name/" -e '/^seed:/d' "$ROOT/configs/id18_nse.yml" > "$ROOT/configs/$name.yml"
  echo "seed: $seed" >> "$ROOT/configs/$name.yml"
  grep -nE '^(seed|experiment_name):' "$ROOT/configs/$name.yml" | tr '\n' ' '; echo
  if squeue -u sunyiq -h -o '%j' | grep -qx "ohn_$name"; then echo "ohn_$name already queued/running"; return 0; fi
  local out jid
  out=$(sbatch --job-name="ohn_$name" -p "$part" -t 1-12:00:00 --export=ALL,CONFIG="$name" "$ROOT/run_ohn.slurm" 2>&1); echo "$out"
  jid=$(echo "$out" | grep -oE 'Submitted batch job [0-9]+' | grep -oE '[0-9]+')
  [ -n "$jid" ] || { echo "SUBMIT_FAILED $name"; return 1; }
  echo "jobid[$name]=$jid"
  squeue -j "$jid" -h -o '%i %j %T %R'
}
submit 101 hgpu8
submit 102 hgpu8
submit 103 hgpu4
submit 104 hgpu4
exit 0
