#!/bin/bash
set -o pipefail
# Submit the two ID18-protocol OpenHydroNet trainings (one single-GPU job each) once the data build has finished.
ROOT=/data1/home/sunyiq/openhydronet_531_20261015
date --iso-8601=seconds
tail -n 3 "$ROOT/logs/build_id18.log" | cut -c1-200
grep -q '^BUILD_DONE' "$ROOT/logs/build_id18.log" || { echo "BUILD_NOT_DONE"; exit 1; }
du -sh "$ROOT/data/id18_maurer"
submit() {  # name partition
  local name=$1 part=$2
  if squeue -u sunyiq -h -o '%j' | grep -qx "ohn_$name"; then echo "ohn_$name already queued/running"; return 0; fi
  local out
  out=$(sbatch --job-name="ohn_$name" -p "$part" -t 1-12:00:00 --export=ALL,CONFIG="$name" "$ROOT/run_ohn.slurm" 2>&1); echo "$out"
  local jid
  jid=$(echo "$out" | grep -oE 'Submitted batch job [0-9]+' | grep -oE '[0-9]+')
  [ -n "$jid" ] || { echo "SUBMIT_FAILED $name"; return 1; }
  echo "jobid[$name]=$jid"
  squeue -j "$jid" -h -o '%i %j %T %R'
}
submit id18_cmal hgpu8
submit id18_nse hgpu4
exit 0
