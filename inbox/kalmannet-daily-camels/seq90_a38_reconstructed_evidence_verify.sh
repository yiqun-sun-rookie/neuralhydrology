#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

EXPECTED_USER="sunyiq"
MAILBOX_ROOT="/data1/home/sunyiq/hpc_mailbox"
RESULT82="${MAILBOX_ROOT}/outbox/kalmannet-daily-camels/result_82.txt"
RESULT89="${MAILBOX_ROOT}/outbox/kalmannet-daily-camels/result_89.txt"
SOURCE_RUN_BASE="/data1/home/sunyiq/kalmannet_daily_camels_knet_a38_a800_train1_20260828"
RECONSTRUCTION_ROOT="/data1/home/sunyiq/kalmannet_daily_camels_knet_a38_terminal_evidence_reconstruct_seq89_20260831"
RECONSTRUCTED_ARCHIVE="${RECONSTRUCTION_ROOT}/DAILY_CAMELS_KNET_A38_JOB215801_TERMINAL_EVIDENCE_RECONSTRUCT_SEQ89.tar.gz"
ORIGINAL_ARCHIVE="${MAILBOX_ROOT}/outbox/kalmannet-daily-camels/DAILY_CAMELS_KNET_A38_JOB215801_TERMINAL_EVIDENCE_SEQ82.tar.gz"
VERIFICATION_ROOT="/data1/home/sunyiq/kalmannet_daily_camels_knet_a38_terminal_evidence_verify_seq90_20260831"
VERIFICATION_RECEIPT="${VERIFICATION_ROOT}/member_identity_verification.json"

RESULT82_SHA256="a16bfb72c526ff8ec15bb5940b80d4abe8aabe96ffda6bdd322ea604a4229e69"
RESULT82_SIZE="7403339"
RESULT89_SHA256="4a04920a7da01b44c61c0f486e4cb6e1760698f93e7d1fa2f845c84083b88045"
RESULT89_SIZE="7403341"
ORIGINAL_ARCHIVE_SHA256="72feda409ea3490ccd9a289b1313c9beb276c1cc267a15111dc19e63d5815317"
RECONSTRUCTED_ARCHIVE_SHA256="89975d9d69d477d625ae11713a96edf618cb6189284e280f3008bfe0f785676d"
ARCHIVE_SIZE="13900887"

sha256_file() {
  sha256sum "$1" | awk '{print $1}'
}

require_regular_identity() {
  local path="$1" expected_sha256="$2" expected_size="$3" label="$4"
  [[ -f "$path" && ! -L "$path" ]] || {
    echo "${label} is absent, non-regular, or symbolic: ${path}" >&2
    return 50
  }
  [[ "$(stat -c '%s' "$path")" == "$expected_size" ]] || {
    echo "${label} size differs" >&2
    return 51
  }
  [[ "$(sha256_file "$path")" == "$expected_sha256" ]] || {
    echo "${label} SHA-256 differs" >&2
    return 52
  }
}

[[ "$(id -un)" == "$EXPECTED_USER" ]] || { echo "sequence 90 must run as ${EXPECTED_USER}" >&2; exit 53; }
require_regular_identity "$RESULT82" "$RESULT82_SHA256" "$RESULT82_SIZE" "sequence 82 terminal receipt"
require_regular_identity "$RESULT89" "$RESULT89_SHA256" "$RESULT89_SIZE" "sequence 89 reconstruction result"
require_regular_identity "$RECONSTRUCTED_ARCHIVE" "$RECONSTRUCTED_ARCHIVE_SHA256" "$ARCHIVE_SIZE" "sequence 89 reconstructed archive"
[[ ! -e "$ORIGINAL_ARCHIVE" && ! -L "$ORIGINAL_ARCHIVE" ]] || {
  echo "original sequence 82 mailbox archive unexpectedly reappeared" >&2
  exit 53
}
grep -Fq "archive_sha256=${ORIGINAL_ARCHIVE_SHA256} archive_size=${ARCHIVE_SIZE} archive_member_count=33 archive_reserved_member_count=0" "$RESULT82" || {
  echo "sequence 82 original archive identity differs" >&2
  exit 54
}
grep -Fq "archive_sha256=${RECONSTRUCTED_ARCHIVE_SHA256} archive_size=${ARCHIVE_SIZE} archive_member_count=33 archive_reserved_member_count=0" "$RESULT89" || {
  echo "sequence 89 reconstructed archive identity differs" >&2
  exit 54
}
grep -Fxq 'reconstructed archive does not reproduce the registered sequence 82 bytes exactly' "$RESULT89" || {
  echo "sequence 89 did not stop at the registered container-byte mismatch" >&2
  exit 54
}
grep -Fxq '### exit_code=60' "$RESULT89" || { echo "sequence 89 exit code differs" >&2; exit 54; }
if grep -Fq 'SEQ89_A38_EVIDENCE_RECONSTRUCTION_COMPLETE ' "$RESULT89"; then
  echo "sequence 89 unexpectedly claimed byte-identical completion" >&2
  exit 54
