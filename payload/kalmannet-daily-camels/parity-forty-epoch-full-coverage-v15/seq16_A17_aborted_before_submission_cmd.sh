#!/usr/bin/env bash
set -Eeuo pipefail

MAILBOX_ROOT="/data1/home/${USER}/hpc_mailbox"
PAYLOAD_DIRECTORY="${MAILBOX_ROOT}/payload/kalmannet-daily-camels/parity-forty-epoch-full-coverage-v15"
BASE="/data1/home/sunyiq/kalmannet_daily_camels_parity_20260824"
SOURCE_A17="${BASE}/source_A17_seq16"
RUN_PARENT="${BASE}/runs"
STATUS_DIRECTORY="${BASE}/status"
LOG_DIRECTORY="${BASE}/logs"
OUTBOX_DIRECTORY="${MAILBOX_ROOT}/outbox/kalmannet-daily-camels"

A05_ID="DAILY_CAMELS_UKF_PARITY_KNET_FULL_STATE_EXACT_REPLAY_DTYPE_REPAIR_V3_20260825_A05"
A06_ID="DAILY_CAMELS_UKF_PARITY_KNET_FULL_STATE_CAUSAL_REPLAY_DTYPE_REPAIR_V3_20260825_A06"
A17_ID="DAILY_CAMELS_KNET_FIXED_FULL_TRAINING_COVERAGE_FORTY_EPOCH_V1_20260825_A17"
A17_ARCHIVE="${PAYLOAD_DIRECTORY}/${A17_ID}.tar.gz"
A17_SHA256="5cefd689617787beac0b7810bf13a1c2bdf1f199281e7388ffa3e92e9c603028"
A17_SIZE=228405
A17_OUTER_MANIFEST="${PAYLOAD_DIRECTORY}/A17_bundle_manifest.sha256.json"
A17_OUTER_MANIFEST_SHA256="c26eb67c9bf3c4c3c78b31112a7971d9a7614fc89c67f97d600f72b9119abe07"
A17_OUTER_MANIFEST_SIZE=8282
A17_INTERNAL_MANIFEST_SHA256="24dfee451c311226885ca8b5f436b373e1cf42d840a6359d613a16d7145dc98c"
A17_CONFIG_SHA256="cd222bfcdf2b0e8c4c815aa917a4a23770c24120a390e8558ed4322bd064c742"
HOST_ADMISSION_MIN_BYTES=2819432448
GPU_ADMISSION_MIN_FREE_MIB=826
EXACT_REPLAY_GATE="${STATUS_DIRECTORY}/replay_gate_${A05_ID}.json"
CAUSAL_REPLAY_GATE="${STATUS_DIRECTORY}/replay_gate_${A06_ID}.json"

EVIDENCE_NAME="DAILY_CAMELS_KNET_FIXED_FULL_TRAINING_COVERAGE_FORTY_EPOCH_V1_A17_SEQ16_evidence.tar.gz"
EVIDENCE_ARCHIVE="${OUTBOX_DIRECTORY}/${EVIDENCE_NAME}"
START_EPOCH="$(date +%s)"
SOFT_DEADLINE_EPOCH="$((START_EPOCH + 9000))"
NAMESPACE_VERIFIED=0
ALL_SUBMITTED_JOBS_TERMINAL=0
FINAL_STATUS="SEQ16_A17_STARTED"
declare -a JOB_IDS=()

