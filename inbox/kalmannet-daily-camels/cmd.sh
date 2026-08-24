#!/usr/bin/env bash
set -Eeuo pipefail

MAILBOX_ROOT="/data1/home/${USER}/hpc_mailbox"
PAYLOAD_DIRECTORY="${MAILBOX_ROOT}/payload/kalmannet-daily-camels/parity-full-training-coverage-v13"
BASE="/data1/home/sunyiq/kalmannet_daily_camels_parity_20260824"
SOURCE_A15="${BASE}/source_A15_seq12"
RUN_PARENT="${BASE}/runs"
STATUS_DIRECTORY="${BASE}/status"
LOG_DIRECTORY="${BASE}/logs"
OUTBOX_DIRECTORY="${MAILBOX_ROOT}/outbox/kalmannet-daily-camels"

A05_ID="DAILY_CAMELS_UKF_PARITY_KNET_FULL_STATE_EXACT_REPLAY_DTYPE_REPAIR_V3_20260825_A05"
A06_ID="DAILY_CAMELS_UKF_PARITY_KNET_FULL_STATE_CAUSAL_REPLAY_DTYPE_REPAIR_V3_20260825_A06"
A15_ID="DAILY_CAMELS_KNET_FIXED_FULL_TRAINING_COVERAGE_ACCUMULATION_SMOKE_V1_20260825_A15"
A15_ARCHIVE="${PAYLOAD_DIRECTORY}/${A15_ID}.tar.gz"
A15_SHA256="e60c4bc104d87434100ba5c170b1d81adab298b045441ec7577615220b1f352a"
A15_SIZE=224693
A15_OUTER_MANIFEST="${PAYLOAD_DIRECTORY}/A15_bundle_manifest.sha256.json"
A15_OUTER_MANIFEST_SHA256="da4172e84b817b35d99b4e198f0f4f11c4dfa3106d86d2675cfcdbf728ac24a1"
A15_INTERNAL_MANIFEST_SHA256="08f8bf4c5b99de772875f61ee5e95ca29e832eed169cf70d71607b1cb4046c0b"
A15_CONFIG_SHA256="ddfb3ad510ba1c6edfdf304a55c3d981a3d139a1cc91e104bf2bb26efe3fd763"
HOST_ADMISSION_MIN_BYTES=2806734848
GPU_ADMISSION_MIN_FREE_MIB=822
EXACT_REPLAY_GATE="${STATUS_DIRECTORY}/replay_gate_${A05_ID}.json"
CAUSAL_REPLAY_GATE="${STATUS_DIRECTORY}/replay_gate_${A06_ID}.json"

EVIDENCE_NAME="DAILY_CAMELS_KNET_FIXED_FULL_TRAINING_COVERAGE_ACCUMULATION_SMOKE_V1_A15_SEQ12_evidence.tar.gz"
EVIDENCE_ARCHIVE="${OUTBOX_DIRECTORY}/${EVIDENCE_NAME}"
START_EPOCH="$(date +%s)"
SOFT_DEADLINE_EPOCH="$((START_EPOCH + 6300))"
BASE_OWNED=0
ALL_SUBMITTED_JOBS_TERMINAL=0
FINAL_STATUS="SEQ12_RECOVERY_STARTED"
declare -a JOB_IDS=()

package_evidence() {
  local command_exit_code="$1"
  set +e
  if [[ "$BASE_OWNED" -ne 1 ]]; then
    printf 'evidence_archive=NOT_CREATED base_not_owned=1 status=%s exit_code=%s\n' \
      "$FINAL_STATUS" "$command_exit_code"
    return 0
  fi
  mkdir -p "$OUTBOX_DIRECTORY"
  if [[ -e "$EVIDENCE_ARCHIVE" ]]; then
    printf 'evidence_archive=NOT_REPLACED existing=%s status=%s exit_code=%s\n' \
      "$EVIDENCE_ARCHIVE" "$FINAL_STATUS" "$command_exit_code"
    return 0
  fi

  local snapshot="${BASE}/seq12_snapshot_$$"
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
    "${STATUS_DIRECTORY}"/seq12_* \
    "${STATUS_DIRECTORY}"/probe-"${A15_ID}"-*.json \
    "${STATUS_DIRECTORY}"/entry-probe-"${A15_ID}"-*.json \
    "${STATUS_DIRECTORY}"/train-preflight-"${A15_ID}"-*.json \
    "${STATUS_DIRECTORY}"/train-gpu-resources-"${A15_ID}"-*.csv \
    "${STATUS_DIRECTORY}"/train-cgroup-resources-"${A15_ID}"-*.txt \
    "$EXACT_REPLAY_GATE" "$CAUSAL_REPLAY_GATE"; do
    [[ -f "$candidate" && ! -L "$candidate" ]] || continue
    cp -p "$candidate" "${snapshot}/status/"
  done
  if [[ -n "${PROBE_JOB_ID:-}" ]]; then
    for candidate in "${LOG_DIRECTORY}/probe-${PROBE_JOB_ID}.out" \
      "${LOG_DIRECTORY}/probe-${PROBE_JOB_ID}.err"; do
      [[ -f "$candidate" && ! -L "$candidate" ]] || continue
      cp -p "$candidate" "${snapshot}/logs/"
    done
  fi
  if [[ -n "${TRAIN_JOB_ID:-}" ]]; then
    for candidate in "${LOG_DIRECTORY}/train-${TRAIN_JOB_ID}.out" \
      "${LOG_DIRECTORY}/train-${TRAIN_JOB_ID}.err"; do
      [[ -f "$candidate" && ! -L "$candidate" ]] || continue
      cp -p "$candidate" "${snapshot}/logs/"
    done
  fi
  if [[ -f "${SOURCE_A15}/bundle_manifest.json" && \
        ! -L "${SOURCE_A15}/bundle_manifest.json" ]]; then
    cp -p "${SOURCE_A15}/bundle_manifest.json" "${snapshot}/source/"
  fi

  local temporary_archive="${OUTBOX_DIRECTORY}/.${EVIDENCE_NAME}.$$"
  if [[ "$ALL_SUBMITTED_JOBS_TERMINAL" -eq 1 ]]; then
    if [[ -d "${RUN_PARENT}/${A15_ID}" && ! -L "${RUN_PARENT}/${A15_ID}" ]]; then
      if find "${RUN_PARENT}/${A15_ID}" -type l -print -quit | grep -q .; then
        printf 'evidence_archive=CREATE_FAILED symbolic_run_member=1 status=%s exit_code=%s\n' \
          "$FINAL_STATUS" "$command_exit_code"
        return 0
      fi
      cp -a "${RUN_PARENT}/${A15_ID}" "${snapshot}/run"
    fi
  fi
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
  return 0
}

on_exit() {
  local command_exit_code="$?"
  trap - EXIT INT TERM
  package_evidence "$command_exit_code"
  exit "$command_exit_code"
}
trap on_exit EXIT
trap 'FINAL_STATUS="SEQ12_INTERRUPTED_PARTIAL_PENDING"; exit 143' INT TERM

archive_identity_check() {
  local archive="$1" expected_sha256="$2" expected_size="$3"
  local actual_sha256 actual_size
  [[ -f "$archive" && ! -L "$archive" ]] || {
    echo "payload archive absent or symbolic: $archive" >&2
    return 60
  }
  actual_sha256="$(sha256sum "$archive" | awk '{print $1}')"
  actual_size="$(stat -c '%s' "$archive")"
  [[ "$actual_sha256" = "$expected_sha256" ]] || {
    echo "payload archive SHA-256 differs: $archive" >&2
    return 61
  }
  [[ "$actual_size" = "$expected_size" ]] || {
    echo "payload archive size differs: $archive" >&2
    return 62
  }
}

