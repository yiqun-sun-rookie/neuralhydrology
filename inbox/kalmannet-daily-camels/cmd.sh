#!/usr/bin/env bash
set -Eeuo pipefail

MAILBOX_ROOT="/data1/home/${USER}/hpc_mailbox"
PAYLOAD_DIRECTORY="${MAILBOX_ROOT}/payload/kalmannet-daily-camels/parity-v1"
BASE="/data1/home/sunyiq/kalmannet_daily_camels_parity_20260824"
SOURCE_A01="${BASE}/source_A01"
SOURCE_A02="${BASE}/source_A02"
RUN_PARENT="${BASE}/runs"
STATUS_DIRECTORY="${BASE}/status"
LOG_DIRECTORY="${BASE}/logs"
OUTBOX_DIRECTORY="${MAILBOX_ROOT}/outbox/kalmannet-daily-camels"

A01_ID="DAILY_CAMELS_UKF_PARITY_KNET_FULL_STATE_V1_20260824_A01"
A02_ID="DAILY_CAMELS_UKF_PARITY_KNET_FULL_STATE_CAUSAL_PROBE_V1_20260824_A02"
A01_ARCHIVE="${PAYLOAD_DIRECTORY}/${A01_ID}.tar.gz"
A02_ARCHIVE="${PAYLOAD_DIRECTORY}/${A02_ID}.tar.gz"
A01_SHA256="be80df77480276ab9ebda06d4d82de3569dd348d19ecf580d0e0335cb9a16fdd"
A02_SHA256="bedadb3a33646cbda64378326fa12c910d15476d39b9cf0bd64926173fc6b6a9"
A01_SIZE=198849
A02_SIZE=199239

EVIDENCE_NAME="DAILY_CAMELS_UKF_PARITY_REPLAYS_A01_A02_SEQ3_evidence.tar.gz"
EVIDENCE_ARCHIVE="${OUTBOX_DIRECTORY}/${EVIDENCE_NAME}"
START_EPOCH="$(date +%s)"
SOFT_DEADLINE_EPOCH="$((START_EPOCH + 6300))"
BASE_OWNED=0
ALL_SUBMITTED_JOBS_TERMINAL=0
FINAL_STATUS="SEQ3_STARTED"
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

  local snapshot="${BASE}/seq3_snapshot_$$"
  mkdir -p "$snapshot/status"
  printf '%s\n' "$FINAL_STATUS" > "${snapshot}/final_status.txt"
  printf '%s\n' "$command_exit_code" > "${snapshot}/command_exit_code.txt"
  printf '%s\n' "${JOB_IDS[@]:-}" > "${snapshot}/submitted_job_ids.txt"
  date -u +%Y-%m-%dT%H:%M:%SZ > "${snapshot}/snapshot_time_utc.txt"
  if [[ "${#JOB_IDS[@]}" -gt 0 ]]; then
    local job_csv
    job_csv="$(IFS=,; printf '%s' "${JOB_IDS[*]}")"
    squeue -h -j "$job_csv" -o '%i|%T|%R|%M|%l' \
      > "${snapshot}/squeue_snapshot.txt" 2>&1 || true
    sacct -X -P -j "$job_csv" \
      --format=JobIDRaw,JobName,Partition,AllocCPUS,State,ExitCode,Elapsed,Start,End,MaxRSS \
      > "${snapshot}/sacct_snapshot.txt" 2>&1 || true
  fi
  if [[ -d "$STATUS_DIRECTORY" ]]; then
    find "$STATUS_DIRECTORY" -maxdepth 1 -type f ! -name '*.pending*' \
      -exec cp -p '{}' "${snapshot}/status/" ';' 2>/dev/null || true
  fi

  local temporary_archive="${OUTBOX_DIRECTORY}/.${EVIDENCE_NAME}.$$"
  if [[ "$ALL_SUBMITTED_JOBS_TERMINAL" -eq 1 ]]; then
    tar -czf "$temporary_archive" -C "$BASE" \
      status logs runs \
      source_A01/bundle_manifest.json \
      source_A02/bundle_manifest.json \
      "$(basename "$snapshot")"
  else
    tar -czf "$temporary_archive" -C "$BASE" "$(basename "$snapshot")"
  fi
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
trap 'FINAL_STATUS="SEQ3_INTERRUPTED_PARTIAL_PENDING"; exit 143' INT TERM

