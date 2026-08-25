#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

EXPECTED_USER="sunyiq"
MAILBOX_ROOT="/data1/home/sunyiq/hpc_mailbox"
OUTBOX_DIRECTORY="${MAILBOX_ROOT}/outbox/kalmannet-daily-camels"

A20_EXPERIMENT_ID="DAILY_CAMELS_NATIVE_KALMANNET_MASKED_NSE_SMOKE_V3_20260825_A20"
A20_BASE="/data1/home/sunyiq/kalmannet_daily_camels_masked_nse_v3_20260825"
A20_SOURCE_DIRECTORY="${A20_BASE}/source_A20_seq16"
A20_RUN_DIRECTORY="${A20_BASE}/${A20_EXPERIMENT_ID}"
A20_STATUS_DIRECTORY="${A20_BASE}/status"
A20_ORIGINAL_VERIFIER="${A20_SOURCE_DIRECTORY}/hpc/daily_camels_native_kalmannet_masked_nse/verify_result.py"
A20_ORIGINAL_VERIFIER_SHA256="d3d7191f091e994b207c10a975ea95b9cb06b8b7206c9b86a565c92f22546c63"
A20_ORIGINAL_VERIFIER_SIZE=42904
A20_CONFIGURATION_SHA256="6c2dd29b92505bd394bce2c18af6a6a429264aecabd6b1b2b7099219b7c240b8"
A20_TRAINING_JOB_ID="211295"
A20_EVIDENCE="${OUTBOX_DIRECTORY}/DAILY_CAMELS_NATIVE_KALMANNET_MASKED_NSE_A20_SEQ16_evidence.tar.gz"
A20_EVIDENCE_SHA256="cce4039ce5ffb2793a0c859e5b2f0e541de0d81cf1a715d4eb362bc97a5e9342"
A20_EVIDENCE_SIZE=6359368

AUDIT_ID="DAILY_CAMELS_NATIVE_KALMANNET_MASKED_NSE_A20_RESULT_AUDIT_V2_20260825_A21"
AUDIT_BASE="/data1/home/sunyiq/kalmannet_daily_camels_masked_nse_a20_result_audit_v2_20260825"
AUDIT_SOURCE_DIRECTORY="${AUDIT_BASE}/source"
AUDIT_STATUS_DIRECTORY="${AUDIT_BASE}/status"
AUDIT_STAGING_DIRECTORY="/data1/home/sunyiq/kalmannet_daily_camels_masked_nse_a20_result_audit_v2_staging_20260825"
CORRECTED_VERIFIER="${AUDIT_SOURCE_DIRECTORY}/verify_result.py"
CORRECTED_VERIFIER_SHA256="f1a8616f13ffcb26bb2ed57e463ed313f987dfae734a73879b582f48326ff18a"
CORRECTED_VERIFIER_SIZE=43746
RESULT_VERIFICATION="${AUDIT_STATUS_DIRECTORY}/result_verification.json"
RESOURCE_VERIFICATION="${AUDIT_STATUS_DIRECTORY}/resource_verification.json"
AUDIT_IDENTITY="${AUDIT_STATUS_DIRECTORY}/audit_identity.json"
EVIDENCE_NAME="DAILY_CAMELS_NATIVE_KALMANNET_MASKED_NSE_A20_AUDIT_A21_SEQ17_evidence.tar.gz"
EVIDENCE_ARCHIVE="${OUTBOX_DIRECTORY}/${EVIDENCE_NAME}"

NAMESPACE_OWNED=0
FINAL_STATUS="SEQ17_A21_STARTED"

sha256_file() {
  sha256sum "$1" | awk '{print $1}'
}

verify_regular_identity() {
  local path="$1" expected_sha="$2" expected_size="$3"
  [[ -f "$path" && ! -L "$path" ]] || return 1
  [[ "$(stat -c '%s' "$path")" = "$expected_size" ]] || return 1
  [[ "$(sha256_file "$path")" = "$expected_sha" ]]
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
    raise SystemExit("audit staging and outbox are on different filesystems")
if os.path.lexists(destination):
    raise SystemExit("audit evidence destination already exists")
os.link(source, destination, follow_symlinks=False)
published = os.stat(destination, follow_symlinks=False)
if (
    published.st_dev != source_record.st_dev
    or published.st_ino != source_record.st_ino
    or published.st_size != source_record.st_size
):
    raise SystemExit("published audit evidence identity differs")
directory_fd = os.open(
    str(destination.parent), os.O_RDONLY | getattr(os, "O_DIRECTORY", 0)
)
try:
    os.fsync(directory_fd)
finally:
    os.close(directory_fd)
PY
}

