#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

EXPECTED_USER="sunyiq"
MAILBOX_ROOT="/data1/home/sunyiq/hpc_mailbox"
PAYLOAD_DIRECTORY="${MAILBOX_ROOT}/payload/kalmannet-daily-camels/masked-nse-physical-evidence-a20-v16"
EXPERIMENT_ID="DAILY_CAMELS_NATIVE_KALMANNET_MASKED_NSE_SMOKE_V3_20260825_A20"
ARCHIVE="${PAYLOAD_DIRECTORY}/${EXPERIMENT_ID}.tar.gz"
ARCHIVE_SHA256="44f6df340807d81662e7ccf905e533df61bfbbd4897335303b3e30ddf681a520"
ARCHIVE_SIZE=211055
OUTER_MANIFEST="${PAYLOAD_DIRECTORY}/bundle_manifest.sha256.json"
OUTER_MANIFEST_SHA256="83e81d0d64f2dab1313df4c5313af98d197f55d9f54981d72b1c161da2bd6455"
OUTER_MANIFEST_SIZE=5412
INTERNAL_MANIFEST_SHA256="6be4ec56bbb04055b9316532ebe0ae30fa5fc44f573e2297aa6439c1665cb974"
CONFIG_SHA256="6c2dd29b92505bd394bce2c18af6a6a429264aecabd6b1b2b7099219b7c240b8"
VERIFY_RESULT_SHA256="d3d7191f091e994b207c10a975ea95b9cb06b8b7206c9b86a565c92f22546c63"

BASE="/data1/home/sunyiq/kalmannet_daily_camels_masked_nse_v3_20260825"
SOURCE_DIRECTORY="${BASE}/source_A20_seq16"
TRANSPORT_DIRECTORY="${BASE}/transport"
STATUS_DIRECTORY="${BASE}/status"
LOG_DIRECTORY="${BASE}/logs"
PRIVATE_EVIDENCE_DIRECTORY="${BASE}/private_evidence_staging"
RUN_DIRECTORY="${BASE}/${EXPERIMENT_ID}"
OUTBOX_DIRECTORY="${MAILBOX_ROOT}/outbox/kalmannet-daily-camels"
EVIDENCE_NAME="DAILY_CAMELS_NATIVE_KALMANNET_MASKED_NSE_A20_SEQ16_evidence.tar.gz"
EVIDENCE_ARCHIVE="${OUTBOX_DIRECTORY}/${EVIDENCE_NAME}"

START_EPOCH="$(date +%s)"
SOFT_DEADLINE_EPOCH="$((START_EPOCH + 5400))"
ATTEMPT_ID="$(date -u +%Y%m%dT%H%M%SZ)-$$"
NAMESPACE_OWNED=0
ALL_SUBMITTED_JOBS_TERMINAL=1
JOB_COUNT=0
JOB_IDS_CSV=""
PROBE_JOB_ID=""
TRAIN_JOB_ID=""
FINAL_STATUS="SEQ16_A20_STARTED"

sha256_file() {
  sha256sum "$1" | awk '{print $1}'
}

verify_regular_identity() {
  local path="$1" expected_sha="$2" expected_size="$3"
  [[ -f "$path" && ! -L "$path" ]] || return 1
  [[ "$(stat -c '%s' "$path")" = "$expected_size" ]] || return 1
  [[ "$(sha256_file "$path")" = "$expected_sha" ]]
}

register_job_id() {
  local job_id="$1"
  case "$job_id" in
    ''|*[!0-9]*) return 1 ;;
  esac
  if [[ -z "$JOB_IDS_CSV" ]]; then
    JOB_IDS_CSV="$job_id"
  else
    JOB_IDS_CSV="${JOB_IDS_CSV},${job_id}"
  fi
  JOB_COUNT=$((JOB_COUNT + 1))
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

