#!/bin/bash
set -eo pipefail

JOB_ID=216818
EVALUATION_ROOT="/data1/home/sunyiq/zhenjiang_d32_differentiable_ukf_dev_eval_20260831_r2"
TRAINING_ROOT="/data1/home/sunyiq/zhenjiang_d32_differentiable_ukf_20260828_r2"
RUN_ROOT="${EVALUATION_ROOT}/run"
REGISTRY="${RUN_ROOT}/docs/records/ZHENJIANG_D32_GRU_DIFFERENTIABLE_UKF_V1_DEVELOPMENT_EVALUATION_REGISTRY_R2.json"

echo "QUERY_TIME=$(date -Is)"
echo "=== SQUEUE ==="
squeue -j "${JOB_ID}" -o '%i|%j|%T|%P|%N|%M|%l|%R' || true
echo "=== ESTIMATED_START ==="
squeue --start -j "${JOB_ID}" -o '%i|%S|%R' || true
echo "=== SACCT ==="
sacct -j "${JOB_ID}" -P --format=JobIDRaw,JobName,Partition,State,ExitCode,Elapsed,Start,End,NodeList || true

ALL_COMPLETE=true
echo "=== OUTPUT_EXISTENCE ==="
for SEED in 17 29 43; do
  ATTEMPT="${EVALUATION_ROOT}/smoke/ZHD32-DUKF-DEV-EVAL-S${SEED}-V1/attempt_001"
  FINAL=false
  PARTIAL=false
  test -d "${ATTEMPT}" && FINAL=true
  test -d "${ATTEMPT}.partial" && PARTIAL=true
  printf 'seed=%s final=%s partial=%s\n' "${SEED}" "${FINAL}" "${PARTIAL}"
  if [ "${FINAL}" != true ]; then ALL_COMPLETE=false; fi
done

OUT_LOG="${EVALUATION_ROOT}/logs/smoke_${JOB_ID}.out"
ERR_LOG="${EVALUATION_ROOT}/logs/smoke_${JOB_ID}.err"
echo "=== STDOUT_TAIL ==="
if [ -f "${OUT_LOG}" ]; then tail -n 160 "${OUT_LOG}"; else echo absent; fi
echo "=== STDERR_TAIL ==="
if [ -f "${ERR_LOG}" ]; then tail -n 160 "${ERR_LOG}"; else echo absent; fi

if [ "${ALL_COMPLETE}" = true ]; then
  export PYTHONDONTWRITEBYTECODE=1
  export MKL_THREADING_LAYER=GNU
  export MKL_SERVICE_FORCE_INTEL=1
  source "/data1/home/${USER}/miniconda3/etc/profile.d/conda.sh"
  conda activate nh_final
  cd "${RUN_ROOT}"
  export PYTHONPATH="${TRAINING_ROOT}/run/scripts/modeling:${RUN_ROOT}/scripts/analysis:${TRAINING_ROOT}/run/scripts/astronomical_tide:${TRAINING_ROOT}/run/third_party:${PYTHONPATH:-}"
  for SEED in 17 29 43; do
    ATTEMPT="${EVALUATION_ROOT}/smoke/ZHD32-DUKF-DEV-EVAL-S${SEED}-V1/attempt_001"
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
zero = {
    "test_target_rows_read": 0,
    "test_target_values_loaded": 0,
    "test_target_values_parsed": 0,
}
for seed in (17, 29, 43):
    experiment = "ZHD32-DUKF-DEV-EVAL-S%d-V1" % seed
    attempt = root / "smoke" / experiment / "attempt_001"
    worker = json.loads((attempt / "worker_summary.json").read_text())
    data = json.loads((attempt / "data_identity.json").read_text())
    checkpoint = json.loads((attempt / "checkpoint_identity.json").read_text())
    run = json.loads((attempt / "run_identity.json").read_text())
    expected = registry["experiments"][experiment]
    if (
        worker.get("status") != "completed_2023_development_smoke"
        or worker.get("completed_batches") != 2
        or worker.get("processed_base_sample_count") != 64
        or worker.get("block_count") != 1
        or worker.get("block_error_row_count") != 828
        or worker.get("block_analysis_row_count") != 6
        or worker.get("block_state_decay_row_count") != 138
        or worker.get("test_target_counters") != zero
        or data.get("test_target_counters") != zero
        or data.get("last_loaded_target_time_beijing") != "2023-12-31T23:00:00+08:00"
        or run.get("registry_sha256") != registry_sha
        or checkpoint.get("best_checkpoint_sha256") != expected["best_checkpoint_sha256"]
        or checkpoint.get("only_adapter_state_dict_loaded") is not True
        or checkpoint.get("optimizer_state_loaded") is not False
        or checkpoint.get("random_state_loaded") is not False
    ):
        raise SystemExit("revision-two smoke semantic gate failed for seed %d" % seed)
    print(
        "REVISION_TWO_SMOKE_SEED_GATE=PASS seed=%d samples=%d checkpoint=%s"
        % (seed, worker["processed_base_sample_count"], checkpoint["best_checkpoint_sha256"])
    )
print("REVISION_TWO_THREE_SEED_SMOKE_GATE=PASS")
PY
fi
