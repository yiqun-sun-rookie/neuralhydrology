#!/usr/bin/env bash
set -eo pipefail

MAILBOX=/data1/home/sunyiq/hpc_mailbox
SOURCE="$MAILBOX/payload/kalmannet-tukf20"
TARGET=/data1/home/sunyiq/kalmannet_tukf20_20260824
ARCHIVE_NAME=tukf20_hpc_payload_v1.tar.gz
MANIFEST_NAME=bundle_manifest.sha256.json
EXPECTED_ARCHIVE_SHA=721fa666319cc448e901515d066bb217560c87ec8edd19e5cbb2300269074f76
EXPECTED_ARCHIVE_BYTES=217695
EXPECTED_MANIFEST_SHA=16bbe1922ddfa57dc34270a10e61fcf84e3135a3dd91d6ab8f7cb9adbdeb1ab8
EXPECTED_CONFIG_SHA=56ea39cad0debfd996f86d221d0de3671c8ecdfbac99e9b9bb96a913c7ec614f
DEPLOYMENT_ID=TUKF20_HBV_ROLLING_ORIGIN_JOINT_LEARNING_HPC_DEPLOYMENT_V1
SCIENTIFIC_ID=TUKF20_HBV_ROLLING_ORIGIN_JOINT_LEARNING_V1
SOURCE_ARCHIVE="$SOURCE/$ARCHIVE_NAME"
SOURCE_MANIFEST="$SOURCE/$MANIFEST_NAME"
STAGING=""

source /data1/home/sunyiq/miniconda3/etc/profile.d/conda.sh
conda activate nh_final
PYTHON=$(command -v python)
test -n "$PYTHON"

preserve_failed_staging() {
  if [[ -n "$STAGING" && -d "$STAGING" ]]; then
    echo "PRESERVED_FAILED_STAGING=$STAGING"
  fi
}
trap preserve_failed_staging EXIT

echo '=== TUKF20 TRANSPORT GATE ==='
test -f "$SOURCE_ARCHIVE" -a -f "$SOURCE_MANIFEST"
test "$(wc -c < "$SOURCE_ARCHIVE")" = "$EXPECTED_ARCHIVE_BYTES"
test "$(sha256sum "$SOURCE_ARCHIVE" | awk '{print $1}')" = "$EXPECTED_ARCHIVE_SHA"
test "$(sha256sum "$SOURCE_MANIFEST" | awk '{print $1}')" = "$EXPECTED_MANIFEST_SHA"

"$PYTHON" -B - "$SOURCE_ARCHIVE" "$SOURCE_MANIFEST" "$EXPECTED_ARCHIVE_SHA" "$EXPECTED_CONFIG_SHA" <<'PY'
import hashlib
import json
from pathlib import Path, PurePosixPath
import sys
import tarfile

archive_path = Path(sys.argv[1])
manifest_path = Path(sys.argv[2])
expected_archive_sha = sys.argv[3]
expected_config_sha = sys.argv[4]
manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
assert manifest["archive_sha256"] == expected_archive_sha
assert manifest["deployment_config_sha256"] == expected_config_sha
assert manifest["member_count"] == len(manifest["members"]) == 48
with tarfile.open(archive_path, "r:gz") as archive:
    members = archive.getmembers()
    names = []
    for member in members:
        pure = PurePosixPath(member.name)
        assert member.isfile()
        assert not pure.is_absolute() and ".." not in pure.parts
        assert member.name == pure.as_posix()
        assert member.name not in names
        names.append(member.name)
    expected = set(manifest["members"]) | {manifest["payload_manifest_name"]}
    assert set(names) == expected
    payload_bytes = archive.extractfile(manifest["payload_manifest_name"]).read()
    assert hashlib.sha256(payload_bytes).hexdigest() == manifest["payload_manifest_sha256"]
    payload = json.loads(payload_bytes.decode("utf-8"))
    assert payload["members"] == manifest["members"]
    for name, expected_hash in manifest["members"].items():
        actual = hashlib.sha256(archive.extractfile(name).read()).hexdigest()
        assert actual == expected_hash, name
print("TUKF20_ARCHIVE_VERIFIED=48")
PY

echo '=== TUKF20 ATOMIC DEPLOYMENT ==='
test ! -e "$TARGET" || { echo TUKF20_TARGET_ALREADY_EXISTS; exit 70; }
STAGING=$(mktemp -d /data1/home/sunyiq/.kalmannet_tukf20_20260824_staging.XXXXXX)
mkdir -p "$STAGING/_transport" "$STAGING/logs"
cp "$SOURCE_ARCHIVE" "$STAGING/_transport/$ARCHIVE_NAME"
cp "$SOURCE_MANIFEST" "$STAGING/_transport/$MANIFEST_NAME"
tar -xzf "$STAGING/_transport/$ARCHIVE_NAME" -C "$STAGING"

"$PYTHON" -B - "$STAGING" "$STAGING/_transport/$MANIFEST_NAME" <<'PY'
import hashlib
import json
from pathlib import Path, PurePosixPath
import sys

root = Path(sys.argv[1]).resolve()
manifest = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))
payload_path = root / manifest["payload_manifest_name"]
payload_bytes = payload_path.read_bytes()
assert hashlib.sha256(payload_bytes).hexdigest() == manifest["payload_manifest_sha256"]
payload = json.loads(payload_bytes.decode("utf-8"))
assert payload["members"] == manifest["members"]
for name, expected_hash in payload["members"].items():
    pure = PurePosixPath(name)
    assert not pure.is_absolute() and ".." not in pure.parts
    path = root.joinpath(*pure.parts).resolve()
    path.relative_to(root)
    assert path.is_file(), name
    assert hashlib.sha256(path.read_bytes()).hexdigest() == expected_hash, name