submit_probe() {
  local raw job_id
  raw="$(cd "$SOURCE_A15" && sbatch --parsable --mem=0 \
    hpc/daily_camels_ukf_knet_parity/submit_probe_gpu.slurm)"
  job_id="${raw%%;*}"
  case "$job_id" in
    ''|*[!0-9]*) echo "invalid Slurm probe job id: ${raw}" >&2; return 63 ;;
  esac
  printf '%s\n' "$job_id" > "${STATUS_DIRECTORY}/seq12_probe_A15_job_id.txt"
  JOB_IDS+=("$job_id")
  SUBMITTED_JOB_ID="$job_id"
  printf 'submitted label=probe_A15 job_id=%s scheduler_memory_request=0n runtime_host_min_bytes=%s runtime_gpu_min_free_mib=%s\n' \
    "$job_id" "$HOST_ADMISSION_MIN_BYTES" "$GPU_ADMISSION_MIN_FREE_MIB"
}

submit_train() {
  local raw job_id
  raw="$(cd "$SOURCE_A15" && sbatch --parsable --mem=0 \
    --export=ALL,PARITY_EXACT_REPLAY_GATE="${EXACT_REPLAY_GATE}",PARITY_CAUSAL_REPLAY_GATE="${CAUSAL_REPLAY_GATE}",PARITY_HOST_ADMISSION_MIN_BYTES="${HOST_ADMISSION_MIN_BYTES}",PARITY_GPU_ADMISSION_MIN_FREE_MIB="${GPU_ADMISSION_MIN_FREE_MIB}" \
    hpc/daily_camels_ukf_knet_parity/submit_train_gpu.slurm)"
  job_id="${raw%%;*}"
  case "$job_id" in
    ''|*[!0-9]*) echo "invalid Slurm training job id: ${raw}" >&2; return 64 ;;
  esac
  printf '%s\n' "$job_id" > "${STATUS_DIRECTORY}/seq12_train_A15_job_id.txt"
  JOB_IDS+=("$job_id")
  SUBMITTED_JOB_ID="$job_id"
  printf 'submitted label=train_A15 job_id=%s scheduler_memory_request=0n runtime_host_min_bytes=%s runtime_gpu_min_free_mib=%s\n' \
    "$job_id" "$HOST_ADMISSION_MIN_BYTES" "$GPU_ADMISSION_MIN_FREE_MIB"
}

accounting_record_once() {
  local job_id="$1"
  sacct -X -n -P -j "$job_id" --format=JobIDRaw,State,ExitCode 2>/dev/null | \
    awk -F'|' -v id="$job_id" '$1 == id {print $2 "|" $3; exit}'
}

wait_for_jobs() {
  local job_id live_state record state all_ready
  while (( $(date +%s) < SOFT_DEADLINE_EPOCH )); do
    all_ready=1
    for job_id in "$@"; do
      live_state="$(squeue -h -j "$job_id" -o '%T' 2>/dev/null | head -1 | tr -d '[:space:]' || true)"
      record="$(accounting_record_once "$job_id" || true)"
      state="${record%%|*}"
      state="${state%%+*}"
      case "$state" in
        COMPLETED|FAILED|CANCELLED*|TIMEOUT|OUT_OF_MEMORY|NODE_FAIL|PREEMPTED|BOOT_FAIL|DEADLINE|REVOKED|SPECIAL_EXIT) ;;
        *) all_ready=0 ;;
      esac
      [[ -z "$live_state" ]] || all_ready=0
    done
    [[ "$all_ready" -eq 0 ]] || return 0
    sleep 10
  done
  return 124
}

require_probe_succeeded() {
  local job_id="$1" record state exit_code
  record="$(accounting_record_once "$job_id" || true)"
  state="${record%%|*}"
  exit_code="${record#*|}"
  state="${state%%+*}"
  printf 'accounting job_id=%s state=%s exit_code=%s\n' \
    "$job_id" "${state:-UNKNOWN}" "${exit_code:-UNKNOWN}"
  [[ "$state" = "COMPLETED" && "$exit_code" = "0:0" ]]
}