cancel_known_jobs() {
  local cancel_deadline live
  if [[ -n "$TRAIN_JOB_ID" ]]; then
    scancel "$TRAIN_JOB_ID" 2>/dev/null || true
  fi
  if [[ -n "$PROBE_JOB_ID" ]]; then
    scancel "$PROBE_JOB_ID" 2>/dev/null || true
  fi
  if [[ "$JOB_COUNT" -eq 0 ]]; then
    ALL_SUBMITTED_JOBS_TERMINAL=1
    return 0
  fi
  cancel_deadline="$(( $(date +%s) + 180 ))"
  while (( $(date +%s) < cancel_deadline )); do
    live="$(squeue -h -j "$JOB_IDS_CSV" -o '%i' 2>/dev/null || true)"
    if [[ -z "$live" ]]; then
      ALL_SUBMITTED_JOBS_TERMINAL=1
      return 0
    fi
    sleep 5
  done
  ALL_SUBMITTED_JOBS_TERMINAL=0
  return 1
}

publish_no_replace() {
  local source="$1" destination="$2"
  python - "$source" "$destination" <<'PY'
import os
from pathlib import Path
import stat
import sys

source, destination = map(Path, sys.argv[1:3])
source_record = os.stat(source, follow_symlinks=False)
parent_record = os.stat(destination.parent, follow_symlinks=False)
if not stat.S_ISREG(source_record.st_mode):
    raise SystemExit("publication source is not a regular file")
if not stat.S_ISDIR(parent_record.st_mode):
    raise SystemExit("publication parent is not a real directory")
if source_record.st_dev != parent_record.st_dev:
    raise SystemExit("evidence staging and outbox are on different filesystems")
if os.path.lexists(destination):
    raise SystemExit("evidence destination already exists")
os.link(source, destination, follow_symlinks=False)
published = os.stat(destination, follow_symlinks=False)
if (
    published.st_dev != source_record.st_dev
    or published.st_ino != source_record.st_ino
    or published.st_size != source_record.st_size
):
    raise SystemExit("published evidence identity differs")
directory_fd = os.open(
    str(destination.parent),
    os.O_RDONLY | getattr(os, "O_DIRECTORY", 0),
)
try:
    os.fsync(directory_fd)
finally:
    os.close(directory_fd)
PY
}

