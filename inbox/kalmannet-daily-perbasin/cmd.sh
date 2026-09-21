#!/bin/bash
# sequence=183
set -eo pipefail

SOURCE_ROOT=/data1/home/sunyiq/kalmannet_daily_camels_per_basin_21_development_20260908_v3_aligned_rematch_20260916
OUTPUT_ROOT=/data1/home/sunyiq/kalmannet_daily_camels_stability_diagnosis_development_20260921_v1

echo "DIAG_PREFLIGHT_READONLY_V1"
echo "sequence=183"
echo "timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "host=$(hostname)"

echo "OWN_JOBS_BEGIN"
squeue -u "$USER" -h -o '%i|%j|%T|%P|%R' || true
echo "OWN_JOBS_END"

echo "HCPU48_STATE_BEGIN"
sinfo -p hcpu48 -h -o '%P|%a|%l|%D|%t|%C'
scontrol show partition hcpu48 | grep -E 'PartitionName=|State=|OverSubscribe=|TotalCPUs=|TotalNodes='
echo "HCPU48_STATE_END"

[ -d "$SOURCE_ROOT/workspace" ] || { echo "MISSING_WORKSPACE"; exit 10; }
[ -d "$SOURCE_ROOT/runs" ] || { echo "MISSING_RUNS"; exit 11; }
if [ -e "$OUTPUT_ROOT" ]; then
  echo "OUTPUT_ROOT_ALREADY_EXISTS=$OUTPUT_ROOT"
  exit 12
fi
echo "OUTPUT_ROOT_ABSENT=yes"

echo "SOURCE_HASHES_BEGIN"
sha256sum \
  "$SOURCE_ROOT/workspace/knet/dl/nn_kalman_clamp_5.py" \
  "$SOURCE_ROOT/workspace/src/global_hydrology/models/knet_native_hbvlite_full_state.py" \
  "$SOURCE_ROOT/workspace/src/global_hydrology/experiments/daily_camels_knet_per_basin_runner.py" \
  "$SOURCE_ROOT/workspace/src/global_hydrology/experiments/daily_camels_ukf_knet_parity_runner.py" \
  "$SOURCE_ROOT/workspace/src/global_hydrology/models/hbvlite_system_model.py" \
  "$SOURCE_ROOT/workspace/src/global_hydrology/models/differentiable_hbv_lite.py"
echo "SOURCE_HASHES_END"

echo "RUN_SUMMARIES_BEGIN"
for SEED in 20260824 20260901 20260908 20260915 20260922; do
  RUN_ID="DAILY_CAMELS_KNET_ALIGNED_REMATCH_V3_20260916_KNET_BASIN_02092500_SEED_${SEED}"
  SUMMARY="$SOURCE_ROOT/runs/$RUN_ID/result_summary.json"
  [ -f "$SUMMARY" ] || { echo "MISSING_SUMMARY=$SUMMARY"; exit 13; }
  echo "RUN_ID=$RUN_ID"
  grep -E '"(best_epoch|best_checkpoint|best_checkpoint_sha256)"' "$SUMMARY"
done
echo "RUN_SUMMARIES_END"
