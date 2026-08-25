#!/usr/bin/env bash
# ABORTED BEFORE SUBMISSION; original draft SHA-256: 78aac949f334ab9d5eec960791d5258a2ad5a43907baf71bc937d8689784e58e
set -Eeuo pipefail

MAILBOX_ROOT="/data1/home/${USER}/hpc_mailbox"
PAYLOAD_DIRECTORY="${MAILBOX_ROOT}/payload/kalmannet-daily-camels/masked-nse-equal-basin-a18-v16"
EXPERIMENT_ID="DAILY_CAMELS_NATIVE_KALMANNET_MASKED_NSE_SMOKE_V1_20260825_A18"
ARCHIVE="${PAYLOAD_DIRECTORY}/${EXPERIMENT_ID}.tar.gz"
ARCHIVE_SHA256="9128035b2a2627cf50e1156be24c9be609b335167fb13ff9402028489debc70c"
ARCHIVE_SIZE=198945
OUTER_MANIFEST="${PAYLOAD_DIRECTORY}/bundle_manifest.sha256.json"
OUTER_MANIFEST_SHA256="b10020e5b5e075ea784b06709d0c7b13d275226be300784f684953e6e6d06131"
OUTER_MANIFEST_SIZE=5199
INTERNAL_MANIFEST_SHA256="913971d937790f2d4bb1302232b67fa3d5e46e7d4b07fa7fba54ee0d6d330029"
CONFIG_SHA256="f6ee9bf7f57e97ef6eb630f95f232f80e6d5c9f1f2a6fd67bc76b6eba578eaed"

BASE="/data1/home/sunyiq/kalmannet_daily_camels_masked_nse_20260825"
SOURCE_DIRECTORY="${BASE}/source_A18_seq16"
TRANSPORT_DIRECTORY="${BASE}/transport"
STATUS_DIRECTORY="${BASE}/status"
LOG_DIRECTORY="${BASE}/logs"
RUN_DIRECTORY="${BASE}/${EXPERIMENT_ID}"
OUTBOX_DIRECTORY="${MAILBOX_ROOT}/outbox/kalmannet-daily-camels"
EVIDENCE_NAME="DAILY_CAMELS_NATIVE_KALMANNET_MASKED_NSE_A18_SEQ16_evidence.tar.gz"
EVIDENCE_ARCHIVE="${OUTBOX_DIRECTORY}/${EVIDENCE_NAME}"

START_EPOCH="$(date +%s)"
SOFT_DEADLINE_EPOCH="$((START_EPOCH + 5400))"
NAMESPACE_OWNED=0
ALL_SUBMITTED_JOBS_TERMINAL=0
FINAL_STATUS="SEQ16_A18_STARTED"
declare -a JOB_IDS=()