classify_train_completion() {
  local job_id="$1" record state exit_code
  record="$(accounting_record_once "$job_id" || true)"
  state="${record%%|*}"
  exit_code="${record#*|}"
  state="${state%%+*}"
  printf 'accounting job_id=%s state=%s exit_code=%s\n' \
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

test ! -e "$EVIDENCE_ARCHIVE" || {
  echo "refusing to replace existing seq12 evidence: $EVIDENCE_ARCHIVE" >&2
  exit 65
}
if [[ ! -d "$BASE" || -L "$BASE" ]]; then
  echo "daily parity root is absent or symbolic: $BASE" >&2
  exit 66
fi
BASE_OWNED=1
for required_directory in "$RUN_PARENT" "$STATUS_DIRECTORY" "$LOG_DIRECTORY"; do
  [[ -d "$required_directory" && ! -L "$required_directory" ]] || {
    echo "daily parity directory is absent or symbolic: $required_directory" >&2
    exit 67
  }
done
[[ ! -e "$SOURCE_A15" ]] || {
  echo "seq12 source directory already exists; refusing to replace it" >&2
  exit 68
}
if find "$STATUS_DIRECTORY" -maxdepth 1 -type f -name 'seq12_*' -print -quit | grep -q .; then
  echo "seq12 already recorded status evidence; refusing duplicate submission" >&2
  exit 69
fi
[[ ! -e "${RUN_PARENT}/${A15_ID}" ]] || {
  echo "seq12 run directory already exists: ${RUN_PARENT}/${A15_ID}" >&2
  exit 70
}
for phase in probe replay train; do
  [[ ! -e "${STATUS_DIRECTORY}/locks/${A15_ID}.${phase}.lock" ]] || {
    echo "seq12 phase lock already exists: ${A15_ID}.${phase}" >&2
    exit 71
  }
done
if find "$STATUS_DIRECTORY" -maxdepth 1 -type f \
    \( -name "probe-${A15_ID}-*.json" \
       -o -name "entry-probe-${A15_ID}-*.json" \
       -o -name "train-preflight-${A15_ID}-*.json" \
       -o -name "train-gpu-resources-${A15_ID}-*.csv" \
       -o -name "train-cgroup-resources-${A15_ID}-*.txt" \) \
    -print -quit | grep -q .; then
  echo "seq12 A15 status evidence already exists" >&2
  exit 72
fi
for gate in "$EXACT_REPLAY_GATE" "$CAUSAL_REPLAY_GATE"; do
  [[ -f "$gate" && ! -L "$gate" ]] || {
    echo "required replay gate is absent or symbolic: $gate" >&2
    exit 73
  }
done
FINAL_STATUS="SEQ12_NAMESPACE_ABSENCE_VERIFIED"

echo '=== VERIFY IMMUTABLE PAYLOAD AND REPLAY GATES ==='
archive_identity_check "$A15_ARCHIVE" "$A15_SHA256" "$A15_SIZE"
archive_identity_check "$A15_OUTER_MANIFEST" "$A15_OUTER_MANIFEST_SHA256" 8299
mkdir "$SOURCE_A15"
tar -xzf "$A15_ARCHIVE" -C "$SOURCE_A15"

set +u
source "/data1/home/${USER}/miniconda3/etc/profile.d/conda.sh"
conda activate nh_final
set -u
export PYTHONDONTWRITEBYTECODE=1
python - "$SOURCE_A15" "$A15_ARCHIVE" "$A15_OUTER_MANIFEST" \
  "$A15_ID" "$A05_ID" "$A06_ID" "$EXACT_REPLAY_GATE" "$CAUSAL_REPLAY_GATE" \
  "$A15_SHA256" "$A15_OUTER_MANIFEST_SHA256" \
  "$A15_INTERNAL_MANIFEST_SHA256" "$A15_CONFIG_SHA256" <<'PY'
import hashlib
import json
import math
from pathlib import Path
import sys

source = Path(sys.argv[1])
archive_path, outer_manifest_path = map(Path, sys.argv[2:4])
expected_active_id, exact_id, causal_id = sys.argv[4:7]
exact_gate_path, causal_gate_path = map(Path, sys.argv[7:9])
expected_archive_sha, expected_outer_sha, expected_internal_sha, expected_config_sha = (
    sys.argv[9:13]
)

def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()

internal_manifest_path = source / "bundle_manifest.json"
if (
    sha256(archive_path) != expected_archive_sha
    or sha256(outer_manifest_path) != expected_outer_sha
    or sha256(internal_manifest_path) != expected_internal_sha
):
    raise SystemExit("seq12 archive or manifest identity differs")
outer = json.loads(outer_manifest_path.read_text(encoding="utf-8"))
manifest = json.loads(internal_manifest_path.read_text(encoding="utf-8"))
active_member = manifest["active_config_member"]
active_path = source / active_member
if (
    outer.get("experiment_id") != expected_active_id
    or outer.get("archive_sha256") != expected_archive_sha
    or outer.get("internal_manifest_sha256") != expected_internal_sha
    or outer.get("member_sha256", {}).get(active_member) != expected_config_sha
    or manifest.get("member_sha256", {}).get(active_member) != expected_config_sha
    or sha256(active_path) != expected_config_sha
):
    raise SystemExit("seq12 outer or internal bundle inventory differs")
active = json.loads(active_path.read_text(encoding="utf-8"))
exact_config = json.loads(
    (source / manifest["exact_replay_config_member"]).read_text(encoding="utf-8")
)
policy = active.get("execution_policy", {})
optimization = active.get("optimization", {})
reference = active.get("reference", {})
model = active.get("model", {})
forecast = active.get("forecast", {})
gate_config = active.get("gate", {})
data = active.get("data", {})
epoch_zero_anchor = active.get("epoch_zero_reproducibility", {})
expected_starts = [
    0, 100, 201, 301, 401, 501, 602, 702, 802, 903, 1003, 1103, 1204,
    1304, 1404, 1504, 1605, 1705, 1805, 1906, 2006, 2106, 2206, 2307, 2407,
]
if (
    manifest.get("experiment_id") != expected_active_id
    or active.get("experiment_id") != expected_active_id
    or active.get("basin_id") != "09035800"
    or exact_config.get("experiment_id") != exact_id
    or active.get("initialization", {}).get("execution_mode") != "causal_shared_spinup"
    or model.get("gain_initialization") != "near_zero_fc2_head"
    or policy.get("allow_probe") is not True
    or policy.get("allow_replay") is not False
    or policy.get("allow_training") is not True
    or forecast.get("leads_days") != [1, 2, 3]
    or forecast.get("checkpoint_target_count_per_lead_without_warmup") != 728
    or forecast.get("expected_recovery_target_count_per_lead") != 712
    or optimization.get("training_objective") != "physical_unit_multilead_mse"
    or optimization.get("checkpoint_objective") != "physical_unit_multilead_mse"
    or optimization.get("nonfinite_forecast_policy")
       != "hard_fail_before_target_missingness_mask"
    or optimization.get("lead_weights") != [1.0 / 3.0] * 3
    or optimization.get("training_epochs") != 1
    or optimization.get("steps_per_epoch") != 1
    or not math.isclose(
        float(optimization.get("learning_rate")),
        0.0005,
        rel_tol=0.0,
        abs_tol=0.0,
    )
    or optimization.get("segment_days") != 150
    or optimization.get("segment_filter_warmup_days") != 45
    or optimization.get("training_segment_sampling")
       != "fixed_full_training_coverage_round_half_up"
    or optimization.get("segments_per_optimizer_step") != 25
    or optimization.get("fixed_training_segment_start_indices") != expected_starts
    or optimization.get("same_segment_post_step_diagnostic")
       != "fresh_no_grad_forward_on_identical_training_forecast_targets"
    or optimization.get("same_training_batch_post_step_diagnostic")
       != "fresh_no_grad_forward_on_identical_25_segment_aggregate_forecast_targets"
    or epoch_zero_anchor.get("checkpoint_objective_728") != 0.40192019589669764
    or epoch_zero_anchor.get("parameter_sha256")
       != "b4a375c3195cae48c984e9a18cd470746950fda5a5aceec60b6e594f1a352645"
    or epoch_zero_anchor.get("prediction_sha256")
       != "17a6f0dbbe145b0262e0b2c1f426c49f1687a29927e8f8348f6ea293e246d91f"
    or gate_config.get("minimum_nse_exclusive") != 0.6
    or gate_config.get("require_each_lead") is not True
    or gate_config.get("require_post_epoch_zero_improvement") is not True
    or gate_config.get("require_better_than_strict_zero_gain_each_lead") is not True
    or gate_config.get("require_zero_reserved_data_access") is not True
    or gate_config.get("require_same_segment_post_step_improvement") is not True
    or data.get("archive_sha256")
       != "71e6d163507ae405204bedf63d2c6c06e2c3ea303cea1a0481cfa4d5f280f5fd"
    or reference.get("reference_status") != "frozen_from_seq6_causal_replay_gate_A06"
    or manifest.get("selection_objective", {}).get("common_target_count_per_lead") != 728
    or manifest.get("nse_gate", {}).get("common_target_count_per_lead") != 712
):
    raise SystemExit("seq12 training bundle identity or technical-smoke budget differs")

requirements = active.get("replay_gate_requirements", {})
expected_gates = (
    ("exact", exact_gate_path, exact_id, "exact_tukf06_backward_time_diagnostic"),
    ("causal", causal_gate_path, causal_id, "causal_shared_spinup"),
)
for name, path, experiment_id, mode in expected_gates:
    requirement = requirements.get(name, {})
    gate = json.loads(path.read_text(encoding="utf-8"))
    test_attestation = (gate.get("pytest_exit_code"), gate.get("remote_test_status"))
    if (
        sha256(path) != requirement.get("receipt_sha256")
        or requirement.get("experiment_id") != experiment_id
        or requirement.get("initialization_mode") != mode
        or gate.get("status") != "REPLAY_PASS"
        or gate.get("experiment_id") != experiment_id
        or gate.get("initialization_mode") != mode
        or gate.get("active_config_sha256") != requirement.get("active_config_sha256")
        or gate.get("bundle_manifest_sha256") != requirement.get("bundle_manifest_sha256")
        or gate.get("archive_sha256") != data.get("archive_sha256")
        or gate.get("selection_objective") != "physical_unit_multilead_mse"
        or gate.get("selection_objective_target_count_per_lead") != 728
        or gate.get("nse_gate_target_count_per_lead") != 712
        or gate.get("entry_exit_code") != 0
        or gate.get("ukf_replay_contract_passed") is not True
        or gate.get("zero_gain_contract_passed") is not True
        or gate.get("array_members_materialized_by_sealer") != 0
        or gate.get("torch_imported_by_sealer") is not False
        or gate.get("numpy_imported_by_sealer") is not False
        or test_attestation not in {
            (0, "passed"),
            (77, "skipped_pytest_unavailable"),
        }
    ):
        raise SystemExit(f"seq12 replay gate differs: {experiment_id}")
causal_metrics = json.loads(causal_gate_path.read_text(encoding="utf-8"))[
    "verified_replay_metrics"
]
objective = causal_metrics["ukf_checkpoint_objective_728"]
nse = causal_metrics["ukf_nse_by_lead_712"]
if (
    not math.isclose(
        float(objective),
        float(reference["causal_tukf06_complete_validation_objective_no_warmup"]),
        rel_tol=0.0,
        abs_tol=1.0e-12,
    )
    or [float(nse[str(lead)]) for lead in (1, 2, 3)]
    != [float(value) for value in reference["causal_tukf06_recovery_731_day_nse"]]
):
    raise SystemExit("seq12 frozen causal reference differs from the A06 replay gate")
PY
python -u "${SOURCE_A15}/hpc/daily_camels_ukf_knet_parity/preflight.py" \
  --bundle-root "$SOURCE_A15" --phase probe --offline-bundle-check \
  --report "${STATUS_DIRECTORY}/seq12_offline_A15.json"
FINAL_STATUS="SEQ12_OFFLINE_BUNDLE_AND_REPLAY_GATES_VERIFIED"

echo '=== SUBMIT READ-ONLY A15 GPU PROBE WITH PARTITION-COMPATIBLE MEMORY AND MEASURED-PEAK ADMISSION ==='
submit_probe
PROBE_JOB_ID="$SUBMITTED_JOB_ID"
FINAL_STATUS="SEQ12_PROBE_SUBMITTED"
if ! wait_for_jobs "$PROBE_JOB_ID"; then
  FINAL_STATUS="SEQ12_PROBE_PARTIAL_PENDING"
  echo "soft deadline reached while the probe is pending; no training submitted" >&2
  exit 74
fi
ALL_SUBMITTED_JOBS_TERMINAL=1
require_probe_succeeded "$PROBE_JOB_ID" || {
  FINAL_STATUS="SEQ12_PROBE_HARD_STOP"
  exit 75
}
require_lock_cleared "${STATUS_DIRECTORY}/locks/${A15_ID}.probe.lock" || {
  FINAL_STATUS="SEQ12_PROBE_LOCK_HARD_STOP"
  exit 79
}
python - "$STATUS_DIRECTORY" "$A15_ID" "$PROBE_JOB_ID" \
  "$HOST_ADMISSION_MIN_BYTES" "$GPU_ADMISSION_MIN_FREE_MIB" <<'PY'
import json
from pathlib import Path
import sys

status, experiment_id, job_id = Path(sys.argv[1]), sys.argv[2], sys.argv[3]
host_admission_min_bytes = int(sys.argv[4])
gpu_admission_min_free_mib = int(sys.argv[5])
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
    or scheduled.get("resource_admission", {}).get("required") is not False
    or scheduled.get("resource_admission", {}).get("status") != "NOT_REQUIRED"
    or scheduled.get("resource_admission", {}).get(
        "checked_on_allocated_training_node_before_training"
    ) is not False
    or scheduled.get("selection_objective", {}).get("common_target_count_per_lead") != 728
    or scheduled.get("nse_gate", {}).get("common_target_count_per_lead") != 712
    or scheduled.get("cuda_probe_without_torch_import", {}).get("visible_device_count") != 1
    or int(scheduled.get("available_host_memory_bytes") or 0)
       < host_admission_min_bytes
    or int(
        scheduled.get("cuda_probe_without_torch_import", {}).get("memory_free_mib")
        or 0
    ) < gpu_admission_min_free_mib
    or entry.get("status") != "PREFLIGHT_PASS"
    or entry.get("phase") != "probe"
    or entry.get("run_directory_absent") is not True
    or entry.get("gain_initialization") != "near_zero_fc2_head"
    or entry.get("reserved_evaluation_period_access_authorized") is not False
    or entry.get("array_members_materialized") != 0
    or entry.get("numerical_frameworks_imported_by_entry") != 0
):
    raise SystemExit("seq12 A15 probe evidence differs")