package_evidence() {
  local command_exit_code="$1" temporary_archive
  if [[ "$NAMESPACE_OWNED" -ne 1 ]]; then
    printf 'evidence_archive=NOT_CREATED namespace_not_owned=1 status=%s exit_code=%s\n' \
      "$FINAL_STATUS" "$command_exit_code"
    return 0
  fi
  printf '%s\n' "$FINAL_STATUS" > "${AUDIT_STATUS_DIRECTORY}/final_status.txt" || return 91
  printf '%s\n' "$command_exit_code" > "${AUDIT_STATUS_DIRECTORY}/command_exit_code.txt" || return 92
  date -u +%Y-%m-%dT%H:%M:%SZ > "${AUDIT_STATUS_DIRECTORY}/finished_time_utc.txt" || return 93
  if find "$AUDIT_BASE" -type l -print -quit | grep -q .; then
    return 94
  fi
  mkdir -p "$OUTBOX_DIRECTORY" || return 95
  temporary_archive="$(mktemp "${AUDIT_STAGING_DIRECTORY}/audit.XXXXXX.tar.gz")" || return 96
  tar -czf "$temporary_archive" -C "$(dirname "$AUDIT_BASE")" "$(basename "$AUDIT_BASE")" || return 97
  [[ -s "$temporary_archive" ]] || return 98
  gzip -t "$temporary_archive" || return 99
  tar -tzf "$temporary_archive" >/dev/null || return 100
  publish_no_replace "$temporary_archive" "$EVIDENCE_ARCHIVE" || return 101
  printf 'evidence_archive=%s\n' "$EVIDENCE_ARCHIVE"
  printf 'evidence_archive_sha256=%s\n' "$(sha256_file "$EVIDENCE_ARCHIVE")"
  printf 'evidence_archive_size=%s\n' "$(stat -c '%s' "$EVIDENCE_ARCHIVE")"
  printf 'evidence_status=%s command_exit_code=%s\n' "$FINAL_STATUS" "$command_exit_code"
  rm -- "$temporary_archive" || return 102
}

on_exit() {
  local main_exit_code="$?" package_exit_code=0
  trap - EXIT INT TERM
  set +e
  package_evidence "$main_exit_code"
  package_exit_code="$?"
  if [[ "$main_exit_code" -eq 0 && "$package_exit_code" -ne 0 ]]; then
    printf 'audit passed but evidence packaging failed: %s\n' "$package_exit_code" >&2
    exit 90
  fi
  if [[ "$main_exit_code" -ne 0 && "$package_exit_code" -ne 0 ]]; then
    printf 'audit failure=%s; additional evidence failure=%s\n' \
      "$main_exit_code" "$package_exit_code" >&2
  fi
  exit "$main_exit_code"
}

ACTUAL_USER="$(id -un)"
ACTUAL_UID="$(id -u)"
EXPECTED_UID="$(id -u "$EXPECTED_USER")"
if [[ "${USER-}" != "$EXPECTED_USER" || "$ACTUAL_USER" != "$EXPECTED_USER" || "$ACTUAL_UID" != "$EXPECTED_UID" ]]; then
  printf 'fixed-user check failed: env=%s actual=%s uid=%s expected_uid=%s\n' \
    "${USER-UNSET}" "$ACTUAL_USER" "$ACTUAL_UID" "$EXPECTED_UID" >&2
  exit 50
fi

test ! -e "$AUDIT_BASE" || {
  echo "isolated A21 audit base already exists; refusing duplicate or overwrite" >&2
  exit 51
}
test ! -e "$AUDIT_STAGING_DIRECTORY" || {
  echo "isolated A21 staging directory already exists; refusing duplicate or overwrite" >&2
  exit 52
}
test ! -e "$EVIDENCE_ARCHIVE" || {
  echo "A21 audit evidence already exists; refusing replacement" >&2
  exit 53
}
verify_regular_identity \
  "$A20_ORIGINAL_VERIFIER" "$A20_ORIGINAL_VERIFIER_SHA256" "$A20_ORIGINAL_VERIFIER_SIZE" || {
  echo "A20 original verifier identity differs" >&2
  exit 54
}
verify_regular_identity "$A20_EVIDENCE" "$A20_EVIDENCE_SHA256" "$A20_EVIDENCE_SIZE" || {
  echo "A20 sequence-16 evidence identity differs" >&2
  exit 55
}
[[ -d "$A20_RUN_DIRECTORY" && ! -L "$A20_RUN_DIRECTORY" ]] || {
  echo "A20 completed run directory is absent or symbolic" >&2
  exit 56
}
if find "$A20_RUN_DIRECTORY" -type l -print -quit | grep -q .; then
  echo "A20 completed run contains symbolic members" >&2
  exit 57