print(f"TUKF20_EXTRACTED_MEMBERS_VERIFIED={len(payload['members'])}")
PY

test -s "$STAGING/hpc/tukf20_hbv_rolling_origin_joint_learning/submit_smoke_cpu.slurm"
test -s "$STAGING/hpc/tukf20_hbv_rolling_origin_joint_learning/submit_formal_cpu.slurm"
mv "$STAGING" "$TARGET"
STAGING=""
echo "TUKF20_DEPLOYED=$TARGET"

echo '=== TUKF20 UNIQUE SMOKE SUBMISSION ==='
STATUS_ROOT="$TARGET/artifacts/tukf20_hpc_deployment_v1/status"
CLAIM="$STATUS_ROOT/.smoke_submission_claim"
RAW="$STATUS_ROOT/smoke_submission_raw.txt"
RECEIPT="$STATUS_ROOT/smoke_submission_receipt.json"
JOBID_FILE="$STATUS_ROOT/smoke_job_id.txt"
SQUEUE="$STATUS_ROOT/smoke_squeue_snapshot.txt"
SACCT="$STATUS_ROOT/smoke_sacct_snapshot.txt"
SLURM="$TARGET/hpc/tukf20_hbv_rolling_origin_joint_learning/submit_smoke_cpu.slurm"
mkdir -p "$STATUS_ROOT"

for path in "$RAW" "$RECEIPT" "$JOBID_FILE" "$SQUEUE" "$SACCT"; do
  test ! -e "$path" || { echo "TUKF20_SMOKE_EVIDENCE_ALREADY_EXISTS=$path"; exit 71; }
done
EXISTING_QUEUE=$(squeue -u "$USER" -h -o '%i|%j' 2>/dev/null | awk -F'|' '$2 == "tukf20-smoke" {print $1}')
EXISTING_ACCOUNTING=$(sacct -u "$USER" -S 2026-08-24 -X -n -P --format=JobIDRaw,JobName 2>/dev/null | awk -F'|' '$2 == "tukf20-smoke" {print $1}')
test -z "$EXISTING_QUEUE" -a -z "$EXISTING_ACCOUNTING" || {
  echo "TUKF20_SMOKE_PRIOR_SCHEDULER_RECORD queue=$EXISTING_QUEUE accounting=$EXISTING_ACCOUNTING"
  exit 72
}
mkdir "$CLAIM" 2>/dev/null || { echo TUKF20_SMOKE_STAGE_ALREADY_CLAIMED; exit 73; }
printf 'stage=smoke\nclaimed_at_utc=%s\nhost=%s\n' \
  "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$(hostname)" > "$CLAIM/owner.txt"

set +e
(
  set -o noclobber
  sbatch "$SLURM" > "$RAW" 2>&1
)
SUBMIT_RC=$?
set -e
cat "$RAW"
test "$SUBMIT_RC" -eq 0
MATCH_COUNT=$(grep -cE '^Submitted batch job [0-9]+$' "$RAW" || true)
test "$MATCH_COUNT" -eq 1 || { echo TUKF20_SMOKE_SUBMIT_LITERAL_RECORD_INVALID; exit 74; }
JID=$(awk '/^Submitted batch job [0-9]+$/ {print $4}' "$RAW")
test -n "$JID"
(
  set -o noclobber
  printf '%s\n' "$JID" > "$JOBID_FILE"
)
SQUEUE_TMP="$SQUEUE.tmp.$$"
QUEUE_ROW=""
for attempt in $(seq 1 10); do
  QUEUE_ROW=$(squeue --noheader --jobs "$JID" --format='%i|%j|%T|%P|%C' 2>/dev/null || true)
  if printf '%s\n' "$QUEUE_ROW" | awk -F'|' -v id="$JID" '$1 == id {found=1} END {exit !found}'; then
    break
  fi
  QUEUE_ROW=""
  sleep 1
done
test -n "$QUEUE_ROW" || { echo TUKF20_SMOKE_SQUEUE_CONFIRMATION_MISSING; exit 75; }
printf '%s\n' "$QUEUE_ROW" > "$SQUEUE_TMP"
mv "$SQUEUE_TMP" "$SQUEUE"

"$PYTHON" -B - "$RECEIPT" "$RAW" "$SQUEUE" "$JID" "$EXPECTED_ARCHIVE_SHA" "$EXPECTED_CONFIG_SHA" "$DEPLOYMENT_ID" "$SCIENTIFIC_ID" <<'PY'
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import sys

destination, raw_path, queue_path = map(Path, sys.argv[1:4])
payload = {
    "schema_version": "tukf20_hpc_submission_receipt_v1",
    "deployment_id": sys.argv[7],
    "scientific_experiment_id": sys.argv[8],
    "stage": "smoke",
    "job_id": int(sys.argv[4]),
    "raw_output_sha256": hashlib.sha256(raw_path.read_bytes()).hexdigest(),
    "squeue_snapshot_sha256": hashlib.sha256(queue_path.read_bytes()).hexdigest(),
    "bundle_sha256": sys.argv[5],
    "deployment_config_sha256": sys.argv[6],
    "submitted_at_utc": datetime.now(timezone.utc).isoformat(),
}
with destination.open("x", encoding="utf-8", newline="\n") as handle:
    json.dump(payload, handle, indent=2, sort_keys=True)
    handle.write("\n")
PY

echo "TUKF20_SMOKE_JOB_ID=$JID"
cat "$SQUEUE"
sacct -X --jobs "$JID" --format=JobID,JobName,Partition,AllocCPUS,State,ExitCode,Elapsed,Start,End 2>&1 || true
echo TUKF20_SMOKE_SUBMISSION_RECORDED
exit 0