print(json.dumps({
    "experiment_id": experiment_id,
    "probe_job_id": job_id,
    "hostname": scheduled["hostname"],
    "available_host_memory_bytes": scheduled["available_host_memory_bytes"],
    "gpu": scheduled["cuda_probe_without_torch_import"],
    "host_admission_min_bytes": host_admission_min_bytes,
    "gpu_admission_min_free_mib": gpu_admission_min_free_mib,
    "host_admission_safety_factor_over_A14_process_peak": 2.0,
    "gpu_admission_safety_factor_over_A14_incremental_peak": 2.0,
    "probe_gate": "PASS",
}, sort_keys=True))
PY
FINAL_STATUS="SEQ12_PROBE_PASS"

echo '=== SUBMIT ONE-EPOCH ONE-STEP REAL BACKPROPAGATION RESOURCE SMOKE ==='
ALL_SUBMITTED_JOBS_TERMINAL=0
submit_train
TRAIN_JOB_ID="$SUBMITTED_JOB_ID"
FINAL_STATUS="SEQ12_TRAIN_SUBMITTED"
if ! wait_for_jobs "$TRAIN_JOB_ID"; then
  FINAL_STATUS="SEQ12_TRAIN_PARTIAL_PENDING"
  echo "soft deadline reached while training is pending; the job was not cancelled" >&2
  exit 76
fi
ALL_SUBMITTED_JOBS_TERMINAL=1
if ! classify_train_completion "$TRAIN_JOB_ID"; then
  FINAL_STATUS="SEQ12_TRAIN_TECHNICAL_HARD_STOP"
  exit 77
fi
require_lock_cleared "${STATUS_DIRECTORY}/locks/${A15_ID}.train.lock" || {
  FINAL_STATUS="SEQ12_TRAIN_LOCK_HARD_STOP"
  exit 80
}
printf 'train_exit_class=%s\n' "$TRAIN_EXIT_CLASS"

SACCT_RESOURCE_FILE="${STATUS_DIRECTORY}/seq12_train_A15_sacct_resources.txt"
[[ ! -e "$SACCT_RESOURCE_FILE" ]] || {
  echo "refusing to replace seq12 Slurm resource evidence" >&2
  exit 78
}
sacct -P --units=K -j "$TRAIN_JOB_ID" \
  --format=JobIDRaw,JobName,Partition,AllocCPUS,ReqMem,AllocTRES,State,ExitCode,Elapsed,Start,End,MaxRSS,MaxVMSize,AveRSS \
  > "$SACCT_RESOURCE_FILE"

FINAL_STATUS="SEQ12_TRAIN_EVIDENCE_CHECK"
python - "$RUN_PARENT" "$STATUS_DIRECTORY" "$A15_ID" "$TRAIN_JOB_ID" \
  "$TRAIN_EXIT_CLASS" "$A15_INTERNAL_MANIFEST_SHA256" \
  "$EXACT_REPLAY_GATE" "$CAUSAL_REPLAY_GATE" \
  "$HOST_ADMISSION_MIN_BYTES" "$GPU_ADMISSION_MIN_FREE_MIB" <<'PY'
import csv
import hashlib
import json
import math
import os
from pathlib import Path
import re
import sys

run_parent, status = Path(sys.argv[1]), Path(sys.argv[2])
experiment_id, job_id, exit_class = sys.argv[3:6]
expected_bundle_manifest_sha = sys.argv[6]
exact_replay_gate_path, causal_replay_gate_path = map(Path, sys.argv[7:9])
host_admission_min_bytes = int(sys.argv[9])
gpu_admission_min_free_mib = int(sys.argv[10])
run = run_parent / experiment_id

def load_json(name):
    return json.loads((run / name).read_text(encoding="utf-8"))

def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()

summary = load_json("result_summary.json")
completion = load_json("completion.marker.json")
manifest = load_json("manifest.sha256.json")
history = load_json("epoch_history.json")
identity = load_json("experiment_identity.json")
if (run / "failure.json").exists():
    raise SystemExit("A15 contains a failure record despite a completion marker")
if len(history) != 2 or [row.get("epoch") for row in history] != [0, 1]:
    raise SystemExit("A15 did not preserve exactly epoch zero and epoch one")
manifest_files = manifest.get("files", {})
if not isinstance(manifest_files, dict) or not manifest_files:
    raise SystemExit("A15 manifest file inventory is empty or malformed")
actual_files = {
    path.relative_to(run).as_posix()
    for path in run.rglob("*")
    if path.is_file()
}
expected_files = set(manifest_files) | {
    "manifest.sha256.json",
    "completion.marker.json",
}
if actual_files != expected_files:
    raise SystemExit(
        f"A15 manifest inventory differs: missing={sorted(expected_files - actual_files)} "
        f"extra={sorted(actual_files - expected_files)}"
    )
if any(path.is_symlink() for path in run.rglob("*")):
    raise SystemExit("A15 run contains a symbolic member")
for relative, expected in manifest_files.items():
    path = run / relative
    if not path.is_file() or sha256(path) != expected:
        raise SystemExit(f"A15 manifest mismatch: {relative}")

training = summary.get("training") or {}
epoch_zero, epoch_one = history
identity_sha = sha256(run / "experiment_identity.json")
if (
    completion.get("summary_sha256") != sha256(run / "result_summary.json")
    or completion.get("manifest_sha256") != sha256(run / "manifest.sha256.json")
    or summary.get("identity_sha256") != identity_sha
    or completion.get("identity_sha256") != identity_sha
    or manifest.get("identity_sha256") != identity_sha
    or identity.get("experiment_id") != experiment_id
    or identity.get("phase") != "train"
    or identity.get("initialization_mode") != "causal_shared_spinup"
    or identity.get("gain_initialization") != "near_zero_fc2_head"
    or summary.get("experiment_id") != experiment_id
    or completion.get("experiment_id") != experiment_id
    or manifest.get("experiment_id") != experiment_id
):
    raise SystemExit("A15 completion, manifest, summary, and identity chain differs")