package_evidence() {
  local command_exit_code="$1"
  local snapshot snapshot_name temporary_archive evidence_destination
  local candidate
  if [[ "$NAMESPACE_OWNED" -ne 1 ]]; then
    printf 'evidence_archive=NOT_CREATED namespace_not_owned=1 status=%s exit_code=%s\n' \
      "$FINAL_STATUS" "$command_exit_code"
    return 0
  fi
  mkdir -p "$OUTBOX_DIRECTORY" || return 91
  snapshot="${BASE}/seq16_A20_snapshot_$$"
  snapshot_name="$(basename "$snapshot")"
  mkdir "$snapshot" || return 92
  mkdir "$snapshot/status" "$snapshot/logs" "$snapshot/source" "$snapshot/transport" || return 93
  printf '%s\n' "$FINAL_STATUS" > "${snapshot}/final_status.txt" || return 94
  printf '%s\n' "$command_exit_code" > "${snapshot}/command_exit_code.txt" || return 95
  printf '%s\n' "$JOB_COUNT" > "${snapshot}/submitted_job_count.txt" || return 96
  if [[ "$JOB_COUNT" -gt 0 ]]; then
    printf '%s\n' "$JOB_IDS_CSV" > "${snapshot}/submitted_job_ids.txt" || return 97
    squeue -h -j "$JOB_IDS_CSV" -o '%i|%T|%R|%M|%l' \
      > "${snapshot}/squeue_snapshot.txt" 2>&1 || true
    sacct -P --units=K -j "$JOB_IDS_CSV" \
      --format=JobIDRaw,JobName,Partition,AllocCPUS,ReqMem,AllocTRES,State,ExitCode,Elapsed,Start,End,MaxRSS,MaxVMSize,AveRSS \
      > "${snapshot}/sacct_snapshot.txt" 2>&1 || true
  else
    : > "${snapshot}/submitted_job_ids.txt"
  fi
  date -u +%Y-%m-%dT%H:%M:%SZ > "${snapshot}/snapshot_time_utc.txt" || return 98
  for candidate in "${STATUS_DIRECTORY}"/*; do
    [[ -f "$candidate" && ! -L "$candidate" ]] || continue
    cp -p -- "$candidate" "${snapshot}/status/" || return 99
  done
  for candidate in "${LOG_DIRECTORY}"/*; do
    [[ -f "$candidate" && ! -L "$candidate" ]] || continue
    cp -p -- "$candidate" "${snapshot}/logs/" || return 100
  done
  if [[ -f "${SOURCE_DIRECTORY}/bundle_manifest.json" && ! -L "${SOURCE_DIRECTORY}/bundle_manifest.json" ]]; then
    cp -p -- "${SOURCE_DIRECTORY}/bundle_manifest.json" "${snapshot}/source/" || return 101
  fi
  if [[ -f "${TRANSPORT_DIRECTORY}/bundle_manifest.sha256.json" && ! -L "${TRANSPORT_DIRECTORY}/bundle_manifest.sha256.json" ]]; then
    cp -p -- "${TRANSPORT_DIRECTORY}/bundle_manifest.sha256.json" "${snapshot}/transport/" || return 102
  fi
  if find "$snapshot" -type l -print -quit | grep -q .; then
    return 103
  fi

  temporary_archive="$(mktemp "${PRIVATE_EVIDENCE_DIRECTORY}/evidence.XXXXXX.tar.gz")" || return 104
  if [[ "$ALL_SUBMITTED_JOBS_TERMINAL" -eq 1 ]]; then
    evidence_destination="$EVIDENCE_ARCHIVE"
    if [[ -d "$RUN_DIRECTORY" && ! -L "$RUN_DIRECTORY" ]]; then
      if find "$RUN_DIRECTORY" -type l -print -quit | grep -q .; then
        return 105
      fi
      tar -czf "$temporary_archive" -C "$BASE" "$snapshot_name" "$EXPERIMENT_ID" || return 106
    else
      tar -czf "$temporary_archive" -C "$BASE" "$snapshot_name" || return 107
    fi
  else
    evidence_destination="${OUTBOX_DIRECTORY}/${EXPERIMENT_ID}.partial-pending.${ATTEMPT_ID}.tar.gz"
    tar -czf "$temporary_archive" -C "$BASE" "$snapshot_name" || return 108
  fi
  [[ -s "$temporary_archive" ]] || return 109
  gzip -t "$temporary_archive" || return 110
  tar -tzf "$temporary_archive" >/dev/null || return 111
  publish_no_replace "$temporary_archive" "$evidence_destination" || return 112
  printf 'evidence_archive=%s\n' "$evidence_destination"
  printf 'evidence_archive_sha256=%s\n' "$(sha256_file "$evidence_destination")"
  printf 'evidence_archive_size=%s\n' "$(stat -c '%s' "$evidence_destination")"
  printf 'evidence_status=%s command_exit_code=%s all_jobs_terminal=%s\n' \
    "$FINAL_STATUS" "$command_exit_code" "$ALL_SUBMITTED_JOBS_TERMINAL"
  rm -- "$temporary_archive" || return 113
  return 0
}

on_exit() {
  local main_exit_code="$?" package_exit_code=0
  trap - EXIT INT TERM
  set +e
  package_evidence "$main_exit_code"
  package_exit_code="$?"
  if [[ "$main_exit_code" -eq 0 && "$package_exit_code" -ne 0 ]]; then
    printf 'main workflow succeeded but evidence packaging failed: %s\n' \
      "$package_exit_code" >&2
    exit 90
  fi
  if [[ "$main_exit_code" -ne 0 && "$package_exit_code" -ne 0 ]]; then
    printf 'main failure=%s; additional evidence failure=%s\n' \
      "$main_exit_code" "$package_exit_code" >&2
  fi
  exit "$main_exit_code"
}

on_signal() {
  FINAL_STATUS="SEQ16_A20_INTERRUPTED_CANCELLING_OWN_JOBS"
  cancel_known_jobs || true
  exit 143
}

ACTUAL_USER="$(id -un)"
ACTUAL_UID="$(id -u)"
EXPECTED_UID="$(id -u "$EXPECTED_USER")"
if [[ "${USER-}" != "$EXPECTED_USER" || "$ACTUAL_USER" != "$EXPECTED_USER" || "$ACTUAL_UID" != "$EXPECTED_UID" ]]; then
  printf 'fixed-user check failed: env=%s actual=%s uid=%s expected_uid=%s\n' \
    "${USER-UNSET}" "$ACTUAL_USER" "$ACTUAL_UID" "$EXPECTED_UID" >&2
  exit 50
fi

trap on_exit EXIT
trap on_signal INT TERM

test ! -e "$BASE" || {
  echo "isolated A20 base already exists; refusing overwrite or duplicate: $BASE" >&2
  exit 60
}
test ! -e "$EVIDENCE_ARCHIVE" || {
  echo "A20 evidence archive already exists; refusing replacement" >&2
  exit 61
}
for path in "$ARCHIVE" "$OUTER_MANIFEST"; do
  [[ -f "$path" && ! -L "$path" ]] || {
    echo "payload member absent or symbolic: $path" >&2
    exit 62
  }
done
verify_regular_identity "$ARCHIVE" "$ARCHIVE_SHA256" "$ARCHIVE_SIZE" || {
  echo "A20 archive identity differs" >&2
  exit 63
}
verify_regular_identity "$OUTER_MANIFEST" "$OUTER_MANIFEST_SHA256" "$OUTER_MANIFEST_SIZE" || {
  echo "A20 outer manifest identity differs" >&2
  exit 64
}

mkdir "$BASE"
NAMESPACE_OWNED=1
mkdir "$SOURCE_DIRECTORY" "$TRANSPORT_DIRECTORY" "$STATUS_DIRECTORY" \
  "$LOG_DIRECTORY" "$PRIVATE_EVIDENCE_DIRECTORY"
COPIED_ARCHIVE="${TRANSPORT_DIRECTORY}/${EXPERIMENT_ID}.tar.gz"
COPIED_OUTER_MANIFEST="${TRANSPORT_DIRECTORY}/bundle_manifest.sha256.json"
cp -p -- "$ARCHIVE" "$COPIED_ARCHIVE"
cp -p -- "$OUTER_MANIFEST" "$COPIED_OUTER_MANIFEST"
verify_regular_identity "$COPIED_ARCHIVE" "$ARCHIVE_SHA256" "$ARCHIVE_SIZE" || exit 71
verify_regular_identity "$COPIED_OUTER_MANIFEST" "$OUTER_MANIFEST_SHA256" "$OUTER_MANIFEST_SIZE" || exit 72

python - "$COPIED_ARCHIVE" "$COPIED_OUTER_MANIFEST" "$SOURCE_DIRECTORY" \
  "$INTERNAL_MANIFEST_SHA256" <<'PY'
from hashlib import sha256
import json
import os
from pathlib import Path, PurePosixPath
import sys
import tarfile

archive, outer_path, destination = map(Path, sys.argv[1:4])
internal_manifest_sha = sys.argv[4]
root = destination.resolve(strict=True)
if any(root.iterdir()):
    raise SystemExit("safe extraction destination is not empty")
outer = json.loads(outer_path.read_text(encoding="utf-8"))
expected_hash = dict(outer["member_sha256"])
expected_size = {name: int(size) for name, size in outer["member_size"].items()}
if outer.get("member_count") != len(expected_hash) or set(expected_hash) != set(expected_size):
    raise SystemExit("outer manifest member geometry differs")
expected_names = set(expected_hash) | {"bundle_manifest.json"}
with tarfile.open(archive, "r:gz") as bundle:
    members = bundle.getmembers()
    names = [member.name for member in members]
    if names != sorted(names) or len(names) != len(set(names)) or set(names) != expected_names:
        raise SystemExit("archive contains unordered, duplicate, missing, or extra members")
    for member in members:
        relative = PurePosixPath(member.name)
        if (
            not member.isfile()
            or relative.is_absolute()
            or member.name != relative.as_posix()
            or ".." in relative.parts
            or "\\" in member.name
        ):
            raise SystemExit(f"unsafe archive member: {member.name!r}")
        wanted_size = expected_size.get(member.name, member.size)
        wanted_hash = expected_hash.get(member.name, internal_manifest_sha)
        if member.size != wanted_size:
            raise SystemExit(f"archive member size differs: {member.name}")
        target = root.joinpath(*relative.parts)
        target.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
        source = bundle.extractfile(member)
        if source is None:
            raise SystemExit(f"archive member is unreadable: {member.name}")
        descriptor = os.open(
            target,
            os.O_WRONLY | os.O_CREAT | os.O_EXCL | getattr(os, "O_NOFOLLOW", 0),
            0o600,
        )
        digest = sha256()
        byte_count = 0
        try:
            with os.fdopen(descriptor, "wb") as output:
                while True:
                    block = source.read(1024 * 1024)
                    if not block:
                        break
                    output.write(block)
                    digest.update(block)
                    byte_count += len(block)
                output.flush()
                os.fsync(output.fileno())
        finally:
            source.close()
        if byte_count != wanted_size or digest.hexdigest() != wanted_hash:
            raise SystemExit(f"archive member identity differs: {member.name}")
internal = json.loads((root / "bundle_manifest.json").read_text(encoding="utf-8"))
if (
    internal.get("member_count") != outer["member_count"]
    or internal.get("member_sha256") != expected_hash
    or internal.get("member_size") != expected_size
):
    raise SystemExit("inner and outer manifests differ")
PY

python - "$SOURCE_DIRECTORY" "$COPIED_OUTER_MANIFEST" "$EXPERIMENT_ID" \
  "$ARCHIVE_SHA256" "$INTERNAL_MANIFEST_SHA256" "$CONFIG_SHA256" \
  "$VERIFY_RESULT_SHA256" <<'PY'
from hashlib import sha256
import json
from pathlib import Path
import sys

source = Path(sys.argv[1])
outer_path = Path(sys.argv[2])
experiment_id, archive_sha, internal_sha, config_sha, verifier_sha = sys.argv[3:8]

def digest(path):
    return sha256(path.read_bytes()).hexdigest()

outer = json.loads(outer_path.read_text(encoding="utf-8"))
internal_path = source / "bundle_manifest.json"
internal = json.loads(internal_path.read_text(encoding="utf-8"))
config_member = "configs/daily_camels_native_kalmannet_masked_nse_smoke_v3.json"
verifier_member = "hpc/daily_camels_native_kalmannet_masked_nse/verify_result.py"
config = json.loads((source / config_member).read_text(encoding="utf-8"))
loss = config.get("loss_contract", {})
if (
    outer.get("schema_version") != "daily_camels_native_kalmannet_masked_nse_hpc_archive_v1"
    or outer.get("experiment_id") != experiment_id
    or outer.get("archive_sha256") != archive_sha
    or outer.get("internal_manifest_sha256") != internal_sha
    or digest(internal_path) != internal_sha
    or outer.get("reserved_data_member_count") != 0
    or internal.get("schema_version") != "daily_camels_native_kalmannet_masked_nse_hpc_bundle_v3"
    or internal.get("experiment_id") != experiment_id
    or internal.get("purpose") != "daily_development_smoke_only"
    or internal.get("member_count") != 25
    or internal.get("input_archive_count") != 2
    or internal.get("reserved_data_member_count") != 0
    or internal.get("member_sha256", {}).get(config_member) != config_sha
    or internal.get("member_sha256", {}).get(verifier_member) != verifier_sha
    or config.get("schema_version") != "daily_camels_native_kalmannet_masked_nse_smoke_v3"
    or config.get("experiment_id") != experiment_id
    or config.get("data", {}).get("cadence") != "daily"
    or loss.get("contract_name") != "daily_camels_physical_masked_nse_equal_basin_lead_v2"
    or loss.get("formula")
       != "mean_equal_complete_basin_lead_events((prediction_physical-target_physical)^2/(basin_training_population_std_original_units+0.1)^2)"
    or loss.get("training_statistics_start_index") != 0
    or loss.get("training_statistics_stop_index_exclusive") != 2557
    or loss.get("population_standard_deviation_ddof") != 0
    or loss.get("loss_epsilon_original_discharge_units") != 0.1
    or loss.get("tukf09_compatibility_diagnostic")
       != "primary_loss/global_training_population_std^2"
    or loss.get("result_cell_evidence")
       != {
           "fields": ["event_count", "physical_mse", "primary_loss"],
           "training_events_per_basin_lead": 45,
           "validation_events_per_basin_lead": 109,
       }
    or config.get("checkpoint_selection", {}).get("metric")
       != "negative_shared_masked_nse_validation_loss"
):
    raise SystemExit("A20 bundle or scientific identity differs")
print(json.dumps({
    "status": "SEQ16_A20_OFFLINE_IDENTITY_PASS",
    "experiment_id": experiment_id,
    "member_count": internal["member_count"],
    "reserved_data_member_count": internal["reserved_data_member_count"],
    "loss_contract": loss["contract_name"],
}, sort_keys=True))
PY

export PYTHONDONTWRITEBYTECODE=1
python -u "${SOURCE_DIRECTORY}/hpc/daily_camels_native_kalmannet_masked_nse/preflight.py" \
  --bundle-root "$SOURCE_DIRECTORY" --offline-bundle-check \
  > "${STATUS_DIRECTORY}/seq16_A20_offline_bundle_check.json"
FINAL_STATUS="SEQ16_A20_OFFLINE_BUNDLE_VERIFIED"

echo '=== SUBMIT READ-ONLY A20 GPU PROBE ==='
PROBE_RAW="$(cd "$SOURCE_DIRECTORY" && sbatch --parsable --mem=0 \
  hpc/daily_camels_native_kalmannet_masked_nse/submit_probe_gpu.slurm)"
PROBE_JOB_ID="${PROBE_RAW%%;*}"
register_job_id "$PROBE_JOB_ID" || {
  echo "invalid A20 probe job id: $PROBE_RAW" >&2
  exit 73
}
ALL_SUBMITTED_JOBS_TERMINAL=0
printf '%s\n' "$PROBE_JOB_ID" > "${STATUS_DIRECTORY}/seq16_A20_probe_job_id.txt"
FINAL_STATUS="SEQ16_A20_PROBE_SUBMITTED"
if ! wait_for_job "$PROBE_JOB_ID"; then
  FINAL_STATUS="SEQ16_A20_PROBE_SOFT_STOP_CANCELLING"
  cancel_known_jobs || true
  exit 74
fi
ALL_SUBMITTED_JOBS_TERMINAL=1
require_completed_zero "$PROBE_JOB_ID" "probe_A20" || {
  FINAL_STATUS="SEQ16_A20_PROBE_HARD_STOP"
  exit 75
}

FINAL_STATUS="SEQ16_A20_PROBE_COMPLETED_AWAITING_VERIFICATION"
if ! python - "$STATUS_DIRECTORY" "$EXPERIMENT_ID" "$PROBE_JOB_ID" "$RUN_DIRECTORY" <<'PY'
import json
from pathlib import Path
import sys

status, experiment_id, job_id, run_directory = Path(sys.argv[1]), *sys.argv[2:5]
report = json.loads((status / f"probe-{job_id}.json").read_text(encoding="utf-8"))
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
        raise SystemExit(f"A20 probe admission mismatch: {key}")
if report.get("run_root") != run_directory:
    raise SystemExit("A20 probe checked a different run directory")
if int(report.get("available_host_memory_bytes") or 0) < 4 * 1024**3:
    raise SystemExit("A20 probe has less than 4 GiB available host memory")
if int(report.get("cuda_free_bytes") or 0) < 1024**3:
    raise SystemExit("A20 probe has less than 1 GiB free graphics memory")
print(json.dumps({
    "status": "SEQ16_A20_PROBE_PASS",
    "job_id": job_id,
    "host": report["hostname"],
    "available_host_memory_bytes": report["available_host_memory_bytes"],
    "cuda_free_bytes": report["cuda_free_bytes"],
}, sort_keys=True))
PY
then
  FINAL_STATUS="SEQ16_A20_PROBE_VERIFICATION_HARD_STOP"
  exit 76
fi
FINAL_STATUS="SEQ16_A20_PROBE_PASS"

echo '=== SUBMIT UNIQUE PHYSICAL-LOSS EVIDENCE-COMPLETE TRAINING SMOKE ==='
TRAIN_RAW="$(cd "$SOURCE_DIRECTORY" && sbatch --parsable --mem=0 \
  hpc/daily_camels_native_kalmannet_masked_nse/submit_smoke_gpu.slurm)"
TRAIN_JOB_ID="${TRAIN_RAW%%;*}"
register_job_id "$TRAIN_JOB_ID" || {
  echo "invalid A20 training job id: $TRAIN_RAW" >&2
  exit 77
}
ALL_SUBMITTED_JOBS_TERMINAL=0
printf '%s\n' "$TRAIN_JOB_ID" > "${STATUS_DIRECTORY}/seq16_A20_train_job_id.txt"
FINAL_STATUS="SEQ16_A20_TRAIN_SUBMITTED"
if ! wait_for_job "$TRAIN_JOB_ID"; then
  FINAL_STATUS="SEQ16_A20_TRAIN_SOFT_STOP_CANCELLING"
  cancel_known_jobs || true
  exit 78
fi
ALL_SUBMITTED_JOBS_TERMINAL=1
sacct -P --units=K -j "$TRAIN_JOB_ID" \
  --format=JobIDRaw,JobName,Partition,AllocCPUS,ReqMem,AllocTRES,State,ExitCode,Elapsed,Start,End,MaxRSS,MaxVMSize,AveRSS \
  > "${STATUS_DIRECTORY}/seq16_A20_train_sacct_resources.txt"
if ! require_completed_zero "$TRAIN_JOB_ID" "train_A20"; then
  FINAL_STATUS="SEQ16_A20_TRAIN_TECHNICAL_OR_SCIENTIFIC_HARD_STOP"
  exit 79
fi

FINAL_STATUS="SEQ16_A20_TRAIN_COMPLETED_AWAITING_RESULT_VERIFICATION"
if ! python -u "${SOURCE_DIRECTORY}/hpc/daily_camels_native_kalmannet_masked_nse/verify_result.py" \
  --run-directory "$RUN_DIRECTORY" \
  --experiment-id "$EXPERIMENT_ID" \
  --configuration-sha256 "$CONFIG_SHA256" \
  --training-job-id "$TRAIN_JOB_ID" \
  --output "${STATUS_DIRECTORY}/seq16_A20_result_verification.json"; then
  FINAL_STATUS="SEQ16_A20_RESULT_VERIFICATION_HARD_STOP"
  exit 80
fi

FINAL_STATUS="SEQ16_A20_RESULT_VERIFIED_AWAITING_RESOURCE_VERIFICATION"
if ! python - "$STATUS_DIRECTORY" "$RUN_DIRECTORY" "$EXPERIMENT_ID" "$TRAIN_JOB_ID" <<'PY'
import json
import math
import os
from pathlib import Path
import re
import sys

status, run = map(Path, sys.argv[1:3])
experiment_id, job_id = sys.argv[3:5]
preflight = json.loads(
    (status / f"train-preflight-{job_id}.json").read_text(encoding="utf-8")
)
summary = json.loads((run / "result_summary.json").read_text(encoding="utf-8"))
if (
    preflight.get("status") != "PREFLIGHT_PASS"
    or preflight.get("experiment_id") != experiment_id
    or preflight.get("cuda_available") is not True
    or preflight.get("cuda_device_count") != 1
    or preflight.get("run_root_absent") is not True
    or int(preflight.get("available_host_memory_bytes") or 0) < 4 * 1024**3
    or int(preflight.get("cuda_free_bytes") or 0) < 1024**3
):
    raise SystemExit("A20 training-node resource admission differs")

history = summary.get("history", [])
host_values = [
    int(row["host_resident_memory_bytes"])
    for row in history
    if row.get("host_resident_memory_bytes") is not None
]
gpu_values = [int(row.get("gpu_peak_memory_bytes") or 0) for row in history]
if not host_values or min(host_values) <= 0:
    raise SystemExit("A20 measured process host-memory peak is absent")
if max(host_values) >= 4 * 1024**3:
    raise SystemExit("A20 process host-memory peak exceeds admission")
if not gpu_values or max(gpu_values) <= 0:
    raise SystemExit("A20 measured graphics-memory peak is absent")
if max(gpu_values) >= int(preflight["cuda_free_bytes"]):
    raise SystemExit("A20 measured graphics-memory peak exceeds admission")

lines = (status / "seq16_A20_train_sacct_resources.txt").read_text(
    encoding="utf-8"
).splitlines()
if not lines:
    raise SystemExit("A20 accounting resource evidence is absent")
header = lines[0].split("|")
records = [dict(zip(header, line.split("|"))) for line in lines[1:] if line]
main = next((row for row in records if row.get("JobIDRaw") == job_id), None)
if main is None or main.get("State", "").split("+")[0] != "COMPLETED" or main.get("ExitCode") != "0:0":
    raise SystemExit("A20 main accounting record differs")

def memory_kib(value):
    text = str(value or "").strip()
    match = re.fullmatch(r"([0-9]+(?:\.[0-9]+)?)([KMGTP]?)(?:[cn])?", text)
    if match is None:
        return None
    factors = {"": 1, "K": 1, "M": 1024, "G": 1024**2, "T": 1024**3, "P": 1024**4}
    return float(match.group(1)) * factors[match.group(2)]

requested_kib = memory_kib(main.get("ReqMem"))
rss_values = [memory_kib(row.get("MaxRSS")) for row in records]
rss_values = [value for value in rss_values if value is not None and value > 0]
if requested_kib != 0:
    raise SystemExit("A20 partition-compatible requested-memory record is not 0n")
if not rss_values:
    raise SystemExit("A20 accounting peak memory is absent")
if max(rss_values) * 1024 >= 4 * 1024**3:
    raise SystemExit("A20 accounting peak exceeds admission")
if max(rss_values) * 1024 >= int(preflight["available_host_memory_bytes"]):
    raise SystemExit("A20 accounting peak exceeds training-node admission memory")

verification = {
    "schema_version": "daily_camels_native_knet_resource_verification_v1",
    "status": "VERIFIED",
    "experiment_id": experiment_id,
    "training_job_id": job_id,
    "training_node": preflight.get("hostname"),
    "available_host_memory_bytes_at_admission": int(preflight["available_host_memory_bytes"]),
    "cuda_free_bytes_at_admission": int(preflight["cuda_free_bytes"]),
    "process_host_resident_memory_peak_bytes": (
        max(host_values) if host_values else None
    ),
    "process_gpu_peak_memory_bytes": max(gpu_values),
    "sacct_max_rss_kib": max(rss_values),
    "requested_memory_kib": requested_kib,
}
target = status / "seq16_A20_resource_verification.json"
content = (json.dumps(verification, sort_keys=True, separators=(",", ":")) + "\n").encode()
descriptor = os.open(target, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
try:
    os.write(descriptor, content)
finally:
    os.close(descriptor)
print(json.dumps(verification, sort_keys=True))
PY
then
  FINAL_STATUS="SEQ16_A20_RESOURCE_VERIFICATION_HARD_STOP"
  exit 81
fi

FINAL_STATUS="SEQ16_A20_TECHNICAL_AND_LOSS_IMPROVEMENT_VERIFIED"
echo '=== FINAL A20 ACCOUNTING ==='
sacct --units=K -j "$JOB_IDS_CSV" \
  --format=JobID,JobName,Partition,AllocCPUS,ReqMem,State,ExitCode,Elapsed,Start,End,MaxRSS,MaxVMSize,AveRSS
echo "DAILY_CAMELS_NATIVE_KALMANNET_MASKED_NSE_A20_PASS probe=${PROBE_JOB_ID} train=${TRAIN_JOB_ID}"
