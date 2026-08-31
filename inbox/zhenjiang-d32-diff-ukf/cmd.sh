#!/bin/bash
set -eo pipefail

JOB_ID=217013
EVALUATION_ROOT="/data1/home/sunyiq/zhenjiang_d32_differentiable_ukf_dev_eval_20260831_r3"
TRAINING_ROOT="/data1/home/sunyiq/zhenjiang_d32_differentiable_ukf_20260828_r2"
RUN_ROOT="${EVALUATION_ROOT}/run"
REGISTRY="${RUN_ROOT}/docs/records/ZHENJIANG_D32_GRU_DIFFERENTIABLE_UKF_V1_DEVELOPMENT_EVALUATION_REGISTRY_R3.json"

echo "QUERY_TIME=$(date -Is)"
echo "=== ARRAY_QUEUE ==="
squeue -j "${JOB_ID}" -o '%i|%j|%T|%P|%N|%M|%l|%R' || true
echo "=== ARRAY_ESTIMATED_START ==="
squeue --start -j "${JOB_ID}" -o '%i|%S|%R' || true
echo "=== ARRAY_SCHEDULER_IDENTITY ==="
scontrol show job -o "${JOB_ID}" || true
echo "=== ARRAY_ACCOUNTING ==="
sacct -X -j "${JOB_ID}" -P \
  --format=JobIDRaw,JobName,Partition,State,ExitCode,Elapsed,Start,End,NodeList,AllocTRES || true

SEEDS=(17 29 43)
ALL_COMPLETE=true
echo "=== WORKER_OUTPUT_EXISTENCE ==="
for INDEX in 0 1 2; do
  SEED="${SEEDS[$INDEX]}"
  ATTEMPT="${EVALUATION_ROOT}/workers/ZHD32-DUKF-DEV-EVAL-S${SEED}-V1/attempt_001"
  FINAL=false
  PARTIAL=false
  test -d "${ATTEMPT}" && FINAL=true
  test -d "${ATTEMPT}.partial" && PARTIAL=true
  printf 'index=%s seed=%s final=%s partial=%s\n' \
    "${INDEX}" "${SEED}" "${FINAL}" "${PARTIAL}"
  if [ "${FINAL}" != true ]; then ALL_COMPLETE=false; fi
done

for INDEX in 0 1 2; do
  OUT_LOG="${EVALUATION_ROOT}/logs/formal_${JOB_ID}_${INDEX}.out"
  ERR_LOG="${EVALUATION_ROOT}/logs/formal_${JOB_ID}_${INDEX}.err"
  echo "=== INDEX_${INDEX}_STANDARD_OUTPUT_TAIL ==="
  if [ -f "${OUT_LOG}" ]; then tail -n 120 "${OUT_LOG}"; else echo absent; fi
  echo "=== INDEX_${INDEX}_STANDARD_ERROR_TAIL ==="
  if [ -f "${ERR_LOG}" ]; then tail -n 120 "${ERR_LOG}"; else echo absent; fi
done

if [ "${ALL_COMPLETE}" = true ]; then
  for INDEX in 0 1 2; do
    TASK_ID="${JOB_ID}_${INDEX}"
    ACCOUNTING="$(
      sacct -X -n -j "${TASK_ID}" -P --format=JobIDRaw,State,ExitCode |
        awk -F'|' -v task="${TASK_ID}" '$1 == task {print $2 "|" $3}'
    )"
    [ "${ACCOUNTING}" = "COMPLETED|0:0" ] || {
      echo "[FATAL] formal task accounting gate failed: ${TASK_ID} ${ACCOUNTING}" >&2
      exit 1
    }
  done

  export PYTHONDONTWRITEBYTECODE=1
  export MKL_THREADING_LAYER=GNU
  export MKL_SERVICE_FORCE_INTEL=1
  source "/data1/home/${USER}/miniconda3/etc/profile.d/conda.sh"
  conda activate nh_final
  cd "${RUN_ROOT}"
  export PYTHONPATH="${TRAINING_ROOT}/run/scripts/modeling:${RUN_ROOT}/scripts/analysis:${TRAINING_ROOT}/run/scripts/astronomical_tide:${TRAINING_ROOT}/run/third_party:${PYTHONPATH:-}"
  for SEED in 17 29 43; do
    ATTEMPT="${EVALUATION_ROOT}/workers/ZHD32-DUKF-DEV-EVAL-S${SEED}-V1/attempt_001"
    python -u scripts/analysis/zhenjiang_d32_gru_differentiable_ukf_development_evaluation_v1.py \
      --verify-output "${ATTEMPT}"
  done
  python - "${EVALUATION_ROOT}" "${REGISTRY}" <<'PY'