expected_status = (
    "TRAINING_COMPLETE_GATE_PASS"
    if exit_class == "scientific_gate_pass"
    else "TRAINING_COMPLETE_GATE_FAIL"
)
expected_gate_pass = exit_class == "scientific_gate_pass"
expected_728 = {"1": 728, "2": 728, "3": 728}
expected_712 = {"1": 712, "2": 712, "3": 712}
expected_102 = {"1": 102, "2": 102, "3": 102}
expected_2550 = {"1": 2550, "2": 2550, "3": 2550}
expected_starts = [
    0, 100, 201, 301, 401, 501, 602, 702, 802, 903, 1003, 1103, 1204,
    1304, 1404, 1504, 1605, 1705, 1805, 1906, 2006, 2106, 2206, 2307, 2407,
]
expected_zero = {"1": 0, "2": 0, "3": 0}
reserved_keys = (
    "evaluation_array_reads",
    "evaluation_prediction_count",
    "evaluation_metric_count",
    "evaluation_output_count",
)
for label, ledger in (
    ("summary", summary.get("access_ledger", {})),
    ("training", training.get("access_ledger", {})),
):
    if any(int(ledger.get(key, -1)) != 0 for key in reserved_keys):
        raise SystemExit(f"A15 {label} reserved-evaluation ledger is nonzero")

epoch_one_mse = epoch_one.get(
    "training_mse_by_lead_physical_unit_mean_over_optimizer_steps"
)
if not isinstance(epoch_one_mse, dict) or set(epoch_one_mse) != {"1", "2", "3"}:
    raise SystemExit("A15 epoch-one per-lead training MSE inventory differs")
epoch_one_mse_values = [float(epoch_one_mse[str(lead)]) for lead in (1, 2, 3)]
if not all(math.isfinite(value) and value >= 0.0 for value in epoch_one_mse_values):
    raise SystemExit("A15 epoch-one per-lead training MSE is invalid")
epoch_one_objective = float(
    epoch_one["training_objective_physical_unit_multilead_mse"]
)
if not math.isclose(
    epoch_one_objective,
    math.fsum(epoch_one_mse_values) / 3.0,
    rel_tol=1.0e-6,
    abs_tol=1.0e-8,
):
    raise SystemExit("A15 epoch-one scalar loss does not equal the three-lead mean")

same_segment_replays = training.get("same_segment_step_replays")
if not isinstance(same_segment_replays, list) or len(same_segment_replays) != 1:
    raise SystemExit("A15 same-segment replay inventory differs")
same_segment = same_segment_replays[0]
epoch_same_segment_replays = epoch_one.get("same_segment_step_replays")
if epoch_same_segment_replays != same_segment_replays:
    raise SystemExit("A15 epoch and summary same-segment replay evidence differ")
constituents = same_segment.get("training_segment_replays")
if not isinstance(constituents, list) or len(constituents) != 25:
    raise SystemExit("A15 training-batch constituent replay inventory differs")
before_same = float(
    same_segment["before_step_objective_physical_unit_multilead_mse"]
)
after_same = float(
    same_segment["after_step_objective_physical_unit_multilead_mse"]
)
improvement_same = float(same_segment["objective_improvement_before_minus_after"])
expected_strict_decrease = after_same < before_same
constituent_before = []
constituent_after = []
constituent_strict_count = 0
for start, replay in zip(expected_starts, constituents, strict=True):
    issue_start = start + 45
    issue_end = start + 147
    geometry = replay.get("target_geometry_by_lead")
    if not isinstance(geometry, dict) or set(geometry) != {"1", "2", "3"}:
        raise SystemExit("A15 constituent target geometry inventory differs")
    for lead in (1, 2, 3):
        row = geometry[str(lead)]
        hashes = (
            str(row.get("target_index_sha256", "")),
            str(row.get("finite_target_mask_sha256", "")),
        )
        if (
            row.get("issue_start_index_global_inclusive") != issue_start
            or row.get("issue_end_index_global_exclusive") != issue_end
            or row.get("target_start_index_global_inclusive") != issue_start + lead
            or row.get("target_end_index_global_inclusive") != issue_end - 1 + lead
            or row.get("finite_target_count") != 102
            or any(re.fullmatch(r"[0-9a-f]{64}", value) is None for value in hashes)
        ):
            raise SystemExit(f"A15 start-{start} lead-{lead} target geometry differs")
    before = float(replay["before_step_objective_physical_unit_multilead_mse"])
    after = float(replay["after_step_objective_physical_unit_multilead_mse"])
    improvement = float(replay["objective_improvement_before_minus_after"])
    if (
        not all(math.isfinite(value) and value >= 0.0 for value in (before, after))
        or not math.isclose(improvement, before - after, rel_tol=1.0e-12, abs_tol=1.0e-15)
        or replay.get("optimizer_step") != 1
        or replay.get("segment_start_index_global_inclusive") != start
        or replay.get("segment_end_index_global_exclusive") != start + 150
        or replay.get("segment_days") != 150
        or replay.get("filter_warmup_days") != 45
        or replay.get("target_count_by_lead_before_step") != expected_102
        or replay.get("target_count_by_lead_after_step") != expected_102
        or replay.get("identical_target_geometry_before_after") is not True
        or replay.get("after_step_was_recomputed") is not True
        or replay.get("after_step_recomputed_under_no_grad") is not True
        or replay.get("reserved_evaluation_values_used") != 0
        or bool(replay.get("strict_objective_decrease")) != (after < before)
    ):
        raise SystemExit(f"A15 start-{start} constituent replay evidence differs")
    constituent_before.append(before)
    constituent_after.append(after)
    constituent_strict_count += int(after < before)

aggregate_before_by_lead = same_segment.get("mse_by_lead_before_step")
aggregate_after_by_lead = same_segment.get("mse_by_lead_after_step")
if (
    not isinstance(aggregate_before_by_lead, dict)
    or set(aggregate_before_by_lead) != {"1", "2", "3"}
    or not isinstance(aggregate_after_by_lead, dict)
    or set(aggregate_after_by_lead) != {"1", "2", "3"}
):
    raise SystemExit("A15 aggregate per-lead replay inventory differs")
expected_aggregate_before_by_lead = {
    str(lead): math.fsum(float(row["mse_by_lead_before_step"][str(lead)]) for row in constituents) / 25.0
    for lead in (1, 2, 3)
}
expected_aggregate_after_by_lead = {
    str(lead): math.fsum(float(row["mse_by_lead_after_step"][str(lead)]) for row in constituents) / 25.0
    for lead in (1, 2, 3)
}
for lead in (1, 2, 3):
    if (
        not math.isclose(float(aggregate_before_by_lead[str(lead)]), expected_aggregate_before_by_lead[str(lead)], rel_tol=1.0e-12, abs_tol=1.0e-15)
        or not math.isclose(float(aggregate_after_by_lead[str(lead)]), expected_aggregate_after_by_lead[str(lead)], rel_tol=1.0e-12, abs_tol=1.0e-15)
    ):
        raise SystemExit(f"A15 aggregate lead-{lead} replay mean differs")
