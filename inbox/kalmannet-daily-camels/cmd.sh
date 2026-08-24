#!/usr/bin/env bash
set -Eeuo pipefail

MAILBOX_ROOT="/data1/home/${USER}/hpc_mailbox"
PAYLOAD_DIRECTORY="${MAILBOX_ROOT}/payload/kalmannet-daily-camels/parity-train-resource-smoke-v7"
BASE="/data1/home/sunyiq/kalmannet_daily_camels_parity_20260824"
SOURCE_A07="${BASE}/source_A07_seq7"
RUN_PARENT="${BASE}/runs"
STATUS_DIRECTORY="${BASE}/status"
LOG_DIRECTORY="${BASE}/logs"
OUTBOX_DIRECTORY="${MAILBOX_ROOT}/outbox/kalmannet-daily-camels"

A05_ID="DAILY_CAMELS_UKF_PARITY_KNET_FULL_STATE_EXACT_REPLAY_DTYPE_REPAIR_V3_20260825_A05"
A06_ID="DAILY_CAMELS_UKF_PARITY_KNET_FULL_STATE_CAUSAL_REPLAY_DTYPE_REPAIR_V3_20260825_A06"
A07_ID="DAILY_CAMELS_UKF_PARITY_KNET_FULL_STATE_CAUSAL_TRAIN_TECHNICAL_SMOKE_V1_20260825_A07"
A07_ARCHIVE="${PAYLOAD_DIRECTORY}/${A07_ID}.tar.gz"
A07_SHA256="7f09c2316a007393ed889912709f038ad65a087343c53c307bbca472684edd34"
A07_SIZE=207908
EXACT_REPLAY_GATE="${STATUS_DIRECTORY}/replay_gate_${A05_ID}.json"
CAUSAL_REPLAY_GATE="${STATUS_DIRECTORY}/replay_gate_${A06_ID}.json"

EVIDENCE_NAME="DAILY_CAMELS_UKF_PARITY_CAUSAL_TRAIN_RESOURCE_SMOKE_V1_A07_SEQ7_evidence.tar.gz"
EVIDENCE_ARCHIVE="${OUTBOX_DIRECTORY}/${EVIDENCE_NAME}"
START_EPOCH="$(date +%s)"
SOFT_DEADLINE_EPOCH="$((START_EPOCH + 6300))"
BASE_OWNED=0
ALL_SUBMITTED_JOBS_TERMINAL=0
FINAL_STATUS="SEQ7_RECOVERY_STARTED"
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

  local snapshot="${BASE}/seq7_snapshot_$$"
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
    sacct -P --units=K -j "$job_csv" \
      --format=JobIDRaw,JobName,Partition,AllocCPUS,ReqMem,AllocTRES,State,ExitCode,Elapsed,Start,End,MaxRSS,MaxVMSize,AveRSS \
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
      source_A07_seq7/bundle_manifest.json \
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
trap 'FINAL_STATUS="SEQ7_INTERRUPTED_PARTIAL_PENDING"; exit 143' INT TERM

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
  raw="$(cd "$SOURCE_A07" && sbatch --parsable --mem=0 \
    hpc/daily_camels_ukf_knet_parity/submit_probe_gpu.slurm)"
  job_id="${raw%%;*}"
  case "$job_id" in
    ''|*[!0-9]*) echo "invalid Slurm probe job id: ${raw}" >&2; return 63 ;;
  esac
  printf '%s\n' "$job_id" > "${STATUS_DIRECTORY}/seq7_probe_A07_job_id.txt"
  JOB_IDS+=("$job_id")
  SUBMITTED_JOB_ID="$job_id"
  printf 'submitted label=probe_A07 job_id=%s memory_request=all_schedulable_node_memory\n' "$job_id"
}