fi

mkdir "$AUDIT_BASE" "$AUDIT_STAGING_DIRECTORY"
mkdir "$AUDIT_SOURCE_DIRECTORY" "$AUDIT_STATUS_DIRECTORY"
NAMESPACE_OWNED=1
trap on_exit EXIT
trap 'FINAL_STATUS="SEQ17_A21_INTERRUPTED"; exit 143' INT TERM
date -u +%Y-%m-%dT%H:%M:%SZ > "${AUDIT_STATUS_DIRECTORY}/started_time_utc.txt"
FINAL_STATUS="SEQ17_A21_NAMESPACE_OWNED"

python - "$A20_ORIGINAL_VERIFIER" "$CORRECTED_VERIFIER" <<'PY'
import os
from pathlib import Path
import sys

source, destination = map(Path, sys.argv[1:3])
text = source.read_text(encoding="utf-8")
old_basin = '''        basin_loss = math.fsum(lead_losses) / len(lead_losses)
        _close(metrics.get("primary_loss"), basin_loss, "validation basin equal-lead mean")
        _close(metrics.get("validation_loss"), basin_loss, "validation basin loss")
        _close(metrics.get("selection_score"), -basin_loss, "validation basin selection", tight=True)
'''
new_basin = '''        basin_loss = math.fsum(lead_losses) / len(lead_losses)
        recorded_basin_loss = _finite(
            metrics.get("primary_loss"), "validation basin primary loss"
        )
        _close(recorded_basin_loss, basin_loss, "validation basin equal-lead mean")
        _close(
            metrics.get("validation_loss"),
            recorded_basin_loss,
            "validation basin loss alias",
            tight=True,
        )
        _close(
            metrics.get("selection_score"),
            -recorded_basin_loss,
            "validation basin selection alias",
            tight=True,
        )
'''
old_shared = '''    shared_loss = math.fsum(basin_losses) / len(basin_losses)
    _close(row.get("primary_loss"), shared_loss, "validation equal-basin mean")
    _close(row.get("validation_loss"), shared_loss, "validation shared loss")
    _close(row.get("selection_score"), -shared_loss, "validation selection score", tight=True)
'''
new_shared = '''    shared_loss = math.fsum(basin_losses) / len(basin_losses)
    recorded_shared_loss = _finite(row.get("primary_loss"), "validation shared primary loss")
    _close(recorded_shared_loss, shared_loss, "validation equal-basin mean")
    _close(
        row.get("validation_loss"),
        recorded_shared_loss,
        "validation shared loss alias",
        tight=True,
    )
    _close(
        row.get("selection_score"),
        -recorded_shared_loss,
        "validation selection score alias",
        tight=True,
    )
'''
old_write = '''    destination.parent.mkdir(parents=True, exist_ok=True)
    _require(not destination.exists(), "verification output already exists")
    content = _canonical_json_bytes(report, newline=True)
'''
new_write = '''    destination.parent.mkdir(parents=True, exist_ok=True)
    content = _canonical_json_bytes(report, newline=True)
    if destination.exists() or destination.is_symlink():
        _require(
            destination.is_file()
            and not destination.is_symlink()
            and destination.stat().st_nlink == 1,
            "existing verification output is not an unlinked regular file",
        )
        _require(
            destination.read_bytes() == content,
            "existing verification output differs",
        )
        return
'''
for old, new, label in (
    (old_basin, new_basin, "basin aggregation"),
    (old_shared, new_shared, "shared aggregation"),
    (old_write, new_write, "idempotent output"),
):
    if text.count(old) != 1:
        raise SystemExit(f"A20 verifier {label} patch anchor differs")
    text = text.replace(old, new)
content = text.encode("utf-8")
descriptor = os.open(
    destination,
    os.O_WRONLY | os.O_CREAT | os.O_EXCL | getattr(os, "O_NOFOLLOW", 0),
    0o600,
)
try:
    os.write(descriptor, content)
    os.fsync(descriptor)