if (
    not all(math.isfinite(value) and value >= 0.0 for value in (before_same, after_same))
    or not math.isclose(before_same, math.fsum(constituent_before) / 25.0, rel_tol=1.0e-12, abs_tol=1.0e-15)
    or not math.isclose(after_same, math.fsum(constituent_after) / 25.0, rel_tol=1.0e-12, abs_tol=1.0e-15)
    or not math.isclose(
        improvement_same,
        before_same - after_same,
        rel_tol=1.0e-12,
        abs_tol=1.0e-15,
    )
    or same_segment.get("optimizer_step") != 1
    or same_segment.get("training_segment_count") != 25
    or same_segment.get("training_segment_start_indices") != expected_starts
    or re.fullmatch(r"[0-9a-f]{64}", str(same_segment.get("training_segment_start_indices_sha256", ""))) is None
    or same_segment.get("target_count_by_lead_before_step") != expected_2550
    or same_segment.get("target_count_by_lead_after_step") != expected_2550
    or same_segment.get("training_segment_strict_objective_decrease_count") != constituent_strict_count
    or not math.isclose(float(same_segment.get("training_segment_strict_objective_decrease_fraction")), constituent_strict_count / 25.0, rel_tol=0.0, abs_tol=1.0e-15)
    or bool(same_segment.get("every_training_segment_strictly_decreased")) != (constituent_strict_count == 25)
    or re.fullmatch(r"[0-9a-f]{64}", str(same_segment.get("target_geometry_by_training_segment_sha256", ""))) is None
    or same_segment.get("identical_target_geometry_before_after") is not True
    or same_segment.get("after_step_was_recomputed") is not True
    or same_segment.get("after_step_recomputed_under_no_grad") is not True
    or same_segment.get("reserved_evaluation_values_used") != 0
    or bool(same_segment.get("strict_objective_decrease"))
       != expected_strict_decrease
    or training.get("same_segment_post_step_replay_count") != 1
    or bool(training.get("same_segment_every_optimizer_step_strictly_decreased"))
       != expected_strict_decrease
    or epoch_one.get("same_segment_post_step_replay_count") != 1
    or bool(epoch_one.get("same_segment_every_optimizer_step_strictly_decreased"))
       != expected_strict_decrease
):
    raise SystemExit("A15 aggregate training-batch post-step evidence differs")

epoch_objectives = [
    float(row["checkpoint_selection_objective_728_origins_without_warmup"])
    for row in history
]
expected_best_objective = min(epoch_objectives)
expected_best_epoch = epoch_objectives.index(expected_best_objective)
failed_gates = training.get("failed_gates")
if not isinstance(failed_gates, list) or len(failed_gates) != len(set(failed_gates)):
    raise SystemExit("A15 failed-gate inventory is malformed")
training_plan = training.get("training_segment_plan", {})
epoch_zero_reproducibility = training.get("epoch_zero_reproducibility", {})
if (
    summary.get("status") != expected_status
    or completion.get("status") != expected_status
    or summary.get("phase") != "train"
    or summary.get("initialization_mode") != "causal_shared_spinup"
    or summary.get("gain_initialization") != "near_zero_fc2_head"
    or summary.get("zero_gain_maximum_open_loop_difference") != 0.0
    or training.get("status") != expected_status
    or training.get("gain_initialization") != "near_zero_fc2_head"
    or bool(training.get("gate_passed")) != expected_gate_pass
    or bool(training.get("gate_passed")) != (not failed_gates)
    or training.get("objective_definition", {}).get("optimizer")
       != "equal_weight_1_2_3_day_physical_unit_mse"
    or training.get("objective_definition", {}).get("gradient_accumulation")
       != "equal_weight_mean_over_training_segments_then_one_optimizer_step"
    or training.get("optimizer_steps") != 1
    or training.get("sampled_forecast_events") != 7650
    or training.get("epoch_checkpoint_count") != 2
    or training.get("fixed_window_prediction_artifact_count") != 2
    or training.get("objective_definition", {}).get("recorded_training_objective")
       != "before_optimizer_step"
    or training.get("objective_definition", {}).get("same_segment_diagnostic")
       != "fresh_no_grad_forward_on_identical_training_forecast_targets_after_step"
    or not training.get("nonzero_gradient_parameter_names")
    or training.get("last_parameter_sha256") == training.get("epoch_zero_parameter_sha256")
    or training.get("last_parameter_sha256") != epoch_one.get("parameter_sha256")
    or training.get("epoch_zero_parameter_sha256") != epoch_zero.get("parameter_sha256")
    or epoch_zero.get("parameter_sha256")
       != "b4a375c3195cae48c984e9a18cd470746950fda5a5aceec60b6e594f1a352645"
    or epoch_zero.get("fixed_window_prediction_sha256")
       != "17a6f0dbbe145b0262e0b2c1f426c49f1687a29927e8f8348f6ea293e246d91f"
    or not math.isclose(epoch_objectives[0], 0.40192019589669764, rel_tol=0.0, abs_tol=1.0e-12)
    or epoch_zero_reproducibility.get("required") is not True
    or epoch_zero_reproducibility.get("status") != "PASS"
    or epoch_zero_reproducibility.get("checkpoint_objective_728")
       != epoch_objectives[0]
    or epoch_zero_reproducibility.get("parameter_sha256")
       != epoch_zero.get("parameter_sha256")
    or epoch_zero_reproducibility.get("prediction_sha256")
       != epoch_zero.get("fixed_window_prediction_sha256")
    or training_plan.get("sampling") != "fixed_full_training_coverage_round_half_up"
    or training_plan.get("segments_per_optimizer_step") != 25
    or training_plan.get("fixed_training_segment_start_indices") != expected_starts
    or training_plan.get("eligible_unique_issue_count") != 2509
    or training_plan.get("scored_issue_count_per_segment") != 102
    or training_plan.get("candidate_issue_count") != 2550
    or training_plan.get("unique_covered_issue_count") != 2509
    or training_plan.get("duplicate_issue_count") != 41
    or training_plan.get("uncovered_issue_count") != 0
    or training_plan.get("candidate_forecast_target_event_count_all_leads") != 7650
    or training_plan.get("complete_eligible_issue_coverage") is not True
    or training.get("best_epoch") != expected_best_epoch
    or not math.isclose(
        float(training.get("epoch_zero_checkpoint_objective")),
        epoch_objectives[0],
        rel_tol=0.0,
        abs_tol=1.0e-15,
    )
    or not math.isclose(
        float(training.get("best_checkpoint_objective")),
        expected_best_objective,
        rel_tol=0.0,
        abs_tol=1.0e-15,
    )
    or not math.isclose(
        float(training.get("last_validation_checkpoint_objective")),
        epoch_objectives[1],
        rel_tol=0.0,
        abs_tol=1.0e-15,
    )
    or training.get("best_parameter_sha256")
       != history[expected_best_epoch].get("parameter_sha256")
    or bool(training.get("parameter_hash_changed"))
       != (training.get("best_parameter_sha256") != training.get("epoch_zero_parameter_sha256"))
    or training.get("best_target_count_by_lead_after_warmup") != expected_712
    or training.get("best_target_count_by_lead_without_warmup") != expected_728
    or epoch_zero.get("optimizer_steps") != 0
    or epoch_zero.get("sampled_forecast_events") != 0
    or epoch_zero.get("epoch_optimizer_step_count") != 0
    or epoch_zero.get("training_sampled_finite_target_event_count_by_lead") != expected_zero
    or epoch_zero.get("training_mse_by_lead_physical_unit_mean_over_optimizer_steps") is not None
    or epoch_zero.get("gradient_clipped_optimizer_step_count") != 0
    or epoch_zero.get("gradient_clipped_optimizer_step_fraction") is not None
    or epoch_zero.get("maximum_gradient_norm_before_clip") is not None
    or epoch_zero.get("finite_gradients") is not None
    or epoch_zero.get("target_count_by_lead_after_warmup") != expected_712
    or epoch_zero.get("target_count_by_lead_without_warmup") != expected_728
    or epoch_one.get("optimizer_steps") != 1
    or epoch_one.get("sampled_forecast_events") != 7650
    or epoch_one.get("finite_gradients") is not True
    or epoch_one.get("nonzero_gradient_parameter_tensor_count", 0) <= 0
    or epoch_one.get("epoch_optimizer_step_count") != 1
    or epoch_one.get("training_sampled_finite_target_event_count_by_lead")
       != expected_2550
    or epoch_one.get("gradient_clipped_optimizer_step_count") not in {0, 1}
    or epoch_one.get("gradient_clipped_optimizer_step_fraction") not in {0.0, 1.0}
    or not math.isfinite(float(epoch_one.get("maximum_gradient_norm_before_clip")))
    or float(epoch_one.get("maximum_gradient_norm_before_clip")) < 0.0
    or epoch_one.get("target_count_by_lead_after_warmup") != expected_712
    or epoch_one.get("target_count_by_lead_without_warmup") != expected_728
    or epoch_zero.get("training_objective_physical_unit_multilead_mse") is not None
    or not math.isfinite(epoch_one_objective)
):
    raise SystemExit("A15 technical training evidence differs")