archive_identity_check() {
  local archive="$1"
  local expected_sha256="$2"
  local expected_size="$3"
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

submit_job() {
  local source_directory="$1"
  local script_relative="$2"
  local label="$3"
  local raw job_id
  raw="$(cd "$source_directory" && sbatch --parsable "$script_relative")"
  job_id="${raw%%;*}"
  case "$job_id" in
    ''|*[!0-9]*) echo "invalid Slurm job id for ${label}: ${raw}" >&2; return 63 ;;
  esac
  printf '%s\n' "$job_id" > "${STATUS_DIRECTORY}/seq3_${label}_job_id.txt"
  JOB_IDS+=("$job_id")
  SUBMITTED_JOB_ID="$job_id"
  printf 'submitted label=%s job_id=%s\n' "$label" "$job_id"
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
      if [[ -n "$live_state" ]]; then
        all_ready=0
      fi
    done
    if [[ "$all_ready" -eq 1 ]]; then
      return 0
    fi
    sleep 10
  done
  return 124
}

require_jobs_succeeded() {
  local job_id record state exit_code
  for job_id in "$@"; do
    record="$(accounting_record_once "$job_id" || true)"
    state="${record%%|*}"
    exit_code="${record#*|}"
    state="${state%%+*}"
    printf 'accounting job_id=%s state=%s exit_code=%s\n' \
      "$job_id" "${state:-UNKNOWN}" "${exit_code:-UNKNOWN}"
    [[ "$state" = "COMPLETED" && "$exit_code" = "0:0" ]] || return 64
  done
}

test ! -e "$EVIDENCE_ARCHIVE" || {
  echo "refusing to replace existing seq3 evidence: $EVIDENCE_ARCHIVE" >&2
  exit 65
}
if ! mkdir "$BASE"; then
  echo "unique parity root already exists; refusing to reuse: $BASE" >&2
  exit 66
fi
BASE_OWNED=1
mkdir "$SOURCE_A01" "$SOURCE_A02" "$RUN_PARENT" "$STATUS_DIRECTORY" "$LOG_DIRECTORY"
FINAL_STATUS="SEQ3_REMOTE_ROOT_CREATED"

echo '=== VERIFY IMMUTABLE PAYLOADS ==='
archive_identity_check "$A01_ARCHIVE" "$A01_SHA256" "$A01_SIZE"
archive_identity_check "$A02_ARCHIVE" "$A02_SHA256" "$A02_SIZE"
tar -xzf "$A01_ARCHIVE" -C "$SOURCE_A01"
tar -xzf "$A02_ARCHIVE" -C "$SOURCE_A02"

source "/data1/home/${USER}/miniconda3/etc/profile.d/conda.sh"
conda activate nh_final
export PYTHONDONTWRITEBYTECODE=1
python -u "${SOURCE_A01}/hpc/daily_camels_ukf_knet_parity/preflight.py" \
  --bundle-root "$SOURCE_A01" --phase probe --offline-bundle-check \
  --report "${STATUS_DIRECTORY}/seq3_offline_A01.json"
python -u "${SOURCE_A02}/hpc/daily_camels_ukf_knet_parity/preflight.py" \
  --bundle-root "$SOURCE_A02" --phase probe --offline-bundle-check \
  --report "${STATUS_DIRECTORY}/seq3_offline_A02.json"
FINAL_STATUS="SEQ3_OFFLINE_BUNDLES_VERIFIED"

echo '=== SUBMIT TWO READ-ONLY GPU PROBES ==='
submit_job "$SOURCE_A01" \
  hpc/daily_camels_ukf_knet_parity/submit_probe_gpu.slurm probe_A01
PROBE_A01_JOB_ID="$SUBMITTED_JOB_ID"
submit_job "$SOURCE_A02" \
  hpc/daily_camels_ukf_knet_parity/submit_probe_gpu.slurm probe_A02