submit_train() {
  local raw job_id
  raw="$(cd "$SOURCE_A07" && sbatch --parsable --mem=0 \
    --export=ALL,PARITY_EXACT_REPLAY_GATE="${EXACT_REPLAY_GATE}",PARITY_CAUSAL_REPLAY_GATE="${CAUSAL_REPLAY_GATE}" \
    hpc/daily_camels_ukf_knet_parity/submit_train_gpu.slurm)"
  job_id="${raw%%;*}"
  case "$job_id" in
    ''|*[!0-9]*) echo "invalid Slurm training job id: ${raw}" >&2; return 64 ;;
  esac
  printf '%s\n' "$job_id" > "${STATUS_DIRECTORY}/seq7_train_A07_job_id.txt"
  JOB_IDS+=("$job_id")
  SUBMITTED_JOB_ID="$job_id"
  printf 'submitted label=train_A07 job_id=%s memory_request=all_schedulable_node_memory\n' "$job_id"
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

test ! -e "$EVIDENCE_ARCHIVE" || {
  echo "refusing to replace existing seq7 evidence: $EVIDENCE_ARCHIVE" >&2
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
[[ ! -e "$SOURCE_A07" ]] || {
  echo "seq7 source directory already exists; refusing to replace it" >&2
  exit 68
}
if find "$STATUS_DIRECTORY" -maxdepth 1 -type f -name 'seq7_*' -print -quit | grep -q .; then
  echo "seq7 already recorded status evidence; refusing duplicate submission" >&2
  exit 69
fi
[[ ! -e "${RUN_PARENT}/${A07_ID}" ]] || {
  echo "seq7 run directory already exists: ${RUN_PARENT}/${A07_ID}" >&2
  exit 70
}
for phase in probe replay train; do
  [[ ! -e "${STATUS_DIRECTORY}/locks/${A07_ID}.${phase}.lock" ]] || {
    echo "seq7 phase lock already exists: ${A07_ID}.${phase}" >&2
    exit 71
  }
done
if find "$STATUS_DIRECTORY" -maxdepth 1 -type f \
    \( -name "probe-${A07_ID}-*.json" \
       -o -name "entry-probe-${A07_ID}-*.json" \
       -o -name "train-preflight-${A07_ID}-*.json" \
       -o -name "train-gpu-resources-${A07_ID}-*.csv" \
       -o -name "train-cgroup-resources-${A07_ID}-*.txt" \) \
    -print -quit | grep -q .; then
  echo "seq7 A07 status evidence already exists" >&2
  exit 72
fi
for gate in "$EXACT_REPLAY_GATE" "$CAUSAL_REPLAY_GATE"; do
  [[ -f "$gate" && ! -L "$gate" ]] || {
    echo "required replay gate is absent or symbolic: $gate" >&2
    exit 73
  }
done
FINAL_STATUS="SEQ7_NAMESPACE_ABSENCE_VERIFIED"

echo '=== VERIFY IMMUTABLE PAYLOAD AND REPLAY GATES ==='
archive_identity_check "$A07_ARCHIVE" "$A07_SHA256" "$A07_SIZE"
mkdir "$SOURCE_A07"
tar -xzf "$A07_ARCHIVE" -C "$SOURCE_A07"

set +u
source "/data1/home/${USER}/miniconda3/etc/profile.d/conda.sh"
conda activate nh_final
set -u
export PYTHONDONTWRITEBYTECODE=1
python - "$SOURCE_A07" "$A07_ID" "$A05_ID" "$A06_ID" "$EXACT_REPLAY_GATE" "$CAUSAL_REPLAY_GATE" <<'PY'
import json
import math
from pathlib import Path
import sys

source = Path(sys.argv[1])
expected_active_id, exact_id, causal_id = sys.argv[2:5]
exact_gate_path, causal_gate_path = map(Path, sys.argv[5:7])
manifest = json.loads((source / "bundle_manifest.json").read_text(encoding="utf-8"))
active = json.loads((source / manifest["active_config_member"]).read_text(encoding="utf-8"))
exact_config = json.loads(
    (source / manifest["exact_replay_config_member"]).read_text(encoding="utf-8")
)
policy = active.get("execution_policy", {})
optimization = active.get("optimization", {})
reference = active.get("reference", {})
if (
    manifest.get("experiment_id") != expected_active_id
    or active.get("experiment_id") != expected_active_id
    or exact_config.get("experiment_id") != exact_id
    or active.get("initialization", {}).get("execution_mode") != "causal_shared_spinup"
    or policy.get("allow_probe") is not True
    or policy.get("allow_replay") is not False
    or policy.get("allow_training") is not True
    or optimization.get("training_epochs") != 1
    or optimization.get("steps_per_epoch") != 1
    or reference.get("reference_status") != "frozen_from_seq6_causal_replay_gate_A06"
):
    raise SystemExit("seq7 training bundle identity or technical-smoke budget differs")

expected_gates = (
    (exact_gate_path, exact_id, "exact_tukf06_backward_time_diagnostic"),
    (causal_gate_path, causal_id, "causal_shared_spinup"),
)
for path, experiment_id, mode in expected_gates:
    gate = json.loads(path.read_text(encoding="utf-8"))
    if (
        gate.get("status") != "REPLAY_PASS"
        or gate.get("experiment_id") != experiment_id
        or gate.get("initialization_mode") != mode
        or gate.get("entry_exit_code") != 0
        or gate.get("ukf_replay_contract_passed") is not True
        or gate.get("zero_gain_contract_passed") is not True
    ):
        raise SystemExit(f"seq7 replay gate differs: {experiment_id}")
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
    raise SystemExit("seq7 frozen causal reference differs from the A06 replay gate")
PY
python -u "${SOURCE_A07}/hpc/daily_camels_ukf_knet_parity/preflight.py" \
  --bundle-root "$SOURCE_A07" --phase probe --offline-bundle-check \
  --report "${STATUS_DIRECTORY}/seq7_offline_A07.json"
FINAL_STATUS="SEQ7_OFFLINE_BUNDLE_AND_REPLAY_GATES_VERIFIED"

echo '=== SUBMIT READ-ONLY A07 GPU PROBE WITH WHOLE-NODE MEMORY REQUEST ==='
submit_probe
PROBE_JOB_ID="$SUBMITTED_JOB_ID"
FINAL_STATUS="SEQ7_PROBE_SUBMITTED"
if ! wait_for_jobs "$PROBE_JOB_ID"; then
  FINAL_STATUS="SEQ7_PROBE_PARTIAL_PENDING"
  echo "soft deadline reached while the probe is pending; no training submitted" >&2
  exit 74
fi
ALL_SUBMITTED_JOBS_TERMINAL=1
require_probe_succeeded "$PROBE_JOB_ID" || {
  FINAL_STATUS="SEQ7_PROBE_HARD_STOP"
  exit 75
}
python - "$STATUS_DIRECTORY" "$A07_ID" "$PROBE_JOB_ID" <<'PY'
import json
from pathlib import Path
import sys

status, experiment_id, job_id = Path(sys.argv[1]), sys.argv[2], sys.argv[3]
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
    or scheduled.get("cuda_probe_without_torch_import", {}).get("visible_device_count") != 1
    or int(scheduled.get("available_host_memory_bytes") or 0) <= 0
    or entry.get("status") != "PREFLIGHT_PASS"
    or entry.get("phase") != "probe"
    or entry.get("run_directory_absent") is not True
    or entry.get("reserved_evaluation_period_access_authorized") is not False
    or entry.get("array_members_materialized") != 0
    or entry.get("numerical_frameworks_imported_by_entry") != 0
):
    raise SystemExit("seq7 A07 probe evidence differs")