same_segment_gate_failed = "same_segment_post_step_improvement" in failed_gates
if same_segment_gate_failed is expected_strict_decrease:
    raise SystemExit("A15 aggregate training-batch gate is inconsistent")

def validate_strict_zero_comparison(name):
    comparison = training.get(name)
    if not isinstance(comparison, dict):
        raise SystemExit(f"A15 {name} comparison is absent")
    top_values = (
        comparison.get("strict_zero_gain_checkpoint_objective_728"),
        comparison.get("candidate_checkpoint_objective_728"),
        comparison.get("checkpoint_objective_improvement_zero_minus_candidate"),
    )
    if not all(isinstance(value, (int, float)) and math.isfinite(float(value)) for value in top_values):
        raise SystemExit(f"A15 {name} checkpoint comparison is invalid")
    if not math.isclose(
        float(top_values[2]),
        float(top_values[0]) - float(top_values[1]),
        rel_tol=1.0e-12,
        abs_tol=1.0e-15,
    ):
        raise SystemExit(f"A15 {name} checkpoint improvement has the wrong sign")
    rows = comparison.get("by_lead_712")
    if not isinstance(rows, dict) or set(rows) != {"1", "2", "3"}:
        raise SystemExit(f"A15 {name} strict-zero lead inventory differs")
    row_better = []
    for lead in (1, 2, 3):
        row = rows[str(lead)]
        keys = (
            "strict_zero_gain_mse",
            "candidate_mse",
            "mse_improvement_zero_minus_candidate",
            "strict_zero_gain_nse",
            "candidate_nse",
            "nse_delta_candidate_minus_zero",
        )
        values = [float(row[key]) for key in keys]
        if not all(math.isfinite(value) for value in values):
            raise SystemExit(f"A15 {name} lead-{lead} comparison is non-finite")
        if not math.isclose(values[2], values[0] - values[1], rel_tol=1.0e-12, abs_tol=1.0e-15):
            raise SystemExit(f"A15 {name} lead-{lead} MSE delta has the wrong sign")
        if not math.isclose(values[5], values[4] - values[3], rel_tol=1.0e-12, abs_tol=1.0e-15):
            raise SystemExit(f"A15 {name} lead-{lead} NSE delta has the wrong sign")
        expected_better = values[2] > 0.0 and values[5] > 0.0
        if row.get("candidate_better") is not expected_better:
            raise SystemExit(f"A15 {name} lead-{lead} better flag differs")
        row_better.append(expected_better)
    expected_all = all(row_better)
    if comparison.get("candidate_better_than_strict_zero_gain_each_lead") is not expected_all:
        raise SystemExit(f"A15 {name} overall strict-zero flag differs")
    return comparison, expected_all

epoch_zero_comparison, _ = validate_strict_zero_comparison(
    "epoch_zero_vs_strict_zero_gain"
)
best_comparison, best_strict_pass = validate_strict_zero_comparison(
    "best_vs_strict_zero_gain"
)
if (
    epoch_zero_comparison["candidate_checkpoint_objective_728"]
       != epoch_objectives[0]
    or best_comparison["candidate_checkpoint_objective_728"]
       != expected_best_objective
    or epoch_zero_comparison["strict_zero_gain_checkpoint_objective_728"]
       != best_comparison["strict_zero_gain_checkpoint_objective_728"]
    or not math.isclose(
        float(training.get("objective_improvement")),
        epoch_objectives[0] - expected_best_objective,
        rel_tol=0.0,
        abs_tol=1.0e-15,
    )
):
    raise SystemExit("A15 checkpoint objective chain differs")
for lead in (1, 2, 3):
    zero_row = epoch_zero_comparison["by_lead_712"][str(lead)]
    best_row = best_comparison["by_lead_712"][str(lead)]
    if (
        zero_row["strict_zero_gain_mse"] != best_row["strict_zero_gain_mse"]
        or zero_row["strict_zero_gain_nse"] != best_row["strict_zero_gain_nse"]
    ):
        raise SystemExit("A15 strict zero-gain reference changed between comparisons")
strict_gate_failed = "better_than_strict_zero_gain_each_lead" in failed_gates
if (
    training.get("best_better_than_strict_zero_gain_each_lead") is not best_strict_pass
    or strict_gate_failed is best_strict_pass
):
    raise SystemExit("A15 strict zero-gain comparison and scientific gate disagree")
best_hash_changed = (
    training.get("best_parameter_sha256") != training.get("epoch_zero_parameter_sha256")
)
if ("parameter_hash_change" in failed_gates) is best_hash_changed:
    raise SystemExit("A15 best-parameter change gate is inconsistent")
best_nse = training.get("best_nse_by_lead")
if (
    not isinstance(best_nse, dict)
    or set(best_nse) != {"1", "2", "3"}
    or not all(math.isfinite(float(value)) for value in best_nse.values())
):
    raise SystemExit("A15 best per-lead NSE inventory differs")
if expected_gate_pass:
    if (
        expected_best_epoch <= 0
        or float(training.get("objective_improvement")) <= 1.0e-6
        or any(float(value) <= 0.6 for value in best_nse.values())
        or not best_strict_pass
    ):
        raise SystemExit("A15 scientific gate passed without satisfying every gate")
elif not failed_gates:
    raise SystemExit("A15 scientific gate failed without a named failed gate")

train_preflight_path = status / f"train-preflight-{experiment_id}-{job_id}.json"
train_preflight = json.loads(train_preflight_path.read_text(encoding="utf-8"))
expected_replay_receipts = {
    "exact": sha256(exact_replay_gate_path),
    "causal": sha256(causal_replay_gate_path),
}
resource_admission = train_preflight.get("resource_admission", {})
if (
    train_preflight.get("status") != "PREFLIGHT_PASS"
    or train_preflight.get("phase") != "train"
    or train_preflight.get("experiment_id") != experiment_id
    or train_preflight.get("active_config_sha256") != identity.get("configuration_sha256")
    or train_preflight.get("bundle_manifest_sha256") != expected_bundle_manifest_sha
    or train_preflight.get("replay_gate_receipt_sha256") != expected_replay_receipts
    or train_preflight.get("selection_objective", {}).get("common_target_count_per_lead") != 728
    or train_preflight.get("nse_gate", {}).get("common_target_count_per_lead") != 712
    or train_preflight.get("cuda_probe_without_torch_import", {}).get("visible_device_count") != 1
    or int(train_preflight.get("available_host_memory_bytes") or 0)
       < host_admission_min_bytes
    or int(
        train_preflight.get("cuda_probe_without_torch_import", {}).get("memory_free_mib")
        or 0
    ) < gpu_admission_min_free_mib
    or resource_admission.get("required") is not True
    or resource_admission.get("status") != "PASS"
    or resource_admission.get("checked_on_allocated_training_node_before_training")
       is not True
    or resource_admission.get("host_admission_min_bytes")
       != host_admission_min_bytes
    or resource_admission.get("gpu_admission_min_free_mib")
       != gpu_admission_min_free_mib
    or resource_admission.get("available_host_memory_bytes")
       != train_preflight.get("available_host_memory_bytes")
    or resource_admission.get("gpu_memory_free_mib")
       != train_preflight.get("cuda_probe_without_torch_import", {}).get("memory_free_mib")
    or train_preflight.get("array_members_materialized") != 0
    or train_preflight.get("reserved_data_member_count") != 0
):
    raise SystemExit("A15 scheduled training preflight evidence differs")
causal_gate = json.loads(causal_replay_gate_path.read_text(encoding="utf-8"))
causal_metrics = causal_gate.get("verified_replay_metrics", {})
if (
    not math.isclose(
        float(summary.get("ukf_recovery_checkpoint_objective_728")),
        float(causal_metrics.get("ukf_checkpoint_objective_728")),
        rel_tol=0.0,
        abs_tol=1.0e-12,
    )
    or summary.get("ukf_recovery_nse_by_lead_712")
       != causal_metrics.get("ukf_nse_by_lead_712")
):
    raise SystemExit("A15 run did not preserve the frozen causal UKF reference")

resources = summary.get("resource_peaks", {})
host_process_peak = int(resources.get("host_peak_rss_bytes") or 0)
torch_reserved = int(resources.get("graphics_peak_reserved_bytes") or 0)
if host_process_peak <= 0 or torch_reserved <= 0:
    raise SystemExit("A15 entry resource peaks are absent")

