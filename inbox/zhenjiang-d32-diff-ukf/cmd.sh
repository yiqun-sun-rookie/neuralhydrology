#!/bin/bash
set -eo pipefail

FAILED_JOB_ID=217148
EVALUATION_ROOT="/data1/home/sunyiq/zhenjiang_d32_differentiable_ukf_dev_eval_20260831_r3"
SUMMARY="${EVALUATION_ROOT}/summary/ZHD32-DUKF-DEV-EVAL-SUMMARY-V1/attempt_001"
AUDIT="${EVALUATION_ROOT}/audit/ZHD32-DUKF-DEV-EVAL-SUMMARY-V1/attempt_001"
FAILED_JOB_SCRIPT="${EVALUATION_ROOT}/jobs/aggregate_audit_v2.slurm"
JOB_SCRIPT="${EVALUATION_ROOT}/jobs/aggregate_audit_v3.slurm"
JOB_RECORD="${EVALUATION_ROOT}/jobs/aggregate_audit_v3_job_id.txt"
SOURCE_SCRIPT="${HOME}/hpc_mailbox/inbox/zhenjiang-d32-diff-ukf/aggregate_audit_v3.slurm"
EXPECTED_SCRIPT_BYTES=5494
EXPECTED_SCRIPT_SHA256="eea4ae32a40aa8f1ab3f09c9bf3b8c197129b3b2e7d5bcd815b7b800ad6c3f11"

echo "QUERY_TIME=$(date -Is)"
echo "=== FAILED_JOB_ACCOUNTING ==="
sacct -X -j "${FAILED_JOB_ID}" -P \
  --format=JobID,JobName,Partition,State,ExitCode,Elapsed,Start,End,NodeList,AllocTRES || true
FAILED_ACCOUNTING="$(
  sacct -X -n -j "${FAILED_JOB_ID}" -P --format=JobID,State,ExitCode |
    awk -F'|' -v job="${FAILED_JOB_ID}" '$1 == job {print $2 "|" $3}'
)"
if [ "${FAILED_ACCOUNTING}" != "FAILED|1:0" ]; then
  echo "failed job accounting identity changed: ${FAILED_ACCOUNTING}" >&2
  exit 2
fi
if [ -n "$(squeue -h -u "${USER}" -n zhd32_dukf_aggregate 2>/dev/null)" ]; then
  echo "another aggregate job is still queued or running" >&2
  exit 2
fi

echo "=== PRESERVED_FAILED_SCRIPT ==="
test -f "${FAILED_JOB_SCRIPT}"
test ! -L "${FAILED_JOB_SCRIPT}"
sha256sum "${FAILED_JOB_SCRIPT}"

echo "=== CREATE_ONLY_TARGETS ==="
for TARGET in "${SUMMARY}" "${SUMMARY}.partial" "${AUDIT}" "${AUDIT}.partial" "${JOB_SCRIPT}" "${JOB_RECORD}"; do
  if [ -e "${TARGET}" ]; then
    printf 'exists|%s\n' "${TARGET}"
    echo "create-only target already exists: ${TARGET}" >&2
    exit 2
  fi
  printf 'absent|%s\n' "${TARGET}"
done

if [ ! -f "${SOURCE_SCRIPT}" ] || [ -L "${SOURCE_SCRIPT}" ]; then
  echo "mailbox aggregation script is absent or symbolic" >&2
  exit 2
fi
ACTUAL_SCRIPT_BYTES="$(stat -c '%s' "${SOURCE_SCRIPT}")"
ACTUAL_SCRIPT_SHA256="$(sha256sum "${SOURCE_SCRIPT}" | awk '{print $1}')"
if [ "${ACTUAL_SCRIPT_BYTES}" != "${EXPECTED_SCRIPT_BYTES}" ] || \
   [ "${ACTUAL_SCRIPT_SHA256}" != "${EXPECTED_SCRIPT_SHA256}" ]; then
  echo "mailbox aggregation script identity changed" >&2
  exit 2
fi

install -m 0555 "${SOURCE_SCRIPT}" "${JOB_SCRIPT}"
test "$(stat -c '%s' "${JOB_SCRIPT}")" = "${EXPECTED_SCRIPT_BYTES}"
test "$(sha256sum "${JOB_SCRIPT}" | awk '{print $1}')" = "${EXPECTED_SCRIPT_SHA256}"
JOB_ID="$(sbatch --parsable "${JOB_SCRIPT}")"
case "${JOB_ID}" in
  ''|*[!0-9]*)
    echo "scheduler returned an invalid job identifier: ${JOB_ID}" >&2
    exit 2
    ;;
esac
echo "AGGREGATE_AUDIT_JOB_ID=${JOB_ID}"
scontrol show job -o "${JOB_ID}"
exit 0