PROBE_A02_JOB_ID="$SUBMITTED_JOB_ID"
FINAL_STATUS="SEQ3_PROBES_SUBMITTED"

if ! wait_for_jobs "$PROBE_A01_JOB_ID" "$PROBE_A02_JOB_ID"; then
  FINAL_STATUS="SEQ3_PROBES_PARTIAL_PENDING"
  echo "soft deadline reached while probes are pending; no replay submitted" >&2
  exit 75
fi
ALL_SUBMITTED_JOBS_TERMINAL=1
require_jobs_succeeded "$PROBE_A01_JOB_ID" "$PROBE_A02_JOB_ID" || {
  FINAL_STATUS="SEQ3_PROBE_HARD_STOP"
  exit 76
}
FINAL_STATUS="SEQ3_PROBE_EVIDENCE_CHECK"

python - "$STATUS_DIRECTORY" "$A01_ID" "$PROBE_A01_JOB_ID" "$A02_ID" "$PROBE_A02_JOB_ID" <<'PY'
import json
from pathlib import Path
import sys

status = Path(sys.argv[1])
pairs = ((sys.argv[2], sys.argv[3]), (sys.argv[4], sys.argv[5]))
for experiment_id, job_id in pairs:
    scheduled_path = status / f"probe-{experiment_id}-{job_id}.json"
    entry_path = status / f"entry-probe-{experiment_id}-{job_id}.json"
    scheduled = json.loads(scheduled_path.read_text(encoding="utf-8"))
    entry = json.loads(entry_path.read_text(encoding="utf-8"))
    if (
        scheduled.get("status") != "PREFLIGHT_PASS"
        or scheduled.get("phase") != "probe"
        or scheduled.get("experiment_id") != experiment_id
        or scheduled.get("run_directory_absent") is not True
        or scheduled.get("array_members_materialized") != 0
        or scheduled.get("reserved_data_member_count") != 0
        or scheduled.get("torch_imported") is not False
        or scheduled.get("numpy_imported") is not False
        or scheduled.get("cuda_probe_without_torch_import", {}).get("visible_device_count") != 1
        or int(scheduled.get("cuda_probe_without_torch_import", {}).get("memory_free_mib", 0)) <= 0
        or int(scheduled.get("available_host_memory_bytes") or 0) <= 0
    ):
        raise SystemExit(f"scheduled probe evidence differs: {experiment_id}")
    if (
        entry.get("status") != "PREFLIGHT_PASS"
        or entry.get("phase") != "probe"
        or entry.get("experiment_id") != experiment_id
        or entry.get("run_directory_absent") is not True
        or entry.get("reserved_evaluation_period_access_authorized") is not False
        or entry.get("array_members_materialized") != 0
        or entry.get("numerical_frameworks_imported_by_entry") != 0
        or entry.get("graphics_driver_probe", {}).get("available") is not True
    ):
        raise SystemExit(f"entry probe evidence differs: {experiment_id}")
    print(json.dumps({
        "experiment_id": experiment_id,
        "probe_job_id": job_id,
        "hostname": scheduled.get("hostname"),
        "available_host_memory_bytes": scheduled["available_host_memory_bytes"],
        "cuda_device_name": scheduled["cuda_probe_without_torch_import"]["device_name"],
        "cuda_memory_free_mib": scheduled["cuda_probe_without_torch_import"]["memory_free_mib"],
        "probe_gate": "PASS",
    }, sort_keys=True))
PY
FINAL_STATUS="SEQ3_PROBES_PASS"

echo '=== SUBMIT TWO DIAGNOSTIC REPLAYS; NO TRAINING ==='
ALL_SUBMITTED_JOBS_TERMINAL=0
submit_job "$SOURCE_A01" \
  hpc/daily_camels_ukf_knet_parity/submit_replay_gpu.slurm replay_A01
REPLAY_A01_JOB_ID="$SUBMITTED_JOB_ID"
submit_job "$SOURCE_A02" \
  hpc/daily_camels_ukf_knet_parity/submit_replay_gpu.slurm replay_A02