package_evidence() {
  local command_exit_code="$1"
  set +e
  if [[ "$NAMESPACE_VERIFIED" -ne 1 ]]; then
    printf 'evidence_archive=NOT_CREATED namespace_not_verified=1 status=%s exit_code=%s\n' \
      "$FINAL_STATUS" "$command_exit_code"
    return 0
  fi
  mkdir -p "$OUTBOX_DIRECTORY"
  if [[ -e "$EVIDENCE_ARCHIVE" ]]; then
    printf 'evidence_archive=NOT_REPLACED existing=%s status=%s exit_code=%s\n' \
      "$EVIDENCE_ARCHIVE" "$FINAL_STATUS" "$command_exit_code"
    return 0
  fi

  local snapshot="${BASE}/seq16_snapshot_$$"
  mkdir -p "$snapshot/status" "$snapshot/logs" "$snapshot/source"
  printf '%s\n' "$FINAL_STATUS" > "${snapshot}/final_status.txt"
  printf '%s\n' "$command_exit_code" > "${snapshot}/command_exit_code.txt"
  printf '%s\n' "${JOB_IDS[@]:-}" > "${snapshot}/submitted_job_ids.txt"
  date -u +%Y-%m-%dT%H:%M:%SZ > "${snapshot}/snapshot_time_utc.txt"
  if [[ "${#JOB_IDS[@]}" -gt 0 ]]; then
    local job_csv
    job_csv="$(IFS=,; printf '%s' "${JOB_IDS[*]}")"
    squeue -h -j "$job_csv" -o '%i|%T|%R|%M|%l' \
      > "${snapshot}/squeue_snapshot.txt" 2>&1 || true
    sacct -P --units=K -j "$job_csv" \
      --format=JobIDRaw,JobName,Partition,AllocCPUS,ReqMem,AllocTRES,State,ExitCode,Elapsed,Start,End,MaxRSS,MaxVMSize,AveRSS \
      > "${snapshot}/sacct_snapshot.txt" 2>&1 || true
  fi

  local candidate
  for candidate in \
    "${STATUS_DIRECTORY}"/seq16_* \
    "${STATUS_DIRECTORY}"/probe-"${A17_ID}"-*.json \
    "${STATUS_DIRECTORY}"/entry-probe-"${A17_ID}"-*.json \
    "${STATUS_DIRECTORY}"/train-preflight-"${A17_ID}"-*.json \
    "${STATUS_DIRECTORY}"/train-gpu-resources-"${A17_ID}"-*.csv \
    "${STATUS_DIRECTORY}"/train-cgroup-resources-"${A17_ID}"-*.txt \
    "$EXACT_REPLAY_GATE" "$CAUSAL_REPLAY_GATE"; do
    [[ -f "$candidate" && ! -L "$candidate" ]] || continue
    cp -p "$candidate" "${snapshot}/status/"
  done
  for job_id in "${JOB_IDS[@]:-}"; do
    for candidate in "${LOG_DIRECTORY}"/*-"${job_id}".out "${LOG_DIRECTORY}"/*-"${job_id}".err; do
      [[ -f "$candidate" && ! -L "$candidate" ]] || continue
      cp -p "$candidate" "${snapshot}/logs/"
    done
  done
  if [[ -f "${SOURCE_A17}/bundle_manifest.json" && ! -L "${SOURCE_A17}/bundle_manifest.json" ]]; then
    cp -p "${SOURCE_A17}/bundle_manifest.json" "${snapshot}/source/"
  fi
  if [[ "$ALL_SUBMITTED_JOBS_TERMINAL" -eq 1 && \
        -d "${RUN_PARENT}/${A17_ID}" && ! -L "${RUN_PARENT}/${A17_ID}" ]]; then
    if find "${RUN_PARENT}/${A17_ID}" -type l -print -quit | grep -q .; then
      printf 'evidence_archive=CREATE_FAILED symbolic_run_member=1 status=%s exit_code=%s\n' \
        "$FINAL_STATUS" "$command_exit_code"
      return 0
    fi
    cp -a "${RUN_PARENT}/${A17_ID}" "${snapshot}/run"
  fi

  local temporary_archive="${OUTBOX_DIRECTORY}/.${EVIDENCE_NAME}.$$"
  tar -czf "$temporary_archive" -C "$BASE" "$(basename "$snapshot")"
  if [[ -s "$temporary_archive" && ! -e "$EVIDENCE_ARCHIVE" ]]; then
    mv "$temporary_archive" "$EVIDENCE_ARCHIVE"
    printf 'evidence_archive=%s\n' "$EVIDENCE_ARCHIVE"
    printf 'evidence_archive_sha256=%s\n' "$(sha256sum "$EVIDENCE_ARCHIVE" | awk '{print $1}')"
    printf 'evidence_archive_size=%s\n' "$(stat -c '%s' "$EVIDENCE_ARCHIVE")"
    printf 'evidence_status=%s command_exit_code=%s all_jobs_terminal=%s\n' \
      "$FINAL_STATUS" "$command_exit_code" "$ALL_SUBMITTED_JOBS_TERMINAL"
  else
    printf 'evidence_archive=CREATE_FAILED status=%s exit_code=%s\n' \
      "$FINAL_STATUS" "$command_exit_code"
  fi
}

on_exit() {
  local command_exit_code="$?"
  trap - EXIT INT TERM
  package_evidence "$command_exit_code"
  exit "$command_exit_code"
}
trap on_exit EXIT
trap 'FINAL_STATUS="SEQ16_A17_INTERRUPTED_PARTIAL_PENDING"; exit 143' INT TERM

archive_identity_check() {
  local path="$1" expected_sha256="$2" expected_size="$3"
  local actual_sha256 actual_size
  [[ -f "$path" && ! -L "$path" ]] || {
    echo "payload member absent or symbolic: $path" >&2
    return 60
  }
  actual_sha256="$(sha256sum "$path" | awk '{print $1}')"
  actual_size="$(stat -c '%s' "$path")"
  [[ "$actual_sha256" = "$expected_sha256" ]] || {
    echo "payload SHA-256 differs: $path" >&2
    return 61
  }
  [[ "$actual_size" = "$expected_size" ]] || {
    echo "payload size differs: $path" >&2
    return 62
  }
}

accounting_record_once() {
  local job_id="$1"
  sacct -X -n -P -j "$job_id" --format=JobIDRaw,State,ExitCode 2>/dev/null | \
    awk -F'|' -v id="$job_id" '$1 == id {print $2 "|" $3; exit}'
}

wait_for_job() {
  local job_id="$1" live_state record state
  while (( $(date +%s) < SOFT_DEADLINE_EPOCH )); do
    live_state="$(squeue -h -j "$job_id" -o '%T' 2>/dev/null | head -1 | tr -d '[:space:]' || true)"
    record="$(accounting_record_once "$job_id" || true)"
    state="${record%%|*}"
    state="${state%%+*}"
    case "$state" in
      COMPLETED|FAILED|CANCELLED*|TIMEOUT|OUT_OF_MEMORY|NODE_FAIL|PREEMPTED|BOOT_FAIL|DEADLINE|REVOKED|SPECIAL_EXIT)
        [[ -z "$live_state" ]] && return 0
        ;;
      *) ;;
    esac
    sleep 10
  done
  return 124
}

require_completed_zero() {
  local job_id="$1" label="$2" record state exit_code
  record="$(accounting_record_once "$job_id" || true)"
  state="${record%%|*}"
  exit_code="${record#*|}"
  state="${state%%+*}"
  printf 'accounting label=%s job_id=%s state=%s exit_code=%s\n' \
    "$label" "$job_id" "${state:-UNKNOWN}" "${exit_code:-UNKNOWN}"
  [[ "$state" = "COMPLETED" && "$exit_code" = "0:0" ]]
}

classify_tests_completion() {
  local job_id="$1" record state exit_code
  record="$(accounting_record_once "$job_id" || true)"
  state="${record%%|*}"
  exit_code="${record#*|}"
  state="${state%%+*}"
  printf 'accounting label=tests_A17 job_id=%s state=%s exit_code=%s\n' \
    "$job_id" "${state:-UNKNOWN}" "${exit_code:-UNKNOWN}"
  if [[ "$state" = "COMPLETED" && "$exit_code" = "0:0" ]]; then
    TEST_EXIT_CLASS="passed"
    return 0
  fi
  if [[ "$state" = "FAILED" && "$exit_code" = "77:0" ]]; then
    TEST_EXIT_CLASS="skipped_pytest_unavailable"
    return 0
  fi
  TEST_EXIT_CLASS="failed_or_ambiguous"
  return 1
}

classify_train_completion() {
  local job_id="$1" record state exit_code
  record="$(accounting_record_once "$job_id" || true)"
  state="${record%%|*}"
  exit_code="${record#*|}"
  state="${state%%+*}"
  printf 'accounting label=train_A17 job_id=%s state=%s exit_code=%s\n' \
    "$job_id" "${state:-UNKNOWN}" "${exit_code:-UNKNOWN}"
  if [[ "$state" = "COMPLETED" && "$exit_code" = "0:0" ]]; then
    TRAIN_EXIT_CLASS="scientific_gate_pass"
    return 0
  fi
  if [[ "$state" = "FAILED" && "$exit_code" = "2:0" ]]; then
    TRAIN_EXIT_CLASS="scientific_gate_fail_after_technical_completion"
    return 0
  fi
  TRAIN_EXIT_CLASS="technical_or_scheduler_failure"
  return 1
}

require_lock_cleared() {
  local lock_path="$1" attempt
  for attempt in 1 2 3 4 5 6 7 8 9 10; do
    [[ ! -e "$lock_path" ]] && return 0
    sleep 1
  done
  echo "phase owner lock remains after terminal accounting: $lock_path" >&2
  return 1
}

submit_probe() {
  local raw job_id
  raw="$(cd "$SOURCE_A17" && sbatch --parsable --mem=0 \
    hpc/daily_camels_ukf_knet_parity/submit_probe_gpu.slurm)"
  job_id="${raw%%;*}"
  case "$job_id" in
    ''|*[!0-9]*) echo "invalid Slurm probe job id: ${raw}" >&2; return 63 ;;
  esac
  printf '%s\n' "$job_id" > "${STATUS_DIRECTORY}/seq16_probe_A17_job_id.txt"
  JOB_IDS+=("$job_id")
  SUBMITTED_JOB_ID="$job_id"
}

submit_tests() {
  local raw job_id
  raw="$(sbatch --parsable --mem=0 -p hgpu2p -N 1 -n 1 --cpus-per-task=2 \
    --gres=gpu:1 -t 00:15:00 --exclude=ngu002 -J daily-parity-tests \
    -o "${LOG_DIRECTORY}/tests-%j.out" -e "${LOG_DIRECTORY}/tests-%j.err" \
    --chdir="$SOURCE_A17" \
    --wrap="set -euo pipefail; set +u; source /data1/home/${USER}/miniconda3/etc/profile.d/conda.sh; conda activate nh_final; set -u; export PYTHONDONTWRITEBYTECODE=1 OMP_NUM_THREADS=2 MKL_NUM_THREADS=2 OPENBLAS_NUM_THREADS=2 NUMEXPR_NUM_THREADS=2; python -c 'import importlib.util,sys; available=importlib.util.find_spec(\"pytest\") is not None; print(\"pytest_available=\" + str(available).lower()); sys.exit(0 if available else 77)'; python -m pytest -q -p no:cacheprovider --maxfail=1 tests/test_daily_camels_ukf_knet_parity_contract.py tests/test_daily_camels_ukf_knet_parity_runner.py tests/test_knet_native_hbvlite_full_state.py tests/test_run_daily_camels_ukf_knet_parity_entry.py tests/test_daily_camels_ukf_knet_parity_hpc_preflight.py")"
  job_id="${raw%%;*}"
  case "$job_id" in
    ''|*[!0-9]*) echo "invalid Slurm test job id: ${raw}" >&2; return 64 ;;
  esac
  printf '%s\n' "$job_id" > "${STATUS_DIRECTORY}/seq16_tests_A17_job_id.txt"
  JOB_IDS+=("$job_id")
  SUBMITTED_JOB_ID="$job_id"
}

submit_train() {
  local raw job_id
  raw="$(cd "$SOURCE_A17" && sbatch --parsable --mem=0 \
    --export=ALL,PARITY_EXACT_REPLAY_GATE="${EXACT_REPLAY_GATE}",PARITY_CAUSAL_REPLAY_GATE="${CAUSAL_REPLAY_GATE}",PARITY_HOST_ADMISSION_MIN_BYTES="${HOST_ADMISSION_MIN_BYTES}",PARITY_GPU_ADMISSION_MIN_FREE_MIB="${GPU_ADMISSION_MIN_FREE_MIB}" \
    hpc/daily_camels_ukf_knet_parity/submit_train_gpu.slurm)"
  job_id="${raw%%;*}"
  case "$job_id" in
    ''|*[!0-9]*) echo "invalid Slurm training job id: ${raw}" >&2; return 65 ;;
  esac
  printf '%s\n' "$job_id" > "${STATUS_DIRECTORY}/seq16_train_A17_job_id.txt"
  JOB_IDS+=("$job_id")
  SUBMITTED_JOB_ID="$job_id"
}

test ! -e "$EVIDENCE_ARCHIVE" || {
  echo "refusing to replace existing seq16 evidence: $EVIDENCE_ARCHIVE" >&2
  exit 66
}
[[ -d "$BASE" && ! -L "$BASE" ]] || {
  echo "daily parity root is absent or symbolic: $BASE" >&2
  exit 67
}
for required_directory in "$RUN_PARENT" "$STATUS_DIRECTORY" "$LOG_DIRECTORY"; do
  [[ -d "$required_directory" && ! -L "$required_directory" ]] || {
    echo "daily parity directory is absent or symbolic: $required_directory" >&2
    exit 68
  }
done
[[ ! -e "$SOURCE_A17" ]] || {
  echo "seq16 source directory already exists; refusing to replace it" >&2
  exit 69
}
[[ ! -e "${RUN_PARENT}/${A17_ID}" ]] || {
  echo "A17 run directory already exists; refusing duplicate submission" >&2
  exit 70
}
if find "$STATUS_DIRECTORY" -maxdepth 1 -type f -name 'seq16_*' -print -quit | grep -q .; then
  echo "seq16 already recorded status evidence; refusing duplicate submission" >&2
  exit 71
fi
for phase in probe replay train; do
  [[ ! -e "${STATUS_DIRECTORY}/locks/${A17_ID}.${phase}.lock" ]] || {
    echo "A17 phase lock already exists: ${phase}" >&2
    exit 72
  }
done
for gate in "$EXACT_REPLAY_GATE" "$CAUSAL_REPLAY_GATE"; do
  [[ -f "$gate" && ! -L "$gate" ]] || {
    echo "required replay gate is absent or symbolic: $gate" >&2
    exit 73
  }
done
NAMESPACE_VERIFIED=1
FINAL_STATUS="SEQ16_A17_NAMESPACE_ABSENCE_VERIFIED"

archive_identity_check "$A17_ARCHIVE" "$A17_SHA256" "$A17_SIZE"
archive_identity_check "$A17_OUTER_MANIFEST" "$A17_OUTER_MANIFEST_SHA256" "$A17_OUTER_MANIFEST_SIZE"
mkdir "$SOURCE_A17"
tar -xzf "$A17_ARCHIVE" -C "$SOURCE_A17"

set +u
source "/data1/home/${USER}/miniconda3/etc/profile.d/conda.sh"
conda activate nh_final
set -u
export PYTHONDONTWRITEBYTECODE=1

python - "$SOURCE_A17" "$A17_ARCHIVE" "$A17_OUTER_MANIFEST" \
  "$A17_ID" "$A05_ID" "$A06_ID" "$EXACT_REPLAY_GATE" "$CAUSAL_REPLAY_GATE" \
  "$A17_SHA256" "$A17_OUTER_MANIFEST_SHA256" \
  "$A17_INTERNAL_MANIFEST_SHA256" "$A17_CONFIG_SHA256" <<'PY'
import hashlib
import json
import math
from pathlib import Path
import sys

source = Path(sys.argv[1])
archive_path, outer_path = map(Path, sys.argv[2:4])
active_id, exact_id, causal_id = sys.argv[4:7]
exact_gate_path, causal_gate_path = map(Path, sys.argv[7:9])
archive_sha, outer_sha, internal_sha, config_sha = sys.argv[9:13]

def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()

internal_path = source / "bundle_manifest.json"
if [sha256(archive_path), sha256(outer_path), sha256(internal_path)] != [
    archive_sha, outer_sha, internal_sha
]:
    raise SystemExit("seq16 A17 archive or manifest identity differs")
outer = json.loads(outer_path.read_text(encoding="utf-8"))
manifest = json.loads(internal_path.read_text(encoding="utf-8"))
active_member = manifest["active_config_member"]
active_path = source / active_member
if (
    outer.get("experiment_id") != active_id
    or outer.get("archive_sha256") != archive_sha
    or outer.get("internal_manifest_sha256") != internal_sha
    or outer.get("reserved_data_member_count") != 0
    or manifest.get("reserved_data_member_count") != 0
    or manifest.get("member_sha256", {}).get(active_member) != config_sha
    or sha256(active_path) != config_sha
):
    raise SystemExit("seq16 A17 bundle inventory differs")
config = json.loads(active_path.read_text(encoding="utf-8"))
optimization = config.get("optimization", {})
model = config.get("model", {})
reference = config.get("reference", {})
expected_starts = [
    0, 100, 201, 301, 401, 501, 602, 702, 802, 903, 1003, 1103, 1204,
    1304, 1404, 1504, 1605, 1705, 1805, 1906, 2006, 2106, 2206, 2307, 2407,
]
if (
    config.get("experiment_id") != active_id
    or config.get("basin_id") != "09035800"
    or config.get("data", {}).get("cadence") != "daily"
    or config.get("initialization", {}).get("execution_mode") != "causal_shared_spinup"
    or config.get("execution_policy", {}).get("allow_training") is not True
    or model.get("official_knet_sha256")
       != "934570d3c840e9d57b8fbddf3a018dc29e190cdd712fc9daaf442e383f74d843"
    or model.get("correction_scope") != "full_eighteen_dimensional_state_correction"
    or optimization.get("training_objective") != "physical_unit_multilead_mse"
    or optimization.get("checkpoint_objective") != "physical_unit_multilead_mse"
    or optimization.get("training_epochs") != 40
    or optimization.get("steps_per_epoch") != 1
    or optimization.get("segments_per_optimizer_step") != 25
    or optimization.get("fixed_training_segment_start_indices") != expected_starts
    or not math.isclose(float(optimization.get("learning_rate")), 0.0005, rel_tol=0.0, abs_tol=0.0)
    or reference.get("reference_status")
       != "frozen_from_seq6_causal_replay_seq12_a15_and_seq15_a16"
    or reference.get("a15_one_step_best_checkpoint_objective") != 0.28580983607261695
    or reference.get("a15_one_step_best_nse_by_lead")
       != [0.7931683983822845, 0.7837451386292139, 0.7756788158494483]
    or reference.get("a16_ten_epoch_best_checkpoint_objective")
       != 0.07951907715501967
    or reference.get("a16_ten_epoch_best_nse_by_lead")
       != [0.9649952670432475, 0.9397019701611595, 0.9155408779559143]
    or reference.get("a16_evidence_archive_sha256")
       != "c6ee59e9dbd233858ef3bd310eca41e76d23152aa42d7fba6d5e1d1d414123d9"
    or reference.get("a16_result_summary_sha256")
       != "07cf27a7f3d18d1a3428f829e2486fcd874157ab678d1f75ddebdfc709b8c71b"
):
    raise SystemExit("seq16 A17 scientific or optimization contract differs")
requirements = config.get("replay_gate_requirements", {})
for name, path, expected_id in (
    ("exact", exact_gate_path, exact_id),
    ("causal", causal_gate_path, causal_id),
):
    receipt = json.loads(path.read_text(encoding="utf-8"))
    requirement = requirements.get(name, {})
    if (
        receipt.get("status") != "REPLAY_PASS"
        or receipt.get("experiment_id") != expected_id
        or sha256(path) != requirement.get("receipt_sha256")
    ):
        raise SystemExit(f"seq16 A17 replay gate differs: {name}")
print(json.dumps({
    "status": "SEQ16_A17_OFFLINE_IDENTITY_PASS",
    "experiment_id": active_id,
    "training_epochs": 40,
    "expected_optimizer_steps": 40,
    "expected_forecast_target_events": 306000,
    "correction_scope": model["correction_scope"],
}, sort_keys=True))
PY

python -u "${SOURCE_A17}/hpc/daily_camels_ukf_knet_parity/preflight.py" \
  --bundle-root "$SOURCE_A17" --phase probe --offline-bundle-check \
  --report "${STATUS_DIRECTORY}/seq16_offline_A17.json"
FINAL_STATUS="SEQ16_A17_OFFLINE_BUNDLE_VERIFIED"

echo '=== SUBMIT READ-ONLY A17 SCHEDULED GPU PROBE ==='
submit_probe
PROBE_JOB_ID="$SUBMITTED_JOB_ID"
FINAL_STATUS="SEQ16_A17_PROBE_SUBMITTED"
if ! wait_for_job "$PROBE_JOB_ID"; then
  FINAL_STATUS="SEQ16_A17_PROBE_PARTIAL_PENDING"
  echo "soft deadline reached while probe is pending; no tests or training submitted" >&2
  exit 74
fi
ALL_SUBMITTED_JOBS_TERMINAL=1
require_completed_zero "$PROBE_JOB_ID" "probe_A17" || {
  FINAL_STATUS="SEQ16_A17_PROBE_HARD_STOP"
  exit 75
}
require_lock_cleared "${STATUS_DIRECTORY}/locks/${A17_ID}.probe.lock" || {
  FINAL_STATUS="SEQ16_A17_PROBE_LOCK_HARD_STOP"
  exit 76
}
python - "$STATUS_DIRECTORY" "$A17_ID" "$PROBE_JOB_ID" \
  "$HOST_ADMISSION_MIN_BYTES" "$GPU_ADMISSION_MIN_FREE_MIB" <<'PY'
import json
from pathlib import Path
import sys

status, experiment_id, job_id = Path(sys.argv[1]), sys.argv[2], sys.argv[3]
host_min, gpu_min = int(sys.argv[4]), int(sys.argv[5])
scheduled = json.loads(
    (status / f"probe-{experiment_id}-{job_id}.json").read_text(encoding="utf-8")
)
entry = json.loads(
    (status / f"entry-probe-{experiment_id}-{job_id}.json").read_text(encoding="utf-8")
)
if (
    scheduled.get("status") != "PREFLIGHT_PASS"
    or scheduled.get("phase") != "probe"
    or scheduled.get("experiment_id") != experiment_id
    or scheduled.get("run_directory_absent") is not True
    or scheduled.get("array_members_materialized") != 0
    or scheduled.get("reserved_data_member_count") != 0
    or scheduled.get("torch_imported") is not False
    or scheduled.get("numpy_imported") is not False
    or int(scheduled.get("available_host_memory_bytes") or 0) < host_min
    or int(scheduled.get("cuda_probe_without_torch_import", {}).get("memory_free_mib") or 0)
       < gpu_min
    or entry.get("status") != "PREFLIGHT_PASS"
    or entry.get("phase") != "probe"
    or entry.get("run_directory_absent") is not True
    or entry.get("correction_scope") != "full_eighteen_dimensional_state_correction"
    or entry.get("reserved_evaluation_period_access_authorized") is not False
    or entry.get("array_members_materialized") != 0
    or entry.get("numerical_frameworks_imported_by_entry") != 0
):
    raise SystemExit("seq16 A17 scheduled probe evidence differs")
print(json.dumps({
    "status": "SEQ16_A17_PROBE_PASS",
    "job_id": job_id,
    "hostname": scheduled["hostname"],
    "available_host_memory_bytes": scheduled["available_host_memory_bytes"],
    "gpu": scheduled["cuda_probe_without_torch_import"],
}, sort_keys=True))
PY
FINAL_STATUS="SEQ16_A17_PROBE_PASS"

echo '=== SUBMIT ISOLATED NUMERICAL CONTRACT TESTS ==='
ALL_SUBMITTED_JOBS_TERMINAL=0
submit_tests
TEST_JOB_ID="$SUBMITTED_JOB_ID"
FINAL_STATUS="SEQ16_A17_TESTS_SUBMITTED"
if ! wait_for_job "$TEST_JOB_ID"; then
  FINAL_STATUS="SEQ16_A17_TESTS_PARTIAL_PENDING"
  echo "soft deadline reached while tests are pending; no training submitted" >&2
  exit 77
fi
ALL_SUBMITTED_JOBS_TERMINAL=1
classify_tests_completion "$TEST_JOB_ID" || {
  FINAL_STATUS="SEQ16_A17_TESTS_HARD_STOP"
  exit 78
}
python - "$STATUS_DIRECTORY" "$A17_ID" "$PROBE_JOB_ID" "$TEST_JOB_ID" \
  "$TEST_EXIT_CLASS" <<'PY'
import json
import os
from pathlib import Path
import sys

status = Path(sys.argv[1])
experiment_id, probe_job_id, test_job_id, test_exit_class = sys.argv[2:6]
probe_path = status / f"probe-{experiment_id}-{probe_job_id}.json"
probe = json.loads(probe_path.read_text(encoding="utf-8"))
packages = probe.get("package_availability_without_import", {})
pytest_report = packages.get("pytest", {})
pytest_available = pytest_report.get("available")
if test_exit_class == "passed" and pytest_available is True:
    pass
elif test_exit_class == "skipped_pytest_unavailable" and pytest_available is False:
    pass
else:
    raise SystemExit("seq16 A17 pytest availability and test exit class disagree")
attestation = {
    "status": "SEQ16_A17_TEST_ATTESTATION_PASS",
    "experiment_id": experiment_id,
    "probe_job_id": probe_job_id,
    "test_job_id": test_job_id,
    "pytest_available": pytest_available,
    "test_exit_class": test_exit_class,
}
target = status / "seq16_A17_test_attestation.json"
data = (json.dumps(attestation, sort_keys=True, separators=(",", ":")) + "\n").encode()
descriptor = os.open(target, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
try:
    os.write(descriptor, data)
finally:
    os.close(descriptor)
print(json.dumps(attestation, sort_keys=True))
PY
FINAL_STATUS="SEQ16_A17_TESTS_PASS_OR_ATTESTED_SKIP"

echo '=== SUBMIT TEN-EPOCH FULL-TRAINING-COVERAGE CONVERGENCE DIAGNOSTIC ==='
ALL_SUBMITTED_JOBS_TERMINAL=0
submit_train
TRAIN_JOB_ID="$SUBMITTED_JOB_ID"
FINAL_STATUS="SEQ16_A17_TRAIN_SUBMITTED"
if ! wait_for_job "$TRAIN_JOB_ID"; then
  FINAL_STATUS="SEQ16_A17_TRAIN_PARTIAL_PENDING"
  echo "soft deadline reached while training is pending; the job was not cancelled" >&2
  exit 79
fi
ALL_SUBMITTED_JOBS_TERMINAL=1
if ! classify_train_completion "$TRAIN_JOB_ID"; then
  FINAL_STATUS="SEQ16_A17_TRAIN_HARD_STOP"
  exit 80
fi
require_lock_cleared "${STATUS_DIRECTORY}/locks/${A17_ID}.train.lock" || {
  FINAL_STATUS="SEQ16_A17_TRAIN_LOCK_HARD_STOP"
  exit 81
}
sacct -P --units=K -j "$TRAIN_JOB_ID" \
  --format=JobIDRaw,JobName,Partition,AllocCPUS,ReqMem,AllocTRES,State,ExitCode,Elapsed,Start,End,MaxRSS,MaxVMSize,AveRSS \
  > "${STATUS_DIRECTORY}/seq16_train_A17_sacct_resources.txt"

python - "$RUN_PARENT" "$STATUS_DIRECTORY" "$A17_ID" "$TRAIN_JOB_ID" \
  "$TRAIN_EXIT_CLASS" "$TEST_JOB_ID" "$TEST_EXIT_CLASS" \
  "$HOST_ADMISSION_MIN_BYTES" "$GPU_ADMISSION_MIN_FREE_MIB" <<'PY'
import hashlib
import json
import math
import os
from pathlib import Path
import sys

run_parent, status = map(Path, sys.argv[1:3])
experiment_id, job_id, exit_class, test_job_id, test_exit_class = sys.argv[3:8]
host_min, gpu_min = int(sys.argv[8]), int(sys.argv[9])
run = run_parent / experiment_id

def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()

def is_exact_zero_count(value):
    return type(value) is int and value == 0

required = [
    run / "result_summary.json",
    run / "manifest.sha256.json",
    run / "completion.marker.json",
    run / "epoch_history.json",
    run / "experiment_identity.json",
]
if any(not path.is_file() or path.is_symlink() for path in required):
    raise SystemExit("A17 completed run is missing a required regular file")
if (run / "failure.json").exists() or any(path.is_symlink() for path in run.rglob("*")):
    raise SystemExit("A17 completed run contains failure evidence or symbolic members")

summary = json.loads((run / "result_summary.json").read_text(encoding="utf-8"))
manifest = json.loads((run / "manifest.sha256.json").read_text(encoding="utf-8"))
completion = json.loads((run / "completion.marker.json").read_text(encoding="utf-8"))
history = json.loads((run / "epoch_history.json").read_text(encoding="utf-8"))
identity = json.loads((run / "experiment_identity.json").read_text(encoding="utf-8"))
test_attestation_path = status / "seq16_A17_test_attestation.json"
if not test_attestation_path.is_file() or test_attestation_path.is_symlink():
    raise SystemExit("A17 test attestation is absent or symbolic")
test_attestation = json.loads(test_attestation_path.read_text(encoding="utf-8"))
if (
    test_attestation.get("status") != "SEQ16_A17_TEST_ATTESTATION_PASS"
    or test_attestation.get("experiment_id") != experiment_id
    or test_attestation.get("test_job_id") != test_job_id
    or test_attestation.get("test_exit_class") != test_exit_class
):
    raise SystemExit("A17 test attestation identity differs")
training = summary.get("training", {})
manifest_files = manifest.get("files", {})
for relative, expected_sha in manifest_files.items():
    path = run / relative
    if not path.is_file() or path.is_symlink() or sha256(path) != expected_sha:
        raise SystemExit(f"A17 manifest mismatch: {relative}")
if (
    manifest.get("experiment_id") != experiment_id
    or completion.get("experiment_id") != experiment_id
    or summary.get("experiment_id") != experiment_id
    or identity.get("experiment_id") != experiment_id
    or completion.get("manifest_sha256") != sha256(run / "manifest.sha256.json")
    or completion.get("summary_sha256") != sha256(run / "result_summary.json")
):
    raise SystemExit("A17 completion, manifest, summary, or identity chain differs")

if not isinstance(history, list) or len(history) != 41:
    raise SystemExit("A17 must contain epoch zero plus forty post-zero epochs")
if [row.get("epoch") for row in history] != list(range(41)):
    raise SystemExit("A17 epoch sequence differs")
epoch_objectives = [
    float(row["checkpoint_selection_objective_728_origins_without_warmup"])
    for row in history
]
if not all(math.isfinite(value) and value >= 0.0 for value in epoch_objectives):
    raise SystemExit("A17 checkpoint objective history is invalid")
expected_best_epoch = min(range(41), key=epoch_objectives.__getitem__)
expected_best = epoch_objectives[expected_best_epoch]
epoch_zero = history[0]
expected_2550 = {"1": 2550, "2": 2550, "3": 2550}
expected_712 = {"1": 712, "2": 712, "3": 712}
expected_728 = {"1": 728, "2": 728, "3": 728}
if (
    not math.isclose(epoch_objectives[0], 0.40192019589669764, rel_tol=0.0, abs_tol=1e-15)
    or epoch_zero.get("parameter_sha256")
       != "b4a375c3195cae48c984e9a18cd470746950fda5a5aceec60b6e594f1a352645"
    or epoch_zero.get("fixed_window_prediction_sha256")
       != "17a6f0dbbe145b0262e0b2c1f426c49f1687a29927e8f8348f6ea293e246d91f"
):
    raise SystemExit("A17 epoch-zero anchor differs from the frozen baseline")
a16_epoch_ten = history[10]
if (
    not math.isclose(epoch_objectives[10], 0.07951907715501967,
                     rel_tol=0.0, abs_tol=1e-15)
    or a16_epoch_ten.get("parameter_sha256")
       != "c1597f7f1c5c30a6c12ce05e27dc6a45d0b9dd330422fed07a3346b0430cfbca"
    or a16_epoch_ten.get("fixed_window_prediction_sha256")
       != "0517d0e6d4fb290e0cfe1f70ca1ed22e87b1c2c63618edf2b67d725445d7b440"
    or a16_epoch_ten.get("nse_by_lead_after_warmup")
       != {"1": 0.9649952670432475, "2": 0.9397019701611595,
           "3": 0.9155408779559143}
):
    raise SystemExit("A17 epoch-ten anchor differs from A16")
for epoch, row in enumerate(history[1:], start=1):
    if (
        row.get("optimizer_steps") != epoch
        or row.get("epoch_optimizer_step_count") != 1
        or row.get("sampled_forecast_events") != epoch * 7650
        or row.get("training_sampled_finite_target_event_count_by_lead") != expected_2550
        or row.get("target_count_by_lead_after_warmup") != expected_712
        or row.get("target_count_by_lead_without_warmup") != expected_728
        or row.get("finite_gradients") is not True
        or int(row.get("nonzero_gradient_parameter_tensor_count") or 0) <= 0
        or not math.isfinite(float(row.get("training_objective_physical_unit_multilead_mse")))
    ):
        raise SystemExit(f"A17 epoch-{epoch} training-accounting evidence differs")

plan = training.get("training_segment_plan", {})
replays = training.get("same_segment_step_replays", [])
if (
    plan.get("training_epochs") != 40
    or plan.get("steps_per_epoch") != 1
    or plan.get("expected_optimizer_step_count") != 40
    or plan.get("segments_per_optimizer_step") != 25
    or plan.get("candidate_forecast_target_event_count_all_leads") != 7650
    or plan.get("total_candidate_forecast_target_event_count_all_epochs") != 306000
    or plan.get("complete_eligible_issue_coverage") is not True
    or training.get("optimizer_steps") != 40
    or training.get("sampled_forecast_events") != 306000
    or training.get("epoch_checkpoint_count") != 41
    or training.get("fixed_window_prediction_artifact_count") != 41
    or training.get("best_epoch") != expected_best_epoch
    or not math.isclose(float(training.get("best_checkpoint_objective")), expected_best,
                        rel_tol=0.0, abs_tol=1e-15)
    or not math.isclose(float(training.get("last_validation_checkpoint_objective")),
                        epoch_objectives[-1], rel_tol=0.0, abs_tol=1e-15)
    or len(replays) != 40
):
    raise SystemExit("A17 aggregate training-accounting evidence differs")

expected_starts = [
    0, 100, 201, 301, 401, 501, 602, 702, 802, 903, 1003, 1103, 1204,
    1304, 1404, 1504, 1605, 1705, 1805, 1906, 2006, 2106, 2206, 2307, 2407,
]
strict_flags = []
for step, replay in enumerate(replays, start=1):
    before = float(replay["before_step_objective_physical_unit_multilead_mse"])
    after = float(replay["after_step_objective_physical_unit_multilead_mse"])
    strict = after < before
    constituents = replay.get("training_segment_replays", [])
    if (
        replay.get("optimizer_step") != step
        or replay.get("training_segment_count") != 25
        or replay.get("training_segment_start_indices") != expected_starts
        or not is_exact_zero_count(replay.get("reserved_evaluation_values_used"))
        or replay.get("after_step_recomputed_under_no_grad") is not True
        or replay.get("identical_target_geometry_before_after") is not True
        or replay.get("strict_objective_decrease") is not strict
        or len(constituents) != 25
    ):
        raise SystemExit(f"A17 same-training-batch replay differs at step {step}")
    for start, constituent in zip(expected_starts, constituents, strict=True):
        if (
            constituent.get("segment_start_index_global_inclusive") != start
            or constituent.get("target_count_by_lead_before_step")
               != {"1": 102, "2": 102, "3": 102}
            or constituent.get("target_count_by_lead_after_step")
               != {"1": 102, "2": 102, "3": 102}
            or not is_exact_zero_count(constituent.get("reserved_evaluation_values_used"))
            or constituent.get("after_step_recomputed_under_no_grad") is not True
            or constituent.get("identical_target_geometry_before_after") is not True
        ):
            raise SystemExit(f"A17 constituent replay differs at step {step}, start {start}")
    strict_flags.append(strict)

access = summary.get("access_ledger", {})
zero_access_keys = (
    "evaluation_array_reads",
    "evaluation_metric_count",
    "evaluation_output_count",
    "evaluation_prediction_count",
)
if (
    any(access.get(key) != 0 for key in zero_access_keys)
    or training.get("access_ledger") != access
    or summary.get("correction_scope") != "full_eighteen_dimensional_state_correction"
):
    raise SystemExit("A17 evaluation isolation or correction scope differs")

best_nse = training.get("best_nse_by_lead", {})
if set(best_nse) != {"1", "2", "3"} or not all(
    math.isfinite(float(value)) for value in best_nse.values()
):
    raise SystemExit("A17 best per-lead NSE inventory differs")
failed_gates = training.get("failed_gates", [])
gate_passed = bool(training.get("gate_passed"))
if (
    not isinstance(failed_gates, list)
    or gate_passed != (len(failed_gates) == 0)
    or (exit_class == "scientific_gate_pass") is not gate_passed
    or bool(training.get("same_segment_every_optimizer_step_strictly_decreased"))
       != all(strict_flags)
):
    raise SystemExit("A17 entry exit class and scientific gate evidence disagree")

train_preflight = json.loads(
    next(status.glob(f"train-preflight-{experiment_id}-{job_id}.json")).read_text(
        encoding="utf-8"
    )
)
resource_admission = train_preflight.get("resource_admission", {})
if (
    train_preflight.get("status") != "PREFLIGHT_PASS"
    or train_preflight.get("phase") != "train"
    or resource_admission.get("status") != "PASS"
    or resource_admission.get("host_admission_min_bytes") != host_min
    or resource_admission.get("gpu_admission_min_free_mib") != gpu_min
    or int(train_preflight.get("available_host_memory_bytes") or 0) < host_min
    or int(train_preflight.get("cuda_probe_without_torch_import", {}).get("memory_free_mib") or 0)
       < gpu_min
):
    raise SystemExit("A17 training resource admission differs")
resources = summary.get("resource_peaks", {})
if (
    int(resources.get("host_peak_rss_bytes") or 0) <= 0
    or int(resources.get("graphics_peak_reserved_bytes") or 0) <= 0
):
    raise SystemExit("A17 process resource peaks are absent")
for path in (
    next(status.glob(f"train-gpu-resources-{experiment_id}-{job_id}.csv")),
    next(status.glob(f"train-cgroup-resources-{experiment_id}-{job_id}.txt")),
    status / "seq16_train_A17_sacct_resources.txt",
):
    if not path.is_file() or path.stat().st_size <= 0:
        raise SystemExit(f"A17 resource receipt is absent: {path.name}")

a16_objective = 0.07951907715501967
a16_nse = {"1": 0.9649952670432475, "2": 0.9397019701611595, "3": 0.9155408779559143}
ukf_nse = {key: float(value) for key, value in summary["ukf_recovery_nse_by_lead_712"].items()}
best_nse_float = {key: float(value) for key, value in best_nse.items()}
verification = {
    "schema_version": "daily_camels_knet_a17_seq16_verification_v1",
    "status": "A17_TECHNICAL_COMPLETION_VERIFIED",
    "experiment_id": experiment_id,
    "slurm_job_id": job_id,
    "training_exit_class": exit_class,
    "test_job_id": test_job_id,
    "test_exit_class": test_exit_class,
    "test_attestation_sha256": sha256(test_attestation_path),
    "scientific_gate_passed": gate_passed,
    "failed_gates": failed_gates,
    "epoch_count_including_zero": len(history),
    "optimizer_steps": 40,
    "sampled_forecast_events": 306000,
    "best_epoch": expected_best_epoch,
    "epoch_zero_checkpoint_objective": epoch_objectives[0],
    "best_checkpoint_objective": expected_best,
    "objective_improvement": epoch_objectives[0] - expected_best,
    "beats_a16_best_objective": expected_best < a16_objective,
    "a16_best_checkpoint_objective": a16_objective,
    "best_nse_by_lead": best_nse_float,
    "beats_a16_nse_each_lead": all(best_nse_float[k] > a16_nse[k] for k in a16_nse),
    "all_nse_above_0_6": all(value > 0.6 for value in best_nse_float.values()),
    "ukf_nse_by_lead": ukf_nse,
    "remaining_nse_gap_to_ukf_by_lead": {
        key: ukf_nse[key] - best_nse_float[key] for key in ukf_nse
    },
    "same_training_batch_strict_decrease_count": sum(strict_flags),
    "same_training_batch_replay_count": len(strict_flags),
    "reserved_evaluation_access_counts": {key: access[key] for key in zero_access_keys},
    "host_peak_rss_bytes": int(resources["host_peak_rss_bytes"]),
    "graphics_peak_reserved_bytes": int(resources["graphics_peak_reserved_bytes"]),
    "result_summary_sha256": sha256(run / "result_summary.json"),
    "manifest_sha256": sha256(run / "manifest.sha256.json"),
    "completion_sha256": sha256(run / "completion.marker.json"),
}
target = status / "seq16_A17_verification.json"
data = (json.dumps(verification, sort_keys=True, separators=(",", ":")) + "\n").encode()
descriptor = os.open(target, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
try:
    os.write(descriptor, data)
finally:
    os.close(descriptor)
print(json.dumps(verification, sort_keys=True))
PY

FINAL_STATUS="SEQ16_A17_TECHNICAL_COMPLETE"
echo '=== FINAL SLURM ACCOUNTING ==='
JOB_CSV="$(IFS=,; printf '%s' "${JOB_IDS[*]}")"
sacct --units=K -j "$JOB_CSV" \
  --format=JobID,JobName,Partition,AllocCPUS,ReqMem,State,ExitCode,Elapsed,Start,End,MaxRSS,MaxVMSize,AveRSS
echo "DAILY_CAMELS_UKF_KNET_PARITY_SEQ16_A17_TECHNICAL_COMPLETE probe=${PROBE_JOB_ID} tests=${TEST_JOB_ID} train=${TRAIN_JOB_ID} train_exit_class=${TRAIN_EXIT_CLASS} test_exit_class=${TEST_EXIT_CLASS}"

