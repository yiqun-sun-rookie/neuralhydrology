#!/bin/bash
# Read-only snapshot of the unique v2r5 neural-training job and its isolated outputs.
# This auxiliary command submits, cancels, signals, or mutates nothing.
set -o pipefail

ROOT=/data1/home/sunyiq/kalmannet_tukf09_455_basin_zero_validation_target_variance_revision_v1_a800_exclusive_v2r5_20260901
RESULTS_ROOT="${ROOT}/bundle/kalmannet/results/tukf09_455_basin_zero_validation_target_variance_revision_v1"
JOB_ID=217939
JOB_ID_FILE="${ROOT}/status/training_job_id.txt"
SUBMISSION_LOCK="${ROOT}/status/training_submission.lock"
STDOUT="${ROOT}/logs/training-${JOB_ID}.out"
STDERR="${ROOT}/logs/training-${JOB_ID}.err"
INNER_LOG_ROOT="${RESULTS_ROOT}/logs/formal_training_sequence"
NEURAL_CONTROL_ROOT="${RESULTS_ROOT}/control/neural"

echo "=== SNAPSHOT TIME ==="
date --iso-8601=seconds 2>&1 || date 2>&1
hostname -s 2>&1

echo "=== SLURM STATE ==="
sacct -j "${JOB_ID}" -n -P \
  --format=JobIDRaw,JobName,Partition,State,ExitCode,NodeList,Elapsed,Start,End 2>&1 || true
squeue -j "${JOB_ID}" -o '%.18i %.30j %.10P %.10T %.24R %.10M %.20S' 2>&1 || true
sstat -j "${JOB_ID}.batch" --format=JobID,AveCPU,AveRSS,MaxRSS,MaxVMSize -P 2>&1 || true

echo "=== UNIQUE SUBMISSION EVIDENCE ==="
for item in "${SUBMISSION_LOCK}" "${JOB_ID_FILE}"; do
  if [[ -e "${item}" || -L "${item}" ]]; then
    stat -c 'PRESENT|%n|type=%F|mode=%a|links=%h|size=%s|mtime=%Y' "${item}" 2>&1 || true
  else
    echo "ABSENT|${item}"
  fi
done
if [[ -f "${JOB_ID_FILE}" && ! -L "${JOB_ID_FILE}" ]]; then
  printf 'JOB_ID_FILE_CONTENT='
  tr -d '\r\n' < "${JOB_ID_FILE}" 2>&1 || true
  printf '\n'
fi

echo "=== TRAINING LOG SNAPSHOT ==="
for item in "${STDOUT}" "${STDERR}"; do
  if [[ -f "${item}" && ! -L "${item}" ]]; then
    stat -c '%n|type=%F|mode=%a|links=%h|size=%s|mtime=%Y' "${item}" 2>&1 || true
    echo "LOG_SHA256=$(sha256sum "${item}" | awk '{print $1}')"
    echo "--- tail $(basename "${item}") ---"
    tail -n 120 "${item}" 2>&1 || true
  else
    echo "LOG_ABSENT_OR_IRREGULAR|${item}"
  fi
done

echo "=== INNER CONTROLLER LOG SNAPSHOT ==="
for name in \
  verify_filter_rebinding_controller.stdout.log \
  verify_filter_rebinding_controller.stderr.log \
  neural_controller.stdout.log \
  neural_controller.stderr.log; do
  item="${INNER_LOG_ROOT}/${name}"
  if [[ -f "${item}" && ! -L "${item}" ]]; then
    stat -c '%n|type=%F|mode=%a|links=%h|size=%s|mtime=%Y' "${item}" 2>&1 || true
    echo "INNER_LOG_SHA256=$(sha256sum "${item}" | awk '{print $1}')"
    echo "--- tail ${name} ---"
    tail -n 400 "${item}" 2>&1 || true
  else
    echo "INNER_LOG_ABSENT_OR_IRREGULAR|${item}"
  fi
done

echo "=== NEURAL CONTROLLER CONTROL SNAPSHOT ==="
if [[ -d "${NEURAL_CONTROL_ROOT}" && ! -L "${NEURAL_CONTROL_ROOT}" ]]; then
  find "${NEURAL_CONTROL_ROOT}" -mindepth 1 -maxdepth 2 -printf '%y|%m|%n|%s|%p\n' 2>&1 | LC_ALL=C sort || true
  if [[ -f "${NEURAL_CONTROL_ROOT}/events.jsonl" && ! -L "${NEURAL_CONTROL_ROOT}/events.jsonl" ]]; then
    echo "NEURAL_EVENTS_SHA256=$(sha256sum "${NEURAL_CONTROL_ROOT}/events.jsonl" | awk '{print $1}')"
    tail -n 100 "${NEURAL_CONTROL_ROOT}/events.jsonl" 2>&1 || true
  fi