JOB_ID=217148
EVALUATION_ROOT="/data1/home/sunyiq/zhenjiang_d32_differentiable_ukf_dev_eval_20260831_r3"
SUMMARY="${EVALUATION_ROOT}/summary/ZHD32-DUKF-DEV-EVAL-SUMMARY-V1/attempt_001"
AUDIT="${EVALUATION_ROOT}/audit/ZHD32-DUKF-DEV-EVAL-SUMMARY-V1/attempt_001"
OUT_LOG="${EVALUATION_ROOT}/logs/aggregate_audit_v2_${JOB_ID}.out"
ERR_LOG="${EVALUATION_ROOT}/logs/aggregate_audit_v2_${JOB_ID}.err"

echo "QUERY_TIME=$(date -Is)"
echo "=== AGGREGATE_AUDIT_QUEUE ==="
squeue -j "${JOB_ID}" -o '%i|%j|%T|%P|%N|%M|%l|%R' || true
echo "=== AGGREGATE_AUDIT_ESTIMATED_START ==="
squeue --start -j "${JOB_ID}" -o '%i|%S|%R' || true
echo "=== AGGREGATE_AUDIT_SCHEDULER_IDENTITY ==="
scontrol show job -o "${JOB_ID}" || true
echo "=== AGGREGATE_AUDIT_ACCOUNTING ==="
sacct -X -j "${JOB_ID}" -P \
  --format=JobID,JobName,Partition,State,ExitCode,Elapsed,Start,End,NodeList,AllocTRES,MaxRSS || true
echo "=== OUTPUT_EXISTENCE ==="
for TARGET in "${SUMMARY}" "${SUMMARY}.partial" "${AUDIT}" "${AUDIT}.partial"; do
  if [ -e "${TARGET}" ]; then
    printf 'exists|%s\n' "${TARGET}"
  else
    printf 'absent|%s\n' "${TARGET}"
  fi
done
echo "=== STANDARD_OUTPUT_TAIL ==="
if [ -f "${OUT_LOG}" ]; then tail -n 160 "${OUT_LOG}"; else echo absent; fi
echo "=== STANDARD_ERROR_TAIL ==="
if [ -f "${ERR_LOG}" ]; then tail -n 160 "${ERR_LOG}"; else echo absent; fi

ACCOUNTING="$(
  sacct -X -n -j "${JOB_ID}" -P --format=JobID,State,ExitCode |
    awk -F'|' -v job="${JOB_ID}" '$1 == job {print $2 "|" $3}'
)"
if [ "${ACCOUNTING}" = "COMPLETED|0:0" ]; then
  test -d "${SUMMARY}"
  test ! -e "${SUMMARY}.partial"
  test -d "${AUDIT}"
  test ! -e "${AUDIT}.partial"
  echo "=== COMPLETED_RESULT_IDENTITIES ==="
  sha256sum \
    "${SUMMARY}/completion_manifest.json" \
    "${SUMMARY}/development_gate.json" \
    "${SUMMARY}/bootstrap_condition_summary.csv" \
    "${AUDIT}/independent_audit.json"
  echo "=== DEVELOPMENT_GATE ==="
  cat "${SUMMARY}/development_gate.json"
  echo "=== INDEPENDENT_AUDIT ==="
  cat "${AUDIT}/independent_audit.json"
  echo "=== BOOTSTRAP_CONDITION_SUMMARY ==="
  cat "${SUMMARY}/bootstrap_condition_summary.csv"
  echo "=== HOLM_PRIMARY_FAMILY ==="
  cat "${SUMMARY}/holm_primary_family.csv"
  echo "=== WINDOW_CONDITION_SEED_METRICS ==="
  cat "${SUMMARY}/window_condition_seed_metrics.csv"
  echo "AGGREGATE_AUDIT_FINAL_GATE=PASS"
fi
exit 0

EVALUATION_ROOT="/data1/home/sunyiq/zhenjiang_d32_differentiable_ukf_dev_eval_20260831_r3"
RUN_ROOT="${EVALUATION_ROOT}/run"
REGISTRY="${RUN_ROOT}/docs/records/ZHENJIANG_D32_GRU_DIFFERENTIABLE_UKF_V1_DEVELOPMENT_EVALUATION_REGISTRY_R3.json"
SUMMARY="${EVALUATION_ROOT}/summary/ZHD32-DUKF-DEV-EVAL-SUMMARY-V1/attempt_001"
AUDIT="${EVALUATION_ROOT}/audit/ZHD32-DUKF-DEV-EVAL-SUMMARY-V1/attempt_001"
FAILED_JOB_SCRIPT="${EVALUATION_ROOT}/jobs/aggregate_audit_v1.slurm"
JOB_SCRIPT="${EVALUATION_ROOT}/jobs/aggregate_audit_v2.slurm"
JOB_RECORD="${EVALUATION_ROOT}/jobs/aggregate_audit_v2_job_id.txt"