gpu_log = status / f"train-gpu-resources-{experiment_id}-{job_id}.csv"
cgroup_log = status / f"train-cgroup-resources-{experiment_id}-{job_id}.txt"
sacct_log = status / "seq12_train_A15_sacct_resources.txt"
for path in (gpu_log, cgroup_log, sacct_log):
    if not path.is_file() or path.stat().st_size <= 0:
        raise SystemExit(f"A15 resource receipt is absent: {path.name}")

gpu_rows = []
with gpu_log.open("r", encoding="utf-8", newline="") as handle:
    for row in csv.reader(handle):
        if len(row) != 7:
            continue
        try:
            total_mib, used_mib, free_mib = map(int, (row[3], row[4], row[5]))
        except ValueError:
            continue
        gpu_rows.append({
            "timestamp": row[0].strip(),
            "uuid": row[1].strip(),
            "name": row[2].strip(),
            "total_mib": total_mib,
            "used_mib": used_mib,
            "free_mib": free_mib,
        })
if not gpu_rows:
    raise SystemExit("A15 GPU resource sampler produced no valid samples")
if len({row["uuid"] for row in gpu_rows}) != 1:
    raise SystemExit("A15 GPU resource samples span multiple devices")
gpu_baseline_used = gpu_rows[0]["used_mib"] * 1024 * 1024
gpu_sampled_peak_used = max(row["used_mib"] for row in gpu_rows) * 1024 * 1024
gpu_incremental_peak = max(0, gpu_sampled_peak_used - gpu_baseline_used)

cgroup_values = {}
for line in cgroup_log.read_text(encoding="utf-8").splitlines():
    if "=" in line:
        key, value = line.split("=", 1)
        cgroup_values[key] = value
cgroup_current_text = cgroup_values.get("current_memory_peak", "")
cgroup_parent_text = cgroup_values.get("parent_memory_peak", "")
cgroup_current_peak = int(cgroup_current_text) if cgroup_current_text.isdigit() else 0
cgroup_parent_peak = int(cgroup_parent_text) if cgroup_parent_text.isdigit() else 0

def parse_kib(value):
    text = value.strip()
    if not text:
        return 0
    match = re.fullmatch(r"([0-9]+(?:\.[0-9]+)?)([KMGTP]?)", text)
    if not match:
        return 0
    number = float(match.group(1))
    suffix = match.group(2)
    factor = {"": 1024, "K": 1024, "M": 1024**2, "G": 1024**3,
              "T": 1024**4, "P": 1024**5}[suffix]
    return int(number * factor)

sacct_rows = list(csv.DictReader(sacct_log.open("r", encoding="utf-8"), delimiter="|"))
slurm_step_peak = max((parse_kib(row.get("MaxRSS", "")) for row in sacct_rows), default=0)
host_basis = max(host_process_peak, slurm_step_peak)
gpu_basis = max(torch_reserved, gpu_incremental_peak)
if host_basis <= 0 or gpu_basis <= 0:
    raise SystemExit("A15 did not produce usable host and GPU peak bases")

resource_summary = {
    "schema_version": "daily_camels_ukf_knet_resource_smoke_v2",
    "status": "RESOURCE_SMOKE_TECHNICAL_PASS",
    "experiment_id": experiment_id,
    "slurm_job_id": job_id,
    "training_hostname": train_preflight["hostname"],
    "training_cuda_visible_devices": train_preflight["cuda_visible_devices"],
    "training_visible_device_count": train_preflight[
        "cuda_probe_without_torch_import"
    ]["visible_device_count"],
    "training_available_host_memory_before_bytes": int(
        train_preflight["available_host_memory_bytes"]
    ),
    "training_exit_class": exit_class,
    "scientific_gate_passed": bool(training.get("gate_passed")),
    "host_process_peak_rss_bytes": host_process_peak,
    "host_current_cgroup_peak_bytes": cgroup_current_peak,
    "host_parent_cgroup_peak_bytes_record_only": cgroup_parent_peak,
    "slurm_step_max_rss_bytes": slurm_step_peak,
    "host_peak_basis_bytes": host_basis,
    "host_peak_basis_excludes_parent_cgroup": True,
    "slurm_requested_memory": "0n_partition_constraint",
    "host_admission_min_bytes": host_admission_min_bytes,
    "gpu_admission_min_free_mib": gpu_admission_min_free_mib,
    "host_admission_safety_factor_over_A14_process_peak": 2.0,
    "gpu_admission_safety_factor_over_A14_incremental_peak": 2.0,
    "gpu_total_bytes": gpu_rows[0]["total_mib"] * 1024 * 1024,
    "gpu_free_before_bytes": gpu_rows[0]["free_mib"] * 1024 * 1024,
    "gpu_used_before_bytes": gpu_baseline_used,
    "gpu_sampled_peak_used_bytes": gpu_sampled_peak_used,
    "gpu_incremental_peak_used_bytes": gpu_incremental_peak,
    "gpu_torch_peak_allocated_bytes": int(resources["graphics_peak_allocated_bytes"]),
    "gpu_torch_peak_reserved_bytes": torch_reserved,
    "gpu_peak_basis_bytes": gpu_basis,
    "gpu_uuid": gpu_rows[0]["uuid"],
    "gpu_name": gpu_rows[0]["name"],
    "resource_sample_count": len(gpu_rows),
    "resource_sample_interval_seconds": 1,
    "result_summary_sha256": sha256(run / "result_summary.json"),
    "result_manifest_sha256": sha256(run / "manifest.sha256.json"),
    "completion_sha256": sha256(run / "completion.marker.json"),
    "identity_sha256": identity_sha,
    "epoch_history_sha256": sha256(run / "epoch_history.json"),
    "gpu_resource_log_sha256": sha256(gpu_log),
    "cgroup_resource_log_sha256": sha256(cgroup_log),
    "sacct_resource_log_sha256": sha256(sacct_log),
}
target = status / "seq12_A15_resource_summary.json"
data = (json.dumps(resource_summary, sort_keys=True, separators=(",", ":")) + "\n").encode()
descriptor = os.open(target, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
try:
    os.write(descriptor, data)
finally:
    os.close(descriptor)
print(json.dumps({
    "experiment_id": experiment_id,
    "training_status": summary["status"],
    "best_epoch": training["best_epoch"],
    "epoch_zero_objective": training["epoch_zero_checkpoint_objective"],
    "best_objective": training["best_checkpoint_objective"],
    "objective_improvement": training["objective_improvement"],
    "best_nse_by_lead": training["best_nse_by_lead"],
    "optimizer_steps": 1,
    "sampled_forecast_events": 7650,
    "training_segment_count": 25,
    "aggregate_training_batch_before_step_objective": before_same,
    "aggregate_training_batch_after_step_objective": after_same,
    "aggregate_training_batch_objective_improvement": improvement_same,
    "aggregate_training_batch_strict_objective_decrease": expected_strict_decrease,
    "last_parameter_hash_changed": True,
    "resource_summary": resource_summary,
}, sort_keys=True))
PY

echo '=== FINAL SLURM ACCOUNTING WITH JOB STEPS ==='
JOB_CSV="$(IFS=,; printf '%s' "${JOB_IDS[*]}")"
sacct --units=K -j "$JOB_CSV" \
  --format=JobID,JobName,Partition,AllocCPUS,ReqMem,State,ExitCode,Elapsed,Start,End,MaxRSS,MaxVMSize,AveRSS
if [[ "$TRAIN_EXIT_CLASS" = "scientific_gate_pass" ]]; then
  FINAL_STATUS="SEQ12_TECHNICAL_COMPLETE_SCIENTIFIC_GATE_PASS"
else
  FINAL_STATUS="SEQ12_TECHNICAL_COMPLETE_SCIENTIFIC_GATE_FAIL"
fi
echo "DAILY_CAMELS_UKF_KNET_PARITY_SEQ12_TECHNICAL_COMPLETE probe=${PROBE_JOB_ID} train=${TRAIN_JOB_ID} train_exit_class=${TRAIN_EXIT_CLASS} final_status=${FINAL_STATUS}"