else
  echo "NEURAL_CONTROL_ROOT_ABSENT_OR_IRREGULAR"
fi

echo "=== NEURAL UNIT SNAPSHOT ==="
NEURAL_ROOT="${RESULTS_ROOT}/neural"
if [[ -d "${NEURAL_ROOT}" && ! -L "${NEURAL_ROOT}" ]]; then
  unit_directory_count=0
  complete_manifest_count=0
  for lead in 1 2 3; do
    for seed in 0 1 2; do
      unit="${NEURAL_ROOT}/lead_${lead}_seed_${seed}"
      if [[ -d "${unit}" && ! -L "${unit}" ]]; then
        unit_directory_count=$((unit_directory_count + 1))
        checkpoints=$(find "${unit}/checkpoints" -mindepth 1 -maxdepth 1 -type f -name 'epoch_*.pt' -printf '.' 2>/dev/null | wc -c | tr -d '[:space:]')
        if [[ -f "${unit}/manifest.sha256.json" && ! -L "${unit}/manifest.sha256.json" ]]; then
          complete_manifest_count=$((complete_manifest_count + 1))
          echo "UNIT|lead_${lead}_seed_${seed}|manifest=present|checkpoints=${checkpoints}"
        else
          echo "UNIT|lead_${lead}_seed_${seed}|manifest=absent|checkpoints=${checkpoints}"
        fi
      else
        echo "UNIT|lead_${lead}_seed_${seed}|directory=absent|checkpoints=0"
      fi
    done
  done
  echo "NEURAL_UNIT_DIRECTORY_COUNT=${unit_directory_count}"
  echo "NEURAL_COMPLETE_MANIFEST_COUNT=${complete_manifest_count}"
  if [[ -d "${NEURAL_ROOT}/shared" && ! -L "${NEURAL_ROOT}/shared" ]]; then
    echo "NEURAL_SHARED_DIRECTORY=present"
  else
    echo "NEURAL_SHARED_DIRECTORY=absent"
  fi
else
  echo "NEURAL_ROOT=absent"
  echo "NEURAL_UNIT_DIRECTORY_COUNT=0"
  echo "NEURAL_COMPLETE_MANIFEST_COUNT=0"
fi

echo "=== TRAINING EVENT AND VERIFICATION SNAPSHOT ==="
EVENTS="${RESULTS_ROOT}/control/formal_training_sequence/events.jsonl"
if [[ -f "${EVENTS}" && ! -L "${EVENTS}" ]]; then
  stat -c '%n|type=%F|mode=%a|links=%h|size=%s|mtime=%Y' "${EVENTS}" 2>&1 || true
  tail -n 20 "${EVENTS}" 2>&1 || true
else
  echo "TRAINING_EVENTS_ABSENT_OR_IRREGULAR"
fi
shopt -s nullglob
verifications=("${ROOT}"/status/training_verification*.json)
shopt -u nullglob
echo "TRAINING_VERIFICATION_FILE_COUNT=${#verifications[@]}"
for item in "${verifications[@]}"; do
  stat -c 'PRESENT|%n|type=%F|mode=%a|links=%h|size=%s|mtime=%Y' "${item}" 2>&1 || true
  if [[ -f "${item}" && ! -L "${item}" ]]; then
    echo "VERIFICATION_SHA256=$(sha256sum "${item}" | awk '{print $1}')"
  fi
done

echo "=== FORMAL EVALUATION HOLD SNAPSHOT ==="
evaluation_present=0
for name in selection evaluation independent formal_evaluation formal_evaluation_independent; do
  item="${RESULTS_ROOT}/${name}"
  if [[ -e "${item}" || -L "${item}" ]]; then
    echo "PRESENT|${item}"
    evaluation_present=$((evaluation_present + 1))
  else
    echo "ABSENT|${item}"
  fi
done
echo "FORMAL_EVALUATION_OUTPUT_COUNT=${evaluation_present}"
echo "TUKF09_455_V2R5_NEURAL_JOB_READ_ONLY_SNAPSHOT_COMPLETED"
