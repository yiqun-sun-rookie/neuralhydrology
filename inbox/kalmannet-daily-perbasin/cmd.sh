#!/usr/bin/env bash
set -eo pipefail
readonly OUTPUT_ROOT="/data1/home/sunyiq/kalmannet_daily_camels_coldstart_stress_development_20260924_v1"
readonly SOURCE_ROOT="/data1/home/sunyiq/kalmannet_daily_camels_per_basin_21_development_20260908_v3_aligned_rematch_20260916/workspace"
readonly RUNS_ROOT="/data1/home/sunyiq/kalmannet_daily_camels_per_basin_21_development_20260908_v3_aligned_rematch_20260916/runs"
readonly PYTHON_BIN="/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python"
readonly FAMILY="DAILY_CAMELS_KNET_ALIGNED_REMATCH_V3_20260916"
echo "COLDSTART_STRESS_READ_ONLY_PREFLIGHT_V1"
echo "sequence=194"
echo "timestamp_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "host=$(hostname)"
echo "OWN_QUEUE_BEGIN"
squeue -u "$USER" -h -o '%i|%j|%T|%P|%R|%M|%l'
echo "OWN_QUEUE_END"
echo "CPU_PARTITION_BEGIN"
sinfo -h -p hcpu48 -o '%P|%a|%D|%t|%C'
scontrol show partition hcpu48 | grep -E 'PartitionName=|OverSubscribe=|State=|TotalCPUs='
echo "CPU_PARTITION_END"
echo "CPU_NODE_FEATURES_BEGIN"
sinfo -h -p hcpu48 -N -o '%N|%t|%c|%f'
echo "CPU_NODE_FEATURES_END"
for path in "$SOURCE_ROOT" "$RUNS_ROOT"; do
  if [[ -d "$path" ]]; then echo "DIR_PRESENT $path"; else echo "DIR_ABSENT $path"; fi
done
if [[ -x "$PYTHON_BIN" ]]; then echo "PYTHON_PRESENT"; else echo "PYTHON_ABSENT"; fi
for arm in KNET UKF; do
  for seed in 20260824 20260901 20260908 20260915 20260922; do
    summary="$RUNS_ROOT/${FAMILY}_${arm}_BASIN_02092500_SEED_${seed}/result_summary.json"
    if [[ -f "$summary" && ! -L "$summary" ]]; then echo "SUMMARY_PRESENT $arm $seed"; else echo "SUMMARY_ABSENT $arm $seed"; fi
  done
done
if [[ -e "$OUTPUT_ROOT" ]]; then echo "PROPOSED_ROOT_ABSENT=no"; else echo "PROPOSED_ROOT_ABSENT=yes"; fi
echo "PREFLIGHT_COMPLETE"