fi
[[ ! -e "$VERIFICATION_ROOT" && ! -L "$VERIFICATION_ROOT" ]] || {
  echo "sequence 90 verification root already exists" >&2
  exit 55
}
mkdir -m 700 -- "$VERIFICATION_ROOT"

python -S - "$RESULT82" "$RECONSTRUCTED_ARCHIVE" "$SOURCE_RUN_BASE" "$VERIFICATION_RECEIPT" "$RESULT82_SHA256" "$RESULT89_SHA256" "$ORIGINAL_ARCHIVE_SHA256" "$RECONSTRUCTED_ARCHIVE_SHA256" <<'PY'
from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import sys
import tarfile

result82_path = Path(sys.argv[1])
archive_path = Path(sys.argv[2])
source_run_base = sys.argv[3].rstrip("/")
receipt_path = Path(sys.argv[4])
result82_sha256 = sys.argv[5]
result89_sha256 = sys.argv[6]
original_archive_sha256 = sys.argv[7]
reconstructed_archive_sha256 = sys.argv[8]

experiment_id = (
    "DAILY_CAMELS_KNET_FIXED_FULL_TRAINING_COVERAGE_"
    "EPOCH40_TO80_RESUME_STEP_MONOTONICITY_DIAGNOSTIC_V1_20260828_A38"
)
execution_id = "DAILY_CAMELS_KNET_FIXED_FULL_TRAINING_COVERAGE_A38_A800_TRAIN1_SEQ70"
expected_members = [
    "logs/train1-215801.out",
    "logs/train1-215801.err",
    f"status/train-preflight-{experiment_id}-215801.json",
    f"status/train-gpu-resources-{experiment_id}-215801.csv",
    f"status/train-cgroup-resources-{experiment_id}-215801.txt",
    "status/seq70_offline_train_bundle_verification.json",
    "status/seq70_a800_train_submission_identity.txt",
    "status/seq70_a800_training_job_id.txt",
    "status/seq70_a800_training_submitted_time_utc.txt",
    "status/seq70_pre_submission_squeue.txt",
    "status/seq70_post_submission_squeue.txt",
    "status/seq70_pre_submission_sacct.txt",
    "status/seq70_post_submission_sacct.txt",
    "status/seq70_pre_submission_ngu202_hgpu8.txt",
    f"status/locks/{execution_id}.submission.lock/owner.txt",
    f"runs/{experiment_id}/completion.marker.json",
    f"runs/{experiment_id}/epoch_history.json",
    f"runs/{experiment_id}/events.jsonl",
    f"runs/{experiment_id}/experiment_identity.json",
    f"runs/{experiment_id}/feature_diagnostics.json",
    f"runs/{experiment_id}/manifest.sha256.json",
    f"runs/{experiment_id}/owner_evidence.json",
    f"runs/{experiment_id}/preflight.json",
    f"runs/{experiment_id}/replay_evidence.json",
    f"runs/{experiment_id}/result_summary.json",
    f"runs/{experiment_id}/checkpoints/epoch_040.pt",
    f"runs/{experiment_id}/checkpoints/epoch_080.pt",
    f"runs/{experiment_id}/checkpoints/best.pt",
    f"runs/{experiment_id}/checkpoints/last.pt",
    f"runs/{experiment_id}/checkpoints/epoch_075.pt",
    f"runs/{experiment_id}/predictions/epoch_080.npz",
    f"runs/{experiment_id}/predictions/epoch_075.npz",
    f"runs/{experiment_id}/replay_predictions.npz",
]
if len(expected_members) != 33 or len(set(expected_members)) != 33:
    raise SystemExit("registered archive member list is malformed")

inventory: dict[str, tuple[int, str]] = {}
expected_skipped = {"status/cache", "status/tmp"}
seen_skipped: set[str] = set()
inside = False
begin_count = 0
end_count = 0
for line in result82_path.read_text(encoding="utf-8").splitlines():
    if line == "SEQ82_A38_FILE_INVENTORY_BEGIN":
        if inside:
            raise SystemExit("duplicate result82 inventory begin marker")
        inside = True
        begin_count += 1
        continue
    if line == "SEQ82_A38_FILE_INVENTORY_END":
        if not inside:
            raise SystemExit("result82 inventory end precedes begin")
        inside = False
        end_count += 1
        continue
    if not inside or not line.startswith(source_run_base + "/"):
        continue
    skipped_suffix = "|RUNTIME_CACHE_DIRECTORY_SKIPPED"
    if line.endswith(skipped_suffix):
        absolute = line[: -len(skipped_suffix)]
        relative = absolute[len(source_run_base) + 1 :]
        if relative not in expected_skipped or relative in seen_skipped:
            raise SystemExit(f"unexpected or duplicate result82 skipped directory: {relative}")
        seen_skipped.add(relative)
        continue
    match = re.fullmatch(
        rf"({re.escape(source_run_base)}/[^|]+)\|size=([0-9]+)\|sha256=([0-9a-f]{{64}})",
        line,
    )
    if match is None:
        raise SystemExit(f"malformed result82 inventory line: {line}")
    absolute, size_text, digest = match.groups()
    size = int(size_text)
    relative = absolute[len(source_run_base) + 1 :]
    if relative in inventory:
        raise SystemExit(f"duplicate result82 inventory member: {relative}")
    inventory[relative] = (size, digest)