sha256_file() {
  sha256sum "$1" | awk '{print $1}'
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

package_evidence() {
  local command_exit_code="$1"
  set +e
  if [[ "$NAMESPACE_OWNED" -ne 1 ]]; then
    printf 'evidence_archive=NOT_CREATED namespace_not_owned=1 status=%s exit_code=%s\n' \
      "$FINAL_STATUS" "$command_exit_code"
    return 0
  fi
  mkdir -p "$OUTBOX_DIRECTORY"
  if [[ -e "$EVIDENCE_ARCHIVE" ]]; then
    printf 'evidence_archive=NOT_REPLACED existing=%s status=%s exit_code=%s\n' \
      "$EVIDENCE_ARCHIVE" "$FINAL_STATUS" "$command_exit_code"
    return 0
  fi

  local snapshot="${BASE}/seq16_A18_snapshot_$$"
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
  for candidate in "${STATUS_DIRECTORY}"/*; do
    [[ -f "$candidate" && ! -L "$candidate" ]] || continue
    cp -p "$candidate" "${snapshot}/status/"
  done
  for candidate in "${LOG_DIRECTORY}"/*; do
    [[ -f "$candidate" && ! -L "$candidate" ]] || continue
    cp -p "$candidate" "${snapshot}/logs/"
  done
  if [[ -f "${SOURCE_DIRECTORY}/bundle_manifest.json" && ! -L "${SOURCE_DIRECTORY}/bundle_manifest.json" ]]; then
    cp -p "${SOURCE_DIRECTORY}/bundle_manifest.json" "${snapshot}/source/"
  fi

  local temporary_archive="${OUTBOX_DIRECTORY}/.${EVIDENCE_NAME}.$$"
  local -a members
  members=("$(basename "$snapshot")")
  if [[ "$ALL_SUBMITTED_JOBS_TERMINAL" -eq 1 && -d "$RUN_DIRECTORY" && ! -L "$RUN_DIRECTORY" ]]; then
    if find "$RUN_DIRECTORY" -type l -print -quit | grep -q .; then
      printf 'evidence_archive=CREATE_FAILED symbolic_run_member=1 status=%s exit_code=%s\n' \
        "$FINAL_STATUS" "$command_exit_code"
      return 0
    fi
    members+=("$EXPERIMENT_ID")
  fi
  tar -czf "$temporary_archive" -C "$BASE" "${members[@]}"
  if [[ -s "$temporary_archive" && ! -e "$EVIDENCE_ARCHIVE" ]]; then
    mv "$temporary_archive" "$EVIDENCE_ARCHIVE"
    printf 'evidence_archive=%s\n' "$EVIDENCE_ARCHIVE"
    printf 'evidence_archive_sha256=%s\n' "$(sha256_file "$EVIDENCE_ARCHIVE")"
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
trap 'FINAL_STATUS="SEQ16_A18_INTERRUPTED_PARTIAL_PENDING"; exit 143' INT TERM

test ! -e "$BASE" || {
  echo "isolated A18 base already exists; refusing to overwrite or duplicate: $BASE" >&2
  exit 60
}
test ! -e "$EVIDENCE_ARCHIVE" || {
  echo "A18 evidence archive already exists; refusing replacement" >&2
  exit 61
}
for path in "$ARCHIVE" "$OUTER_MANIFEST"; do
  [[ -f "$path" && ! -L "$path" ]] || {
    echo "payload member absent or symbolic: $path" >&2
    exit 62
  }
done
[[ "$(sha256_file "$ARCHIVE")" = "$ARCHIVE_SHA256" && "$(stat -c '%s' "$ARCHIVE")" = "$ARCHIVE_SIZE" ]] || {
  echo "A18 archive identity differs" >&2
  exit 63
}
[[ "$(sha256_file "$OUTER_MANIFEST")" = "$OUTER_MANIFEST_SHA256" && "$(stat -c '%s' "$OUTER_MANIFEST")" = "$OUTER_MANIFEST_SIZE" ]] || {
  echo "A18 outer manifest identity differs" >&2
  exit 64
}

mkdir "$BASE"
NAMESPACE_OWNED=1
mkdir "$SOURCE_DIRECTORY" "$TRANSPORT_DIRECTORY" "$STATUS_DIRECTORY" "$LOG_DIRECTORY"
cp -p "$ARCHIVE" "${TRANSPORT_DIRECTORY}/"
cp -p "$OUTER_MANIFEST" "${TRANSPORT_DIRECTORY}/bundle_manifest.sha256.json"
tar -xzf "$ARCHIVE" -C "$SOURCE_DIRECTORY"

python - "$SOURCE_DIRECTORY" "$OUTER_MANIFEST" "$EXPERIMENT_ID" \
  "$ARCHIVE_SHA256" "$INTERNAL_MANIFEST_SHA256" "$CONFIG_SHA256" <<'PY'
from hashlib import sha256
import json
from pathlib import Path
import sys

source = Path(sys.argv[1])
outer_path = Path(sys.argv[2])
experiment_id, archive_sha, internal_sha, config_sha = sys.argv[3:7]

def digest(path):
    return sha256(path.read_bytes()).hexdigest()

outer = json.loads(outer_path.read_text(encoding="utf-8"))
internal_path = source / "bundle_manifest.json"
internal = json.loads(internal_path.read_text(encoding="utf-8"))
config_member = "configs/daily_camels_native_kalmannet_masked_nse_smoke_v1.json"
config = json.loads((source / config_member).read_text(encoding="utf-8"))
loss = config.get("loss_contract", {})
if (
    outer.get("experiment_id") != experiment_id
    or outer.get("archive_sha256") != archive_sha
    or outer.get("internal_manifest_sha256") != internal_sha
    or digest(internal_path) != internal_sha
    or outer.get("reserved_data_member_count") != 0
    or internal.get("reserved_data_member_count") != 0
    or internal.get("input_archive_count") != 2
    or internal.get("member_sha256", {}).get(config_member) != config_sha
    or config.get("experiment_id") != experiment_id
    or config.get("data", {}).get("cadence") != "daily"
    or loss.get("contract_name")
       != "daily_camels_formal_masked_nse_equal_basin_lead_v1"
    or loss.get("training_statistics_start_index") != 0
    or loss.get("training_statistics_stop_index_exclusive") != 2557
    or loss.get("population_standard_deviation_ddof") != 0
    or loss.get("loss_epsilon_original_discharge_units") != 0.1
    or config.get("checkpoint_selection", {}).get("metric")
       != "negative_shared_masked_nse_validation_loss"
):
    raise SystemExit("A18 bundle or scientific loss identity differs")
print(json.dumps({
    "status": "SEQ16_A18_OFFLINE_IDENTITY_PASS",
    "experiment_id": experiment_id,
    "member_count": internal["member_count"],
    "reserved_data_member_count": internal["reserved_data_member_count"],
    "loss_contract": loss["contract_name"],
}, sort_keys=True))
PY

export PYTHONDONTWRITEBYTECODE=1
python -u "${SOURCE_DIRECTORY}/hpc/daily_camels_native_kalmannet_masked_nse/preflight.py" \
  --bundle-root "$SOURCE_DIRECTORY" --offline-bundle-check \
  > "${STATUS_DIRECTORY}/seq16_A18_offline_bundle_check.json"
FINAL_STATUS="SEQ16_A18_OFFLINE_BUNDLE_VERIFIED"

echo '=== SUBMIT READ-ONLY A18 GPU PROBE ==='
PROBE_RAW="$(cd "$SOURCE_DIRECTORY" && sbatch --parsable --mem=2G \
  hpc/daily_camels_native_kalmannet_masked_nse/submit_probe_gpu.slurm)"
PROBE_JOB_ID="${PROBE_RAW%%;*}"
case "$PROBE_JOB_ID" in
  ''|*[!0-9]*) echo "invalid A18 probe job id: $PROBE_RAW" >&2; exit 65 ;;
esac
JOB_IDS+=("$PROBE_JOB_ID")
printf '%s\n' "$PROBE_JOB_ID" > "${STATUS_DIRECTORY}/seq16_A18_probe_job_id.txt"
FINAL_STATUS="SEQ16_A18_PROBE_SUBMITTED"
if ! wait_for_job "$PROBE_JOB_ID"; then
  FINAL_STATUS="SEQ16_A18_PROBE_PARTIAL_PENDING"
  echo "A18 probe remains pending at the soft deadline; training was not submitted" >&2
  exit 66
fi
ALL_SUBMITTED_JOBS_TERMINAL=1
require_completed_zero "$PROBE_JOB_ID" "probe_A18" || {
  FINAL_STATUS="SEQ16_A18_PROBE_HARD_STOP"
  exit 67
}

python - "$STATUS_DIRECTORY" "$EXPERIMENT_ID" "$PROBE_JOB_ID" "$RUN_DIRECTORY" <<'PY'
import json
from pathlib import Path
import sys

status, experiment_id, job_id, run_directory = Path(sys.argv[1]), *sys.argv[2:5]
report = json.loads(
    (status / f"probe-{job_id}.json").read_text(encoding="utf-8")
)
required = {
    "status": "PREFLIGHT_PASS",
    "experiment_id": experiment_id,
    "cuda_available": True,
    "cuda_device_count": 1,
    "run_root_absent": True,
    "array_members_materialized": 0,
    "reserved_data_member_count": 0,
    "input_archive_count": 2,
    "configuration_contract_validated": True,
    "runtime_interface_gap_count": 0,
}
for key, expected in required.items():
    if report.get(key) != expected:
        raise SystemExit(f"A18 probe admission mismatch: {key}")
if report.get("run_root") != run_directory:
    raise SystemExit("A18 probe checked a different run directory")
if int(report.get("available_host_memory_bytes") or 0) <= 0:
    raise SystemExit("A18 probe host-memory evidence is absent")
if int(report.get("cuda_free_bytes") or 0) <= 0:
    raise SystemExit("A18 probe graphics-memory evidence is absent")
print(json.dumps({
    "status": "SEQ16_A18_PROBE_PASS",
    "job_id": job_id,
    "host": report["hostname"],
    "available_host_memory_bytes": report["available_host_memory_bytes"],
    "cuda_free_bytes": report["cuda_free_bytes"],
}, sort_keys=True))
PY
FINAL_STATUS="SEQ16_A18_PROBE_PASS"

echo '=== SUBMIT UNIQUE EQUAL-BASIN MASKED-NSE TRAINING SMOKE ==='
ALL_SUBMITTED_JOBS_TERMINAL=0
TRAIN_RAW="$(cd "$SOURCE_DIRECTORY" && sbatch --parsable --mem=4G \
  hpc/daily_camels_native_kalmannet_masked_nse/submit_smoke_gpu.slurm)"
TRAIN_JOB_ID="${TRAIN_RAW%%;*}"
case "$TRAIN_JOB_ID" in
  ''|*[!0-9]*) echo "invalid A18 training job id: $TRAIN_RAW" >&2; exit 68 ;;
esac
JOB_IDS+=("$TRAIN_JOB_ID")
printf '%s\n' "$TRAIN_JOB_ID" > "${STATUS_DIRECTORY}/seq16_A18_train_job_id.txt"
FINAL_STATUS="SEQ16_A18_TRAIN_SUBMITTED"
if ! wait_for_job "$TRAIN_JOB_ID"; then
  FINAL_STATUS="SEQ16_A18_TRAIN_PARTIAL_PENDING"
  echo "A18 training remains pending at the soft deadline; it was not cancelled" >&2
  exit 69
fi
ALL_SUBMITTED_JOBS_TERMINAL=1
sacct -P --units=K -j "$TRAIN_JOB_ID" \
  --format=JobIDRaw,JobName,Partition,AllocCPUS,ReqMem,AllocTRES,State,ExitCode,Elapsed,Start,End,MaxRSS,MaxVMSize,AveRSS \
  > "${STATUS_DIRECTORY}/seq16_A18_train_sacct_resources.txt"

if ! require_completed_zero "$TRAIN_JOB_ID" "train_A18"; then
  FINAL_STATUS="SEQ16_A18_TRAIN_TECHNICAL_OR_SCIENTIFIC_HARD_STOP"
  exit 70
fi

python - "$RUN_DIRECTORY" "$STATUS_DIRECTORY" "$EXPERIMENT_ID" "$TRAIN_JOB_ID" <<'PY'
from hashlib import sha256
import json
import math
import os
from pathlib import Path
import sys

root, status = map(Path, sys.argv[1:3])
experiment_id, job_id = sys.argv[3:5]

def digest(path):
    return sha256(path.read_bytes()).hexdigest()

required = {
    "result_summary.json",
    "access_ledger.json",
    "manifest.sha256.json",
    "completion.marker.json",
    "training_scale_evidence.json",
    "experiment_identity.json",
    "events.jsonl",
}
for name in required:
    path = root / name
    if not path.is_file() or path.is_symlink():
        raise SystemExit(f"A18 missing sealed artifact: {name}")
summary = json.loads((root / "result_summary.json").read_text(encoding="utf-8"))
ledger = json.loads((root / "access_ledger.json").read_text(encoding="utf-8"))
manifest = json.loads((root / "manifest.sha256.json").read_text(encoding="utf-8"))
completion = json.loads((root / "completion.marker.json").read_text(encoding="utf-8"))
scales = json.loads((root / "training_scale_evidence.json").read_text(encoding="utf-8"))
history = summary.get("history", [])
gate = summary.get("science_gate", {})
if (
    summary.get("experiment_id") != experiment_id
    or summary.get("status") != "COMPLETED"
    or gate.get("passed") is not True
    or completion.get("experiment_id") != experiment_id
    or completion.get("status") != "COMPLETED"
    or [row.get("epoch") for row in history] != [0, 1, 2, 3, 4]
):
    raise SystemExit("A18 completion or epoch history differs")

scale_hash = scales.get("training_scale_evidence_sha256")
if (
    not isinstance(scale_hash, str)
    or len(scale_hash) != 64
    or summary.get("training_scale_evidence_sha256") != scale_hash
    or completion.get("training_scale_evidence_sha256") != scale_hash
    or gate.get("training_scale_evidence_sha256") != scale_hash
    or {row.get("training_scale_evidence_sha256") for row in history} != {scale_hash}
):
    raise SystemExit("A18 training-scale evidence chain differs")
scale_values = scales.get("scales", {})
if (
    scale_values.get("training_start_index") != 0
    or scale_values.get("validation_start_index") != 2557
    or scale_values.get("population_standard_deviation_ddof") != 0
    or scale_values.get("training_rows_per_basin") != 2557
    or scale_values.get("training_row_count") != 5114
    or float(scale_values.get("global_discharge_population_std") or 0.0) <= 0.0
    or set(scale_values.get("per_basin", {})) != {"04105700", "09035800"}
):
    raise SystemExit("A18 training-only scale geometry differs")
for basin in scale_values["per_basin"].values():
    if (
        basin.get("training_start_index") != 0
        or basin.get("validation_start_index") != 2557
        or basin.get("finite_observation_count") != 2557
        or float(basin.get("population_std_original_discharge_units") or 0.0) <= 0.0
    ):
        raise SystemExit("A18 per-basin training scale differs")

zero_loss = float(history[0]["validation_loss"])
best_loss = min(float(row["validation_loss"]) for row in history[1:])
best_row = min(history[1:], key=lambda row: float(row["validation_loss"]))
if not (
    math.isfinite(zero_loss)
    and math.isfinite(best_loss)
    and best_loss < zero_loss - 1.0e-6
    and int(gate.get("best_epoch") or 0) == int(best_row["epoch"])
    and math.isclose(
        float(gate.get("improvement")),
        zero_loss - best_loss,
        rel_tol=0.0,
        abs_tol=1.0e-12,
    )
):
    raise SystemExit("A18 did not prove real post-epoch-zero improvement")

for row in history:
    loss = float(row["validation_loss"])
    score = float(row["selection_score"])
    if not math.isclose(score, -loss, rel_tol=0.0, abs_tol=1.0e-12):
        raise SystemExit("A18 checkpoint score differs from the frozen loss")
    if set(row.get("per_basin", {})) != {"04105700", "09035800"}:
        raise SystemExit("A18 per-basin validation identities differ")
    if row.get("target_count_by_lead") != {"1": 218, "2": 218, "3": 218}:
        raise SystemExit("A18 validation target geometry differs")
for epoch, row in enumerate(history[1:], start=1):
    units = row.get("training_units", [])
    if (
        row.get("optimizer_steps") != epoch * 2
        or row.get("sampled_forecast_events") != epoch * 540
        or row.get("finite_gradients") is not True
        or int(row.get("nonzero_gradient_parameter_tensor_count") or 0) <= 0
        or float(row.get("routed_queue_correction_abs_max") or 0.0) != 0.0
        or len(units) != 4
    ):
        raise SystemExit(f"A18 epoch-{epoch} progress evidence differs")
    by_step = {}
    for unit in units:
        by_step.setdefault(int(unit["step_in_epoch"]), []).append(unit)
        if (
            int(unit["end_index_exclusive"]) - int(unit["start_index"]) != 64
            or int(unit["forecast_target_count"]) != 135
            or not math.isfinite(float(unit["masked_nse_loss"]))
        ):
            raise SystemExit(f"A18 epoch-{epoch} training unit differs")
    if set(by_step) != {0, 1} or any(
        {unit["basin_id"] for unit in values} != {"04105700", "09035800"}
        or len(values) != 2
        for values in by_step.values()
    ):
        raise SystemExit(f"A18 epoch-{epoch} is not equal-basin per optimizer step")

if (
    ledger.get("archive_materialization_sessions") != 1
    or ledger.get("archive_member_reads")
       != {"dates_ns": 2, "forcing": 2, "observations": 2, "parameters": 2}
):
    raise SystemExit("A18 development archive ledger differs")
for key in (
    "raw_source_byte_reads",
    "evaluation_array_reads",
    "evaluation_predictions",
    "evaluation_metrics",
    "evaluation_outputs",
):
    if ledger.get(key) != 0:
        raise SystemExit(f"A18 reserved-access counter is nonzero: {key}")

files = manifest.get("files", {})
if manifest.get("file_count") != len(files):
    raise SystemExit("A18 manifest count differs")
for relative, record in files.items():
    path = root.joinpath(*relative.split("/"))
    if (
        not path.is_file()
        or path.is_symlink()
        or digest(path) != record.get("sha256")
        or path.stat().st_size != record.get("size_bytes")
    ):
        raise SystemExit(f"A18 manifest mismatch: {relative}")
if (
    completion.get("manifest_sha256") != digest(root / "manifest.sha256.json")
    or completion.get("summary_sha256") != digest(root / "result_summary.json")
):
    raise SystemExit("A18 completion hash chain differs")

best_nse = {
    lead: float(value)
    for lead, value in best_row.get("knet_nse", {}).items()
}
verification = {
    "schema_version": "daily_camels_native_kalmannet_masked_nse_a18_verification_v1",
    "status": "A18_TECHNICAL_AND_LOSS_IMPROVEMENT_VERIFIED",
    "experiment_id": experiment_id,
    "slurm_job_id": job_id,
    "epoch_zero_validation_loss": zero_loss,
    "best_post_zero_validation_loss": best_loss,
    "validation_loss_improvement": zero_loss - best_loss,
    "best_epoch": int(best_row["epoch"]),
    "best_nse_by_lead": best_nse,
    "all_mean_nse_above_0_6": (
        set(best_nse) == {"1", "2", "3"}
        and all(value > 0.6 for value in best_nse.values())
    ),
    "training_scale_evidence_sha256": scale_hash,
    "optimizer_steps": int(history[-1]["optimizer_steps"]),
    "sampled_forecast_events": int(history[-1]["sampled_forecast_events"]),
    "reserved_access_counts": {
        key: ledger[key]
        for key in (
            "evaluation_array_reads",
            "evaluation_predictions",
            "evaluation_metrics",
            "evaluation_outputs",
        )
    },
    "result_summary_sha256": digest(root / "result_summary.json"),
    "manifest_sha256": digest(root / "manifest.sha256.json"),
    "completion_sha256": digest(root / "completion.marker.json"),
}
target = status / "seq16_A18_verification.json"
data = (json.dumps(verification, sort_keys=True, separators=(",", ":")) + "\n").encode()
descriptor = os.open(target, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
try:
    os.write(descriptor, data)
finally:
    os.close(descriptor)
print(json.dumps(verification, sort_keys=True))
PY

FINAL_STATUS="SEQ16_A18_TECHNICAL_AND_LOSS_IMPROVEMENT_VERIFIED"
echo '=== FINAL A18 ACCOUNTING ==='
JOB_CSV="$(IFS=,; printf '%s' "${JOB_IDS[*]}")"
sacct --units=K -j "$JOB_CSV" \
  --format=JobID,JobName,Partition,AllocCPUS,ReqMem,State,ExitCode,Elapsed,Start,End,MaxRSS,MaxVMSize,AveRSS
echo "DAILY_CAMELS_NATIVE_KALMANNET_MASKED_NSE_A18_PASS probe=${PROBE_JOB_ID} train=${TRAIN_JOB_ID}"