print(json.dumps({
    "experiment_id": experiment_id,
    "probe_job_id": job_id,
    "hostname": scheduled["hostname"],
    "available_host_memory_bytes": scheduled["available_host_memory_bytes"],
    "gpu": scheduled["cuda_probe_without_torch_import"],
    "probe_gate": "PASS",
}, sort_keys=True))
PY
FINAL_STATUS="SEQ7_PROBE_PASS"

echo '=== SUBMIT ONE-EPOCH ONE-STEP REAL BACKPROPAGATION RESOURCE SMOKE ==='
ALL_SUBMITTED_JOBS_TERMINAL=0
submit_train
TRAIN_JOB_ID="$SUBMITTED_JOB_ID"
FINAL_STATUS="SEQ7_TRAIN_SUBMITTED"
if ! wait_for_jobs "$TRAIN_JOB_ID"; then
  FINAL_STATUS="SEQ7_TRAIN_PARTIAL_PENDING"
  echo "soft deadline reached while training is pending; the job was not cancelled" >&2
  exit 76
fi
ALL_SUBMITTED_JOBS_TERMINAL=1
if ! classify_train_completion "$TRAIN_JOB_ID"; then
  FINAL_STATUS="SEQ7_TRAIN_TECHNICAL_HARD_STOP"
  exit 77
