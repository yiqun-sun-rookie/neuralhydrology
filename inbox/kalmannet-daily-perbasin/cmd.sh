#!/usr/bin/env bash
set -o pipefail
readonly OUTPUT_ROOT="/data1/home/sunyiq/kalmannet_daily_camels_training_mode_replay_development_20260927_v1"
readonly STRESS_ROOT="/data1/home/sunyiq/kalmannet_daily_camels_coldstart_stress_development_20260924_v1"
readonly INTERVENTION_ROOT="/data1/home/sunyiq/kalmannet_daily_camels_coldstart_intervention_development_20260927_v1"
readonly SOURCE_ROOT="/data1/home/sunyiq/kalmannet_daily_camels_per_basin_21_development_20260908_v3_aligned_rematch_20260916/workspace"
readonly RUNS_ROOT="/data1/home/sunyiq/kalmannet_daily_camels_per_basin_21_development_20260908_v3_aligned_rematch_20260916/runs"
readonly PYTHON_BIN="/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python"
readonly FAMILY="DAILY_CAMELS_KNET_ALIGNED_REMATCH_V3_20260916"
echo "TRAINING_MODE_REPLAY_READ_ONLY_PREFLIGHT_V1"
echo "sequence=217"
echo "timestamp_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "host=$(hostname)"
echo "OWN_QUEUE_BEGIN"
squeue -u "$USER" -h -o '%i|%j|%T|%P|%R|%M|%l' || echo "SQUEUE_FAILED"
echo "OWN_QUEUE_END"
echo "CPU_PARTITION_BEGIN"
sinfo -h -p hcpu48 -o '%P|%a|%D|%t|%C' || echo "SINFO_FAILED"
scontrol show partition hcpu48 | grep -E 'PartitionName=|OverSubscribe=|State=|TotalCPUs=' || echo "PARTITION_FIELDS_NOT_FOUND"
echo "CPU_PARTITION_END"
for path in "$SOURCE_ROOT" "$RUNS_ROOT" "$STRESS_ROOT" "$INTERVENTION_ROOT"; do
  if [[ -d "$path" && ! -L "$path" ]]; then echo "DIR_PRESENT $path"; else echo "DIR_ABSENT $path"; fi
done
if [[ -x "$PYTHON_BIN" ]]; then echo "PYTHON_PRESENT"; else echo "PYTHON_ABSENT"; fi
for seed in 20260824 20260901 20260908 20260915 20260922; do
  summary="$RUNS_ROOT/${FAMILY}_KNET_BASIN_02092500_SEED_${seed}/result_summary.json"
  if [[ -f "$summary" && ! -L "$summary" ]]; then echo "SUMMARY_PRESENT KNET $seed"; else echo "SUMMARY_ABSENT KNET $seed"; fi
done
if [[ -e "$OUTPUT_ROOT" ]]; then echo "PROPOSED_ROOT_ABSENT=no"; else echo "PROPOSED_ROOT_ABSENT=yes"; fi
echo "READ_ONLY_FILES_BEGIN"
for path in "$STRESS_ROOT/aggregate.json" "$STRESS_ROOT/completion.json" "$INTERVENTION_ROOT/bounds.json" \
            "$STRESS_ROOT/runs/STRESS-02092500-NETWORK-20260922-COLD20041001/arrays.npz" \
            "$STRESS_ROOT/runs/STRESS-02092500-NETWORK-20260824-COLD20041001/arrays.npz" \
            "$INTERVENTION_ROOT/runs/INTV-02092500-NETWORK-20260922-COLD20011001-R2_150/arrays.npz" \
            "$INTERVENTION_ROOT/runs/INTV-02092500-NETWORK-20260922-COLD20021001-R2_150/arrays.npz" \
            "$INTERVENTION_ROOT/runs/INTV-02092500-NETWORK-20260922-COLD20031001-R2_150/arrays.npz" \
            "$INTERVENTION_ROOT/runs/INTV-02092500-NETWORK-20260922-COLD20041001-R2_150/arrays.npz"; do
  if [[ -f "$path" && ! -L "$path" ]]; then printf '%s|%s|%s\n' "$path" "$(stat -c %s "$path")" "$(sha256sum "$path" | awk '{print $1}')"; else echo "$path|ABSENT"; fi
done
for seed in 20260824 20260901 20260908 20260915 20260922; do
  path="$RUNS_ROOT/${FAMILY}_KNET_BASIN_02092500_SEED_${seed}/epoch_history.json"
  marker="$RUNS_ROOT/${FAMILY}_KNET_BASIN_02092500_SEED_${seed}/completion.marker.json"
  if [[ -f "$path" && ! -L "$path" ]]; then printf 'EPOCH_HISTORY|%s|%s|%s\n' "$seed" "$(stat -c %s "$path")" "$(sha256sum "$path" | awk '{print $1}')"; else echo "EPOCH_HISTORY|$seed|ABSENT"; fi
  if [[ -f "$marker" && ! -L "$marker" ]]; then printf 'MARKER|%s|%s|%s\n' "$seed" "$(sha256sum "$marker" | awk '{print $1}')" "$(grep -o '"epoch_history_sha256": "[0-9a-f]*"' "$marker" | head -n 1)"; else echo "MARKER|$seed|ABSENT"; fi
done
echo "READ_ONLY_FILES_END"
echo "PREFLIGHT_COMPLETE"