echo "QUERY_TIME=$(date -Is)"
echo "=== RELEVANT_QUEUE ==="
squeue -u "${USER}" -o '%i|%j|%T|%P|%N|%M|%l|%R' |
  awk 'NR == 1 || $2 ~ /^zhd32_dukf/' || true
echo "=== CPU_PARTITIONS ==="
sinfo -p hcpu48,hcpu48y -o '%P|%a|%l|%D|%t|%N' || true
echo "=== CPU_NODES ==="
sinfo -N -p hcpu48,hcpu48y -o '%N|%P|%t|%c|%m' || true
echo "=== IMMUTABLE_INPUTS ==="
sha256sum \
  "${REGISTRY}" \
  "${RUN_ROOT}/scripts/analysis/zhenjiang_d32_gru_differentiable_ukf_development_evaluation_v1.py" \
  "${RUN_ROOT}/scripts/analysis/audit_zhenjiang_d32_gru_differentiable_ukf_development_evaluation_v1.py"
for SEED in 17 29 43; do
  ATTEMPT="${EVALUATION_ROOT}/workers/ZHD32-DUKF-DEV-EVAL-S${SEED}-V1/attempt_001"
  test -d "${ATTEMPT}"
  test ! -e "${ATTEMPT}.partial"
  sha256sum "${ATTEMPT}/completion_manifest.json"
done
if [ -f "${FAILED_JOB_SCRIPT}" ] && [ ! -L "${FAILED_JOB_SCRIPT}" ]; then
  sha256sum "${FAILED_JOB_SCRIPT}"
fi
echo "=== CREATE_ONLY_TARGETS ==="
for TARGET in "${SUMMARY}" "${SUMMARY}.partial" "${AUDIT}" "${AUDIT}.partial" "${JOB_SCRIPT}" "${JOB_RECORD}"; do
  if [ -e "${TARGET}" ]; then
    printf 'exists|%s\n' "${TARGET}"
  else
    printf 'absent|%s\n' "${TARGET}"
  fi
done

for TARGET in "${SUMMARY}" "${SUMMARY}.partial" "${AUDIT}" "${AUDIT}.partial" "${JOB_SCRIPT}" "${JOB_RECORD}"; do
  if [ -e "${TARGET}" ]; then
    echo "create-only target already exists: ${TARGET}" >&2
    exit 2
  fi
done

SOURCE_SCRIPT="${HOME}/hpc_mailbox/inbox/zhenjiang-d32-diff-ukf/aggregate_audit_v2.slurm"
EXPECTED_SCRIPT_BYTES=5494
EXPECTED_SCRIPT_SHA256="6016bdb2ac993ba25a09275953f8ae8a56c310dac13f03fc6f6c895019cf2e09"
if [ ! -f "${SOURCE_SCRIPT}" ] || [ -L "${SOURCE_SCRIPT}" ]; then
  echo "mailbox aggregation script is absent or symbolic" >&2
  exit 2
fi
ACTUAL_SCRIPT_BYTES="$(stat -c '%s' "${SOURCE_SCRIPT}")"
ACTUAL_SCRIPT_SHA256="$(sha256sum "${SOURCE_SCRIPT}" | awk '{print $1}')"
if [ "${ACTUAL_SCRIPT_BYTES}" != "${EXPECTED_SCRIPT_BYTES}" ] || \
   [ "${ACTUAL_SCRIPT_SHA256}" != "${EXPECTED_SCRIPT_SHA256}" ]; then
  echo "mailbox aggregation script identity changed" >&2
  exit 2
fi

mkdir -p "${EVALUATION_ROOT}/jobs" "${EVALUATION_ROOT}/logs"
install -m 0555 "${SOURCE_SCRIPT}" "${JOB_SCRIPT}"
test "$(stat -c '%s' "${JOB_SCRIPT}")" = "${EXPECTED_SCRIPT_BYTES}"
test "$(sha256sum "${JOB_SCRIPT}" | awk '{print $1}')" = "${EXPECTED_SCRIPT_SHA256}"

JOB_ID="$(sbatch --parsable "${JOB_SCRIPT}")"
case "${JOB_ID}" in
  ''|*[!0-9]*)
    echo "scheduler returned an invalid job identifier: ${JOB_ID}" >&2
    exit 2
    ;;
esac
echo "AGGREGATE_AUDIT_JOB_ID=${JOB_ID}"
scontrol show job -o "${JOB_ID}"
exit 0

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
  --format=JobID,JobIDRaw,JobName,Partition,State,ExitCode,Elapsed,Start,End,NodeList,AllocTRES || true

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
      sacct -X -n -j "${JOB_ID}" -P --format=JobID,State,ExitCode |
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