if inside:
    raise SystemExit("unterminated result82 inventory")
if begin_count != 1 or end_count != 1 or seen_skipped != expected_skipped:
    raise SystemExit("result82 inventory markers or skipped-directory set differ")

reserved = re.compile(r"held.?out|reserved.?evaluation|formal.?evaluation", re.I)
rows: list[dict[str, object]] = []
with tarfile.open(archive_path, mode="r:gz") as archive:
    members = archive.getmembers()
    actual_names = [member.name for member in members]
    if actual_names != expected_members:
        raise SystemExit("reconstructed archive member order or inventory differs")
    for member in members:
        pure = PurePosixPath(member.name)
        if (
            pure.is_absolute()
            or ".." in pure.parts
            or reserved.search(member.name)
            or not member.isfile()
            or member.issym()
            or member.islnk()
        ):
            raise SystemExit(f"unsafe reconstructed archive member: {member.name}")
        expected = inventory.get(member.name)
        if expected is None:
            raise SystemExit(f"member is absent from original result82 inventory: {member.name}")
        extracted = archive.extractfile(member)
        if extracted is None:
            raise SystemExit(f"cannot stream reconstructed archive member: {member.name}")
        digest = hashlib.sha256()
        size = 0
        while True:
            chunk = extracted.read(1024 * 1024)
            if not chunk:
                break
            size += len(chunk)
            digest.update(chunk)
        actual_digest = digest.hexdigest()
        if (size, actual_digest) != expected or member.size != size:
            raise SystemExit(f"member content differs from original result82 inventory: {member.name}")
        rows.append({"name": member.name, "sha256": actual_digest, "size": size})

canonical_bytes = json.dumps(rows, sort_keys=True, separators=(",", ":")).encode("utf-8")
report = {
    "schema_version": "a38_terminal_evidence_member_identity_verification_v1",
    "source_job_id": 215801,
    "source_experiment_id": experiment_id,
    "source_execution_id": execution_id,
    "source_result82_sha256": result82_sha256,
    "source_result89_sha256": result89_sha256,
    "original_archive_sha256": original_archive_sha256,
    "reconstructed_archive_path": archive_path.as_posix(),
    "reconstructed_archive_sha256": reconstructed_archive_sha256,
    "archive_size_bytes": archive_path.stat().st_size,
    "archive_member_count": len(rows),
    "archive_reserved_member_count": 0,
    "canonical_member_inventory_sha256": hashlib.sha256(canonical_bytes).hexdigest(),
    "member_content_identity_verified": True,
    "container_byte_identity_reproduced": False,
    "original_archive_missing": True,
    "evaluation_array_reads": 0,
    "formal_evaluation_outputs_created": 0,
}
pending = receipt_path.with_name(".member_identity_verification.pending")
if receipt_path.exists() or receipt_path.is_symlink() or pending.exists() or pending.is_symlink():
    raise SystemExit("verification receipt destination already exists")
with pending.open("x", encoding="utf-8", newline="\n") as handle:
    json.dump(report, handle, sort_keys=True, separators=(",", ":"))
    handle.write("\n")
    handle.flush()
    os.fsync(handle.fileno())
os.replace(pending, receipt_path)
print("SEQ90_A38_MEMBER_IDENTITY " + json.dumps(report, sort_keys=True, separators=(",", ":")))
PY

[[ -f "$VERIFICATION_RECEIPT" && ! -L "$VERIFICATION_RECEIPT" ]] || {
  echo "sequence 90 verification receipt is absent or unsafe" >&2
  exit 56
}
RECEIPT_SHA256="$(sha256_file "$VERIFICATION_RECEIPT")"
RECEIPT_SIZE="$(stat -c '%s' "$VERIFICATION_RECEIPT")"
printf 'SEQ90_A38_MEMBER_IDENTITY_COMPLETE reconstructed_archive_sha256=%s reconstructed_archive_size=%s member_count=33 reserved_member_count=0 receipt=%s receipt_sha256=%s receipt_size=%s member_content_identity_verified=true container_byte_identity_reproduced=false evaluation_array_reads=0 formal_evaluation_outputs_created=0\n' \
  "$RECONSTRUCTED_ARCHIVE_SHA256" "$ARCHIVE_SIZE" "$VERIFICATION_RECEIPT" "$RECEIPT_SHA256" "$RECEIPT_SIZE"