REPLAY_A02_JOB_ID="$SUBMITTED_JOB_ID"
FINAL_STATUS="SEQ3_REPLAYS_SUBMITTED"

if ! wait_for_jobs "$REPLAY_A01_JOB_ID" "$REPLAY_A02_JOB_ID"; then
  FINAL_STATUS="SEQ3_REPLAYS_PARTIAL_PENDING"
  echo "soft deadline reached while replays are pending; jobs were not cancelled" >&2
  exit 77
fi
ALL_SUBMITTED_JOBS_TERMINAL=1
require_jobs_succeeded "$REPLAY_A01_JOB_ID" "$REPLAY_A02_JOB_ID" || {
  FINAL_STATUS="SEQ3_REPLAY_HARD_STOP"
  exit 78
}
FINAL_STATUS="SEQ3_REPLAY_EVIDENCE_CHECK"

python - "$STATUS_DIRECTORY" "$A01_ID" "$A02_ID" <<'PY'
import json
import math
from pathlib import Path
import sys

status = Path(sys.argv[1])
expected = {
    sys.argv[2]: "exact_tukf06_backward_time_diagnostic",
    sys.argv[3]: "causal_shared_spinup",
}
for experiment_id, initialization_mode in expected.items():
    path = status / f"replay_gate_{experiment_id}.json"
    gate = json.loads(path.read_text(encoding="utf-8"))
    metrics = gate.get("verified_replay_metrics", {})
    nse = metrics.get("ukf_nse_by_lead_712", {})
    objective = metrics.get("ukf_checkpoint_objective_728")
    if (
        gate.get("status") != "REPLAY_PASS"
        or gate.get("experiment_id") != experiment_id
        or gate.get("initialization_mode") != initialization_mode
        or gate.get("selection_objective") != "physical_unit_multilead_mse"
        or gate.get("selection_objective_target_count_per_lead") != 728
        or gate.get("nse_gate_target_count_per_lead") != 712
        or gate.get("pytest_exit_code") != 0
        or gate.get("entry_exit_code") != 0
        or gate.get("ukf_replay_contract_passed") is not True
        or gate.get("zero_gain_contract_passed") is not True
        or gate.get("array_members_materialized_by_sealer") != 0
        or gate.get("torch_imported_by_sealer") is not False
        or gate.get("numpy_imported_by_sealer") is not False
        or not isinstance(gate.get("run_member_sha256"), dict)
        or int(gate.get("run_member_count", 0)) <= 0
        or metrics.get("zero_gain_maximum_open_loop_difference") != 0.0
        or isinstance(objective, bool)
        or not isinstance(objective, (int, float))
        or not math.isfinite(float(objective))
        or float(objective) <= 0.0
        or set(nse) != {"1", "2", "3"}
        or not all(isinstance(value, (int, float)) and math.isfinite(float(value)) for value in nse.values())
    ):
        raise SystemExit(f"sealed replay gate differs: {experiment_id}")
    print(json.dumps({
        "experiment_id": experiment_id,
        "initialization_mode": initialization_mode,
        "replay_gate": "PASS",
        "ukf_checkpoint_objective_728": objective,
        "ukf_nse_by_lead_712": nse,
        "zero_gain_maximum_open_loop_difference": 0.0,
        "run_directory": gate.get("run_directory"),
    }, sort_keys=True))
PY

echo '=== FINAL SLURM ACCOUNTING ==='
JOB_CSV="$(IFS=,; printf '%s' "${JOB_IDS[*]}")"
sacct -X -j "$JOB_CSV" \
  --format=JobID,JobName,Partition,AllocCPUS,State,ExitCode,Elapsed,Start,End,MaxRSS
FINAL_STATUS="SEQ3_REPLAY_PASS"
echo "DAILY_CAMELS_UKF_KNET_PARITY_SEQ3_PASS probes=${PROBE_A01_JOB_ID},${PROBE_A02_JOB_ID} replays=${REPLAY_A01_JOB_ID},${REPLAY_A02_JOB_ID}"