from pathlib import Path
import hashlib
import json
import sys


root = Path(sys.argv[1]).resolve()
registry_path = Path(sys.argv[2]).resolve()
registry_sha = hashlib.sha256(registry_path.read_bytes()).hexdigest()
registry = json.loads(registry_path.read_text())
normalization_contract = registry["normalization_identity_contract"]
zero = {
    "test_target_rows_read": 0,
    "test_target_values_loaded": 0,
    "test_target_values_parsed": 0,
}
for seed in (17, 29, 43):
    experiment = "ZHD32-DUKF-DEV-EVAL-S%d-V1" % seed
    attempt = root / "workers" / experiment / "attempt_001"
    worker = json.loads((attempt / "worker_summary.json").read_text())
    data = json.loads((attempt / "data_identity.json").read_text())
    checkpoint = json.loads((attempt / "checkpoint_identity.json").read_text())
    run = json.loads((attempt / "run_identity.json").read_text())
    normalization = data.get("target_normalization_identity", {})
    expected = registry["experiments"][experiment]
    expected_run_sha = normalization_contract[
        "training_run_identity_sha256_by_seed"
    ][str(seed)]
    if (
        worker.get("status") != "completed_2023_development_worker"
        or worker.get("completed_batches") != 252
        or worker.get("processed_base_sample_count") != 8046
        or worker.get("block_count") != 48
        or worker.get("block_error_row_count") != 39744
        or worker.get("block_analysis_row_count") != 288
        or worker.get("block_state_decay_row_count") != 6624
        or worker.get("test_target_counters") != zero
        or data.get("test_target_counters") != zero
        or data.get("processed_base_sample_count") != 8046
        or data.get("validation_base_sample_count") != 8046
        or data.get("last_loaded_target_time_beijing")
        != "2023-12-31T23:00:00+08:00"
        or data.get("source_training_data_identity_sha256")
        != normalization_contract["legacy_training_data_identity_sha256"]
        or data.get("source_training_run_identity_sha256") != expected_run_sha
        or normalization.get("verification_method")
        != normalization_contract["verification_method"]
        or normalization.get("source_training_target_mean_present") is not False
        or normalization.get("source_training_data_identity_sha256")
        != normalization_contract["legacy_training_data_identity_sha256"]
        or normalization.get("source_training_run_identity_sha256")
        != expected_run_sha
        or normalization.get("station_order")
        != normalization_contract["station_order"]
        or normalization.get("target_mean_float32_bits")
        != normalization_contract["target_mean_float32_bits"]
        or normalization.get("target_standard_deviation_float32_bits")
        != normalization_contract["target_standard_deviation_float32_bits"]
        or run.get("registry_sha256") != registry_sha
        or checkpoint.get("best_checkpoint_sha256")
        != expected["best_checkpoint_sha256"]
        or checkpoint.get("only_adapter_state_dict_loaded") is not True
        or checkpoint.get("optimizer_state_loaded") is not False
        or checkpoint.get("random_state_loaded") is not False
    ):
        raise SystemExit(
            "revision-three formal worker semantic gate failed for seed %d"
            % seed
        )
    print(
        "REVISION_THREE_FORMAL_WORKER_GATE=PASS "
        "seed=%d samples=%d blocks=%d checkpoint=%s"
        % (
            seed,
            worker["processed_base_sample_count"],
            worker["block_count"],
            checkpoint["best_checkpoint_sha256"],
        )
    )
print("REVISION_THREE_THREE_WORKER_FORMAL_GATE=PASS")
PY
fi
