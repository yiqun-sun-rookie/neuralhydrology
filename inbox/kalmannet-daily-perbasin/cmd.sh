#!/usr/bin/env bash
set -o pipefail
readonly OUTPUT_ROOT="/data1/home/sunyiq/kalmannet_daily_camels_coldstart_intervention_development_20260927_v1"
readonly BASELINE_ROOT="/data1/home/sunyiq/kalmannet_daily_camels_coldstart_stress_development_20260924_v1"
readonly SOURCE_ROOT="/data1/home/sunyiq/kalmannet_daily_camels_per_basin_21_development_20260908_v3_aligned_rematch_20260916/workspace"
readonly RUNS_ROOT="/data1/home/sunyiq/kalmannet_daily_camels_per_basin_21_development_20260908_v3_aligned_rematch_20260916/runs"
readonly PYTHON_BIN="/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python"
readonly FAMILY="DAILY_CAMELS_KNET_ALIGNED_REMATCH_V3_20260916"
echo "COLDSTART_INTERVENTION_READ_ONLY_PREFLIGHT_V1"
echo "sequence=202"
echo "timestamp_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "host=$(hostname)"
echo "OWN_QUEUE_BEGIN"
squeue -u "$USER" -h -o '%i|%j|%T|%P|%R|%M|%l' || echo "SQUEUE_FAILED"
echo "OWN_QUEUE_END"
echo "CPU_PARTITION_BEGIN"
sinfo -h -p hcpu48 -o '%P|%a|%D|%t|%C' || echo "SINFO_FAILED"
scontrol show partition hcpu48 | grep -E 'PartitionName=|OverSubscribe=|State=|TotalCPUs=' || echo "PARTITION_FIELDS_NOT_FOUND"
echo "CPU_PARTITION_END"
echo "CPU_NODE_STATES_BEGIN"
sinfo -h -p hcpu48 -N -o '%N|%t|%c' || echo "SINFO_NODES_FAILED"
echo "CPU_NODE_STATES_END"
for path in "$SOURCE_ROOT" "$RUNS_ROOT" "$BASELINE_ROOT"; do
  if [[ -d "$path" && ! -L "$path" ]]; then echo "DIR_PRESENT $path"; else echo "DIR_ABSENT $path"; fi
done
if [[ -x "$PYTHON_BIN" ]]; then echo "PYTHON_PRESENT"; else echo "PYTHON_ABSENT"; fi
for seed in 20260824 20260901 20260908 20260915 20260922; do
  summary="$RUNS_ROOT/${FAMILY}_KNET_BASIN_02092500_SEED_${seed}/result_summary.json"
  if [[ -f "$summary" && ! -L "$summary" ]]; then echo "SUMMARY_PRESENT KNET $seed"; else echo "SUMMARY_ABSENT KNET $seed"; fi
done
if [[ -e "$OUTPUT_ROOT" ]]; then echo "PROPOSED_ROOT_ABSENT=no"; else echo "PROPOSED_ROOT_ABSENT=yes"; fi
echo "BASELINE_ROOT_BEGIN"
for name in aggregate.json completion.json; do
  path="$BASELINE_ROOT/$name"
  if [[ -f "$path" && ! -L "$path" ]]; then printf '%s|%s|%s\n' "$name" "$(stat -c %s "$path")" "$(sha256sum "$path" | awk '{print $1}')"; else echo "$name|ABSENT"; fi
done
present=0
absent=0
for seed in 20260824 20260901 20260908 20260915 20260922; do
  for start in 20001001 20011001 20021001 20031001 20041001 20051001 20061001; do
    path="$BASELINE_ROOT/runs/STRESS-02092500-NETWORK-${seed}-COLD${start}/arrays.npz"
    if [[ -f "$path" && ! -L "$path" ]]; then present=$((present + 1)); else absent=$((absent + 1)); echo "ARRAY_ABSENT $seed $start"; fi
  done
done
echo "network_arrays_present=$present network_arrays_absent=$absent"
targets=0
for start in 20001001 20011001 20021001 20031001 20041001 20051001 20061001; do
  date="${start:0:4}-${start:4:2}-${start:6:2}"
  if [[ -f "$BASELINE_ROOT/starts/$date/targets.npz" && ! -L "$BASELINE_ROOT/starts/$date/targets.npz" ]]; then targets=$((targets + 1)); else echo "TARGETS_ABSENT $date"; fi
done
echo "targets_present=$targets"
echo "BASELINE_ROOT_END"
echo "PREFLIGHT_COMPLETE"