fi
printf 'train_exit_class=%s\n' "$TRAIN_EXIT_CLASS"

SACCT_RESOURCE_FILE="${STATUS_DIRECTORY}/seq7_train_A07_sacct_resources.txt"
[[ ! -e "$SACCT_RESOURCE_FILE" ]] || {
  echo "refusing to replace seq7 Slurm resource evidence" >&2
  exit 78
}
sacct -P --units=K -j "$TRAIN_JOB_ID" \
  --format=JobIDRaw,JobName,Partition,AllocCPUS,ReqMem,AllocTRES,State,ExitCode,Elapsed,Start,End,MaxRSS,MaxVMSize,AveRSS \
  > "$SACCT_RESOURCE_FILE"

FINAL_STATUS="SEQ7_TRAIN_EVIDENCE_CHECK"
python - "$RUN_PARENT" "$STATUS_DIRECTORY" "$A07_ID" "$TRAIN_JOB_ID" "$TRAIN_EXIT_CLASS" <<'PY'
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
if len(history) != 2 or [row.get("epoch") for row in history] != [0, 1]:
    raise SystemExit("A07 did not preserve exactly epoch zero and epoch one")
for relative, expected in manifest.get("files", {}).items():
    path = run / relative
    if not path.is_file() or sha256(path) != expected:
        raise SystemExit(f"A07 manifest mismatch: {relative}")

training = summary.get("training") or {}
epoch_zero, epoch_one = history
expected_status = (
    "TRAINING_COMPLETE_GATE_PASS"
    if exit_class == "scientific_gate_pass"
    else "TRAINING_COMPLETE_GATE_FAIL"
)
if (
    summary.get("status") != expected_status
    or completion.get("status") != expected_status
    or summary.get("experiment_id") != experiment_id
    or summary.get("phase") != "train"
    or summary.get("initialization_mode") != "causal_shared_spinup"
    or summary.get("zero_gain_maximum_open_loop_difference") != 0.0
    or summary.get("access_ledger", {}).get("evaluation_array_reads") != 0
    or training.get("status") != expected_status
    or training.get("optimizer_steps") != 1
    or training.get("sampled_forecast_events") != 306
    or not training.get("nonzero_gradient_parameter_names")
    or training.get("last_parameter_sha256") == training.get("epoch_zero_parameter_sha256")
    or epoch_one.get("optimizer_steps") != 1
    or epoch_one.get("sampled_forecast_events") != 306
    or epoch_one.get("finite_gradients") is not True
    or epoch_one.get("nonzero_gradient_parameter_tensor_count", 0) <= 0
    or epoch_one.get("epoch_optimizer_step_count") != 1
    or epoch_one.get("training_sampled_finite_target_event_count_by_lead")
       != {"1": 102, "2": 102, "3": 102}
    or epoch_zero.get("training_objective_physical_unit_multilead_mse") is not None
    or not math.isfinite(float(epoch_one["training_objective_physical_unit_multilead_mse"]))
):
    raise SystemExit("A07 technical training evidence differs")