finally:
    os.close(descriptor)
PY
verify_regular_identity \
  "$CORRECTED_VERIFIER" "$CORRECTED_VERIFIER_SHA256" "$CORRECTED_VERIFIER_SIZE" || {
  FINAL_STATUS="SEQ17_A21_CORRECTED_VERIFIER_IDENTITY_HARD_STOP"
  exit 58
}
FINAL_STATUS="SEQ17_A21_CORRECTED_VERIFIER_READY"

if ! python -u "$CORRECTED_VERIFIER" \
  --run-directory "$A20_RUN_DIRECTORY" \
  --experiment-id "$A20_EXPERIMENT_ID" \
  --configuration-sha256 "$A20_CONFIGURATION_SHA256" \
  --training-job-id "$A20_TRAINING_JOB_ID" \
  --output "$RESULT_VERIFICATION"; then
  FINAL_STATUS="SEQ17_A21_RESULT_VERIFICATION_HARD_STOP"
  exit 59
fi
FINAL_STATUS="SEQ17_A21_RESULT_VERIFIED"

if ! python - "$A20_STATUS_DIRECTORY" "$A20_RUN_DIRECTORY" \
  "$A20_EXPERIMENT_ID" "$A20_TRAINING_JOB_ID" "$RESULT_VERIFICATION" \
  "$RESOURCE_VERIFICATION" <<'PY'
import json
import math
import os
from pathlib import Path
import re
import sys

status, run = map(Path, sys.argv[1:3])
experiment_id, job_id = sys.argv[3:5]
result_path, output_path = map(Path, sys.argv[5:7])
preflight = json.loads(
    (status / f"train-preflight-{job_id}.json").read_text(encoding="utf-8")
)
summary = json.loads((run / "result_summary.json").read_text(encoding="utf-8"))
result = json.loads(result_path.read_text(encoding="utf-8"))
ledger = json.loads((run / "access_ledger.json").read_text(encoding="utf-8"))
if (
    result.get("status") != "VERIFIED"
    or result.get("experiment_id") != experiment_id
    or result.get("training_job_id") != job_id
    or result.get("reserved_data_access_zero") is not True
):
    raise SystemExit("A20 corrected result verification differs")
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
for key in (
    "evaluation_array_reads",
    "evaluation_predictions",
    "evaluation_metrics",
    "evaluation_outputs",
):
    if ledger.get(key) != 0:
        raise SystemExit("A20 reserved-data access is nonzero")
history = summary.get("history", [])
host_values = [
    int(row["host_resident_memory_bytes"])
    for row in history
    if row.get("host_resident_memory_bytes") is not None
]
gpu_values = [int(row.get("gpu_peak_memory_bytes") or 0) for row in history]
if not host_values or min(host_values) <= 0 or max(host_values) >= 4 * 1024**3:
    raise SystemExit("A20 measured process host-memory peak differs")
if (
    not gpu_values
    or max(gpu_values) <= 0
    or max(gpu_values) >= int(preflight["cuda_free_bytes"])
):
    raise SystemExit("A20 measured graphics-memory peak differs")
accounting_path = status / "seq16_A20_train_sacct_resources.txt"
lines = accounting_path.read_text(encoding="utf-8").splitlines()
if not lines:
    raise SystemExit("A20 accounting resource evidence is absent")
header = lines[0].split("|")
records = [dict(zip(header, line.split("|"))) for line in lines[1:] if line]
main = next((row for row in records if row.get("JobIDRaw") == job_id), None)
if (
    main is None
    or main.get("JobName") != "daily-knet-a20-smoke"
    or main.get("Partition") != "hgpu2p"
    or main.get("AllocCPUS") != "2"
    or main.get("State", "").split("+")[0] != "COMPLETED"
    or main.get("ExitCode") != "0:0"
):
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
if requested_kib != 0 or not rss_values:
    raise SystemExit("A20 accounting requested or peak memory differs")
sacct_peak_bytes = max(rss_values) * 1024
if (
    sacct_peak_bytes >= 4 * 1024**3
    or sacct_peak_bytes >= int(preflight["available_host_memory_bytes"])
):
    raise SystemExit("A20 accounting peak exceeds admission")
improvement = float(result["post_zero_improvement"])
if not math.isfinite(improvement) or improvement <= 1.0e-6:
    raise SystemExit("A20 post-zero improvement differs")