resources = summary.get("resource_peaks", {})
host_process_peak = int(resources.get("host_peak_rss_bytes") or 0)
torch_reserved = int(resources.get("graphics_peak_reserved_bytes") or 0)
if host_process_peak <= 0 or torch_reserved <= 0:
    raise SystemExit("A07 entry resource peaks are absent")

gpu_log = status / f"train-gpu-resources-{experiment_id}-{job_id}.csv"
cgroup_log = status / f"train-cgroup-resources-{experiment_id}-{job_id}.txt"
sacct_log = status / "seq7_train_A07_sacct_resources.txt"
for path in (gpu_log, cgroup_log, sacct_log):
    if not path.is_file() or path.stat().st_size <= 0:
        raise SystemExit(f"A07 resource receipt is absent: {path.name}")

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
    raise SystemExit("A07 GPU resource sampler produced no valid samples")
if len({row["uuid"] for row in gpu_rows}) != 1:
    raise SystemExit("A07 GPU resource samples span multiple devices")
gpu_baseline_used = gpu_rows[0]["used_mib"] * 1024 * 1024
gpu_sampled_peak_used = max(row["used_mib"] for row in gpu_rows) * 1024 * 1024
gpu_incremental_peak = max(0, gpu_sampled_peak_used - gpu_baseline_used)

cgroup_values = {}
for line in cgroup_log.read_text(encoding="utf-8").splitlines():
    if "=" in line:
        key, value = line.split("=", 1)
        cgroup_values[key] = value
cgroup_peaks = []
for key in ("current_memory_peak", "parent_memory_peak"):
    value = cgroup_values.get(key, "")
    if value.isdigit():
        cgroup_peaks.append(int(value))
cgroup_peak = max(cgroup_peaks, default=0)

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
host_basis = max(host_process_peak, cgroup_peak, slurm_step_peak)
gpu_basis = max(torch_reserved, gpu_incremental_peak)
if host_basis <= 0 or gpu_basis <= 0:
    raise SystemExit("A07 did not produce usable host and GPU peak bases")

resource_summary = {
    "schema_version": "daily_camels_ukf_knet_resource_smoke_v1",
    "status": "RESOURCE_SMOKE_PASS",
    "experiment_id": experiment_id,
    "slurm_job_id": job_id,
    "training_exit_class": exit_class,
    "scientific_gate_passed": bool(training.get("gate_passed")),
    "host_process_peak_rss_bytes": host_process_peak,
    "host_cgroup_peak_bytes": cgroup_peak,
    "slurm_step_max_rss_bytes": slurm_step_peak,
    "host_peak_basis_bytes": host_basis,
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
    "completion_sha256": sha256(run / "completion.marker.json"),
    "gpu_resource_log_sha256": sha256(gpu_log),
    "cgroup_resource_log_sha256": sha256(cgroup_log),
    "sacct_resource_log_sha256": sha256(sacct_log),
}
target = status / "seq7_A07_resource_summary.json"
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
    "sampled_forecast_events": 306,
    "last_parameter_hash_changed": True,
    "resource_summary": resource_summary,
}, sort_keys=True))
PY

echo '=== FINAL SLURM ACCOUNTING WITH JOB STEPS ==='
JOB_CSV="$(IFS=,; printf '%s' "${JOB_IDS[*]}")"
sacct --units=K -j "$JOB_CSV" \
  --format=JobID,JobName,Partition,AllocCPUS,ReqMem,State,ExitCode,Elapsed,Start,End,MaxRSS,MaxVMSize,AveRSS
FINAL_STATUS="SEQ7_RESOURCE_SMOKE_PASS"
echo "DAILY_CAMELS_UKF_KNET_PARITY_SEQ7_RESOURCE_SMOKE_PASS probe=${PROBE_JOB_ID} train=${TRAIN_JOB_ID} train_exit_class=${TRAIN_EXIT_CLASS}"