verification = {
    "schema_version": "daily_camels_native_knet_a20_resource_verification_v2",
    "status": "VERIFIED",
    "experiment_id": experiment_id,
    "training_job_id": job_id,
    "training_node": preflight.get("hostname"),
    "training_elapsed": main.get("Elapsed"),
    "available_host_memory_bytes_at_admission": int(preflight["available_host_memory_bytes"]),
    "cuda_free_bytes_at_admission": int(preflight["cuda_free_bytes"]),
    "process_host_resident_memory_peak_bytes": max(host_values),
    "process_gpu_peak_memory_bytes": max(gpu_values),
    "sacct_max_rss_kib": max(rss_values),
    "sacct_max_rss_bytes": sacct_peak_bytes,
    "requested_memory_kib": requested_kib,
    "reserved_data_access_zero": True,
    "post_zero_improvement": improvement,
}
content = (
    json.dumps(verification, sort_keys=True, separators=(",", ":"), allow_nan=False)
    + "\n"
).encode("utf-8")
descriptor = os.open(
    output_path,
    os.O_WRONLY | os.O_CREAT | os.O_EXCL | getattr(os, "O_NOFOLLOW", 0),
    0o600,
)
try:
    os.write(descriptor, content)
    os.fsync(descriptor)
finally:
    os.close(descriptor)
print(json.dumps(verification, sort_keys=True))
PY
then
  FINAL_STATUS="SEQ17_A21_RESOURCE_VERIFICATION_HARD_STOP"
  exit 60
fi
FINAL_STATUS="SEQ17_A21_RESOURCE_VERIFIED"

python - "$AUDIT_ID" "$A20_EXPERIMENT_ID" "$A20_EVIDENCE" \
  "$A20_EVIDENCE_SHA256" "$A20_EVIDENCE_SIZE" "$A20_ORIGINAL_VERIFIER" \
  "$A20_ORIGINAL_VERIFIER_SHA256" "$CORRECTED_VERIFIER" \
  "$CORRECTED_VERIFIER_SHA256" "$RESULT_VERIFICATION" \
  "$RESOURCE_VERIFICATION" "$AUDIT_IDENTITY" <<'PY'
from hashlib import sha256
import json
import os
from pathlib import Path
import sys

(
    audit_id,
    experiment_id,
    evidence_path,
    evidence_sha256,
    evidence_size,
    original_path,
    original_sha256,
    corrected_path,
    corrected_sha256,
    result_path,
    resource_path,
    output_path,
) = sys.argv[1:13]

def digest(path):
    result = sha256()
    with Path(path).open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            result.update(block)
    return result.hexdigest()

identity = {
    "schema_version": "daily_camels_native_knet_a20_result_audit_identity_v2",
    "audit_id": audit_id,
    "status": "VERIFIED",
    "source_experiment_id": experiment_id,
    "source_evidence": {
        "path": evidence_path,
        "sha256": evidence_sha256,
        "size_bytes": int(evidence_size),
    },
    "original_verifier": {
        "path": original_path,
        "sha256": original_sha256,
    },
    "corrected_verifier": {
        "path": corrected_path,
        "sha256": corrected_sha256,
    },
    "result_verification_sha256": digest(result_path),
    "resource_verification_sha256": digest(resource_path),
}
if (
    digest(evidence_path) != evidence_sha256
    or Path(evidence_path).stat().st_size != int(evidence_size)
    or digest(original_path) != original_sha256
    or digest(corrected_path) != corrected_sha256
):
    raise SystemExit("A21 audit identity source chain differs")
content = (
    json.dumps(identity, sort_keys=True, separators=(",", ":"), allow_nan=False)
    + "\n"
).encode("utf-8")
descriptor = os.open(
    output_path,
    os.O_WRONLY | os.O_CREAT | os.O_EXCL | getattr(os, "O_NOFOLLOW", 0),
    0o600,
)
try:
    os.write(descriptor, content)
    os.fsync(descriptor)
finally:
    os.close(descriptor)
print(json.dumps(identity, sort_keys=True))
PY

FINAL_STATUS="SEQ17_A21_A20_RESULT_AND_RESOURCES_VERIFIED"
echo "DAILY_CAMELS_NATIVE_KALMANNET_A20_AUDIT_A21_PASS training_job=${A20_TRAINING_JOB_ID}"
