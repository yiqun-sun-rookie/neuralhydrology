#!/usr/bin/env bash
set -eo pipefail

SOURCE=/data1/home/sunyiq/kalmannet_tukf20_20260824_verifier_recovery1
SOURCE_FORMAL_JOB=210748
RECOVERY_JOB=211130
FIRST_PACKAGE_JOB=211139
TARGET=/data1/home/sunyiq/kalmannet_tukf20_20260824_verifier_recovery1_portable_package_retry1
SUBMISSION_ROOT=/data1/home/sunyiq/kalmannet_tukf20_20260824_verifier_recovery1_portable_package_retry1_submission
MAILBOX=/data1/home/sunyiq/hpc_mailbox
PAYLOAD_DIR="$MAILBOX/payload/kalmannet-tukf20/portable_package_retry1"
BUNDLE_NAME=tukf20_hpc_portable_package_retry1_payload_v1.tar.gz
BUNDLE="$PAYLOAD_DIR/$BUNDLE_NAME"
BUNDLE_MANIFEST="$PAYLOAD_DIR/bundle_manifest.sha256.json"
EXPECTED_BUNDLE_SHA=7fa9db38fdb72d2f76c625259df33f4c57d09dac48cde95dd6266c2ac28f0a94
EXPECTED_BUNDLE_BYTES=10341
EXPECTED_BUNDLE_MANIFEST_SHA=12f62dbf391032ce5594499b7170fa5916a84d5f19593860f1995e5cb427171c
EXPECTED_FIRST_ARCHIVE_SHA=1ef7e3c2a378e398fddd8ff5bfd968829667466bdd90be712b3a5ca96e91c6be
PACKAGE_ROOT="$TARGET/artifacts/tukf20_hpc_portable_package_retry1_v1"
STATUS="$PACKAGE_ROOT/status"
ARCHIVE="$PACKAGE_ROOT/tukf20_hpc_verifier_recovery_portable_retry1_result_v1.tar.gz"
MANIFEST="$ARCHIVE.sha256.json"
OUTPUTS="$STATUS/packaging_outputs_complete.json"
COMPLETION="$STATUS/packaging_slurm_completion.json"
RETRIEVAL_FINAL="$MAILBOX/outbox/kalmannet-tukf20/retrieved_portable_package_retry1"
DEPLOY_STAGING=""
TARGET_STAGING=""
RETRIEVAL_STAGING=""

source /data1/home/sunyiq/miniconda3/etc/profile.d/conda.sh
conda activate nh_final || { echo '[FATAL] conda activate failed'; exit 1; }
PYTHON=$(command -v python)
test -n "$PYTHON"

cleanup_staging() {
  for path in "$DEPLOY_STAGING" "$TARGET_STAGING" "$RETRIEVAL_STAGING"; do
    if test -n "$path" -a -d "$path"; then
      case "$path" in
        /data1/home/sunyiq/.kalmannet_tukf20_portable_package_retry1.*|\
        "$MAILBOX"/outbox/kalmannet-tukf20/.retrieved_portable_package_retry1.staging.*)
          rm -rf -- "$path"
          ;;
        *)
          echo "refusing unsafe staging cleanup: $path" >&2
          ;;
      esac
    fi
  done
}
trap cleanup_staging EXIT

echo '=== TUKF20 PORTABLE PACKAGE IMMUTABLE GATES ==='
SOURCE_ACCOUNTING=$(sacct -X -n -P -j "$SOURCE_FORMAL_JOB" --format=JobIDRaw,State,ExitCode,Elapsed 2>/dev/null | \
  awk -F'|' -v id="$SOURCE_FORMAL_JOB" '$1 == id {print $2 "|" $3 "|" $4; exit}')
RECOVERY_ACCOUNTING=$(sacct -X -n -P -j "$RECOVERY_JOB" --format=JobIDRaw,State,ExitCode 2>/dev/null | \
  awk -F'|' -v id="$RECOVERY_JOB" '$1 == id {print $2 "|" $3; exit}')
FIRST_PACKAGE_ACCOUNTING=$(sacct -X -n -P -j "$FIRST_PACKAGE_JOB" --format=JobIDRaw,State,ExitCode 2>/dev/null | \
  awk -F'|' -v id="$FIRST_PACKAGE_JOB" '$1 == id {print $2 "|" $3; exit}')
test "$SOURCE_ACCOUNTING" = 'FAILED|1:0|02:19:56'
test "$RECOVERY_ACCOUNTING" = 'COMPLETED|0:0'
test "$FIRST_PACKAGE_ACCOUNTING" = 'COMPLETED|0:0'
test -d "$SOURCE"
test ! -e "$TARGET"
test ! -e "$SUBMISSION_ROOT"
test ! -e "$RETRIEVAL_FINAL"
test "$(sha256sum "$SOURCE/artifacts/tukf20_hpc_verifier_recovery_v1/tukf20_hpc_verifier_recovery_result_v1.tar.gz" | awk '{print $1}')" = \
  "$EXPECTED_FIRST_ARCHIVE_SHA"

"$PYTHON" -B - "$SOURCE" <<'PY'
import json
from pathlib import Path, PurePosixPath
import tarfile
import sys

root = Path(sys.argv[1])
archive = root / "artifacts/tukf20_hpc_verifier_recovery_v1/tukf20_hpc_verifier_recovery_result_v1.tar.gz"
manifest = json.loads(Path(str(archive) + ".sha256.json").read_text(encoding="utf-8"))
unsafe = []
with tarfile.open(archive, "r:gz") as bundle:
    for member in bundle.getmembers():
        pure = PurePosixPath(member.name)
        if any(":" in part for part in pure.parts):
            unsafe.append(member.name)
assert len(unsafe) == 31, len(unsafe)
assert manifest["member_count"] == 2657
assert manifest["archive_sha256"] == "1ef7e3c2a378e398fddd8ff5bfd968829667466bdd90be712b3a5ca96e91c6be"
print(json.dumps({"status": "PORTABILITY_FAULT_RECONFIRMED", "unsafe_member_count": len(unsafe)}, sort_keys=True))
PY

echo '=== TUKF20 PORTABLE PACKAGE DEPLOYMENT BUNDLE GATE ==='
test -f "$BUNDLE" -a -f "$BUNDLE_MANIFEST"
test "$(wc -c < "$BUNDLE")" = "$EXPECTED_BUNDLE_BYTES"
test "$(sha256sum "$BUNDLE" | awk '{print $1}')" = "$EXPECTED_BUNDLE_SHA"
test "$(sha256sum "$BUNDLE_MANIFEST" | awk '{print $1}')" = "$EXPECTED_BUNDLE_MANIFEST_SHA"
mkdir "$SUBMISSION_ROOT"
mkdir "$SUBMISSION_ROOT/logs"
DEPLOY_STAGING=$(mktemp -d /data1/home/sunyiq/.kalmannet_tukf20_portable_package_retry1.deploy.XXXXXX)
mkdir "$DEPLOY_STAGING/_transport"
cp "$BUNDLE" "$DEPLOY_STAGING/_transport/$BUNDLE_NAME"
cp "$BUNDLE_MANIFEST" "$DEPLOY_STAGING/_transport/bundle_manifest.sha256.json"
tar -xzf "$DEPLOY_STAGING/_transport/$BUNDLE_NAME" -C "$DEPLOY_STAGING"
"$PYTHON" -B - "$DEPLOY_STAGING" <<'PY'
import hashlib
import json
from pathlib import Path, PurePosixPath
import sys

root = Path(sys.argv[1]).resolve()
external = json.loads((root / "_transport/bundle_manifest.sha256.json").read_text(encoding="utf-8"))
archive = root / "_transport" / external["archive_name"]
assert archive.stat().st_size == external["archive_bytes"] == 10341
assert hashlib.sha256(archive.read_bytes()).hexdigest() == external["archive_sha256"] == "7fa9db38fdb72d2f76c625259df33f4c57d09dac48cde95dd6266c2ac28f0a94"
payload_path = root / external["payload_manifest_name"]
payload_bytes = payload_path.read_bytes()
assert hashlib.sha256(payload_bytes).hexdigest() == external["payload_manifest_sha256"]
payload = json.loads(payload_bytes.decode("utf-8"))
assert payload["members"] == external["members"]
assert len(payload["members"]) == 5
assert payload["formal_training_rerun_forbidden"] is True
assert payload["independent_verification_rerun_forbidden"] is True
for name, expected in payload["members"].items():
    pure = PurePosixPath(name)
    assert not pure.is_absolute() and ".." not in pure.parts and ":" not in pure.parts[0]
    path = root.joinpath(*pure.parts).resolve()
    path.relative_to(root)
    assert path.is_file()
    assert hashlib.sha256(path.read_bytes()).hexdigest() == expected
print("TUKF20_PORTABLE_PACKAGE_DEPLOYMENT_MEMBERS_VERIFIED=5")
PY
if grep -rU $'\r' "$DEPLOY_STAGING/hpc" >/dev/null; then
  echo 'CRLF detected in portable-package Slurm script' >&2
  exit 91
fi
mv "$DEPLOY_STAGING" "$SUBMISSION_ROOT/deployment"
DEPLOY_STAGING=""
TARGET_STAGING=$(mktemp -d /data1/home/sunyiq/.kalmannet_tukf20_portable_package_retry1.target.XXXXXX)
cp -a "$SUBMISSION_ROOT/deployment/." "$TARGET_STAGING/"
mkdir "$TARGET_STAGING/logs"
mv "$TARGET_STAGING" "$TARGET"
TARGET_STAGING=""

echo '=== TUKF20 UNIQUE PORTABLE PACKAGE SUBMISSION ==='
CLAIM="$SUBMISSION_ROOT/submission_claim.json"
RAW="$SUBMISSION_ROOT/package_submission_raw.txt"
JOB_ID_FILE="$SUBMISSION_ROOT/package_job_id.txt"
RECEIPT="$SUBMISSION_ROOT/package_submission_receipt.json"
SQUEUE_SNAPSHOT="$SUBMISSION_ROOT/package_squeue_snapshot.txt"
SACCT_SNAPSHOT="$SUBMISSION_ROOT/package_sacct_snapshot.txt"
"$PYTHON" -B - "$CLAIM" "$EXPECTED_BUNDLE_SHA" "$EXPECTED_FIRST_ARCHIVE_SHA" <<'PY'
from datetime import datetime, timezone
import json
from pathlib import Path
import sys

destination, deployment_sha, failed_archive_sha = sys.argv[1:]
payload = {
    "schema_version": "tukf20_hpc_portable_package_retry1_claim_v1",
    "recovery_id": "TUKF20_HPC_PORTABLE_PACKAGE_RETRY1_V1",
    "scientific_experiment_id": "TUKF20_HBV_ROLLING_ORIGIN_JOINT_LEARNING_V1",
    "job_kind": "portable_package_verified_existing_results_only",
    "source_formal_job_id": 210748,
    "verifier_recovery_job_id": 211130,
    "first_packaging_job_id": 211139,
    "deployment_bundle_sha256": deployment_sha,
    "failed_portability_archive_sha256": failed_archive_sha,
    "formal_training_rerun": False,
    "independent_verification_rerun": False,
    "plotting_rerun": False,
    "claimed_at_utc": datetime.now(timezone.utc).isoformat(),
}
with Path(destination).open("x", encoding="utf-8", newline="\n") as stream:
    json.dump(payload, stream, indent=2, sort_keys=True)
    stream.write("\n")
PY
set +e
sbatch "$TARGET/hpc/tukf20_hbv_rolling_origin_joint_learning/submit_verifier_recovery_portable_package_retry1_cpu1.slurm" \
  > "$RAW" 2>&1
SUBMIT_RC=$?
set -e
cat "$RAW"
test "$SUBMIT_RC" -eq 0
PACKAGE_JOB=$(awk '/^Submitted batch job [0-9]+$/ {print $4; exit}' "$RAW")
test -n "$PACKAGE_JOB"
printf '%s' "$PACKAGE_JOB" > "$JOB_ID_FILE"
squeue -j "$PACKAGE_JOB" -o '%.18i|%.12P|%.30j|%.10T|%.10M|%.10l|%R' \
  > "$SQUEUE_SNAPSHOT" 2>&1 || true
"$PYTHON" -B - "$RECEIPT" "$PACKAGE_JOB" "$RAW" "$SQUEUE_SNAPSHOT" \
  "$EXPECTED_BUNDLE_SHA" "$EXPECTED_FIRST_ARCHIVE_SHA" <<'PY'
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import sys

destination, job_id, raw_path, queue_path, deployment_sha, failed_archive_sha = sys.argv[1:]
payload = {
    "schema_version": "tukf20_hpc_portable_package_retry1_submission_v1",
    "recovery_id": "TUKF20_HPC_PORTABLE_PACKAGE_RETRY1_V1",
    "scientific_experiment_id": "TUKF20_HBV_ROLLING_ORIGIN_JOINT_LEARNING_V1",
    "job_kind": "portable_package_verified_existing_results_only",
    "source_formal_job_id": 210748,
    "verifier_recovery_job_id": 211130,
    "first_packaging_job_id": 211139,
    "portable_packaging_job_id": int(job_id),
    "raw_output_sha256": hashlib.sha256(Path(raw_path).read_bytes()).hexdigest(),
    "squeue_snapshot_sha256": hashlib.sha256(Path(queue_path).read_bytes()).hexdigest(),
    "deployment_bundle_sha256": deployment_sha,
    "failed_portability_archive_sha256": failed_archive_sha,
    "formal_training_rerun": False,
    "independent_verification_rerun": False,
    "plotting_rerun": False,
    "submitted_at_utc": datetime.now(timezone.utc).isoformat(),
}
with Path(destination).open("x", encoding="utf-8", newline="\n") as stream:
    json.dump(payload, stream, indent=2, sort_keys=True)
    stream.write("\n")
PY
echo "TUKF20_PORTABLE_PACKAGE_JOB_ID=$PACKAGE_JOB"
cat "$SQUEUE_SNAPSHOT"

echo '=== TUKF20 PORTABLE PACKAGE WAIT ==='
PACKAGE_COMPLETE=0
for attempt in $(seq 1 240); do
  ROW=$(sacct -X -n -P -j "$PACKAGE_JOB" --format=JobIDRaw,State,ExitCode 2>/dev/null | \
    awk -F'|' -v id="$PACKAGE_JOB" '$1 == id {print $2 "|" $3; exit}')
  STATE=$(printf '%s' "$ROW" | awk -F'|' '{print $1}' | sed 's/+.*$//')
  EXIT_CODE=$(printf '%s' "$ROW" | awk -F'|' '{print $2}')
  if test "$STATE" = 'COMPLETED' -a "$EXIT_CODE" = '0:0'; then
    PACKAGE_COMPLETE=1
    break
  fi
  case "$STATE" in
    FAILED|CANCELLED|TIMEOUT|NODE_FAIL|OUT_OF_MEMORY|PREEMPTED|BOOT_FAIL|DEADLINE)
      echo "TUKF20_PORTABLE_PACKAGE_TERMINAL_FAILURE state=$STATE exit_code=$EXIT_CODE" >&2
      sacct -X -n -P -j "$PACKAGE_JOB" \
        --format=JobIDRaw,JobName,Partition,AllocCPUS,State,ExitCode,Elapsed,Start,End,NodeList,MaxRSS \
        > "$SACCT_SNAPSHOT" 2>&1 || true
      tail -n 200 "$TARGET/logs/portable-package-${PACKAGE_JOB}.out" 2>/dev/null || true
      tail -n 200 "$TARGET/logs/portable-package-${PACKAGE_JOB}.err" 2>/dev/null || true
      exit 92
      ;;
  esac
  if test $((attempt % 6)) -eq 0; then
    echo "TUKF20_PORTABLE_PACKAGE_WAIT attempt=$attempt state=${STATE:-UNKNOWN} exit_code=${EXIT_CODE:-UNKNOWN}"
  fi
  sleep 10
done
test "$PACKAGE_COMPLETE" -eq 1

echo '=== TUKF20 PORTABLE PACKAGE ACCOUNTING AND VALIDATION ==='
sacct -X -n -P -j "$PACKAGE_JOB" \
  --format=JobIDRaw,JobName,Partition,AllocCPUS,State,ExitCode,Elapsed,Start,End,NodeList,MaxRSS \
  > "$SACCT_SNAPSHOT"
FINAL_ACCOUNTING=$(awk -F'|' -v id="$PACKAGE_JOB" '$1 == id {print $5 "|" $6; exit}' "$SACCT_SNAPSHOT")
test "$FINAL_ACCOUNTING" = 'COMPLETED|0:0'
STDOUT="$TARGET/logs/portable-package-${PACKAGE_JOB}.out"
STDERR="$TARGET/logs/portable-package-${PACKAGE_JOB}.err"
test -f "$STDOUT" -a -f "$STDERR" -a -f "$ARCHIVE" -a -f "$MANIFEST" -a -f "$OUTPUTS"
mkdir "$PACKAGE_ROOT/evidence"
mkdir "$PACKAGE_ROOT/submission"
cp "$SACCT_SNAPSHOT" "$PACKAGE_ROOT/evidence/packaging_sacct_snapshot.txt"
cp "$CLAIM" "$RAW" "$JOB_ID_FILE" "$RECEIPT" "$SQUEUE_SNAPSHOT" "$PACKAGE_ROOT/submission/"

"$PYTHON" -B - "$TARGET" "$PACKAGE_JOB" "$SACCT_SNAPSHOT" "$STDOUT" "$STDERR" \
  "$RECEIPT" "$COMPLETION" <<'PY'
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path, PurePosixPath
import sys
import tarfile

root = Path(sys.argv[1]).resolve()
job_id = int(sys.argv[2])
sacct, stdout, stderr, receipt, destination = map(Path, sys.argv[3:])
package_root = root / "artifacts/tukf20_hpc_portable_package_retry1_v1"
archive = package_root / "tukf20_hpc_verifier_recovery_portable_retry1_result_v1.tar.gz"
manifest_path = Path(str(archive) + ".sha256.json")
outputs_path = package_root / "status/packaging_outputs_complete.json"
manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
outputs = json.loads(outputs_path.read_text(encoding="utf-8"))

def sha(path):
    digest = hashlib.sha256()
    with Path(path).open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()

invalid = set('<>:"\\|?*')
reserved = {"CON", "PRN", "AUX", "NUL"} | {f"COM{i}" for i in range(1, 10)} | {f"LPT{i}" for i in range(1, 10)}
with tarfile.open(archive, "r:gz") as bundle:
    members = bundle.getmembers()
    names = [member.name for member in members]
    assert len(names) == len(set(names)) == len({name.casefold() for name in names})
    assert set(names) == set(manifest["members"]) | {manifest["payload_manifest_name"]}
    for member in members:
        assert member.isfile()
        pure = PurePosixPath(member.name)
        assert not pure.is_absolute() and ".." not in pure.parts and "\\" not in member.name
        for part in pure.parts:
            assert not any(character in invalid for character in part)
            assert not part.endswith((" ", "."))
            assert part.split(".", 1)[0].upper() not in reserved
    for name, expected in manifest["members"].items():
        stream = bundle.extractfile(name)
        assert stream is not None
        digest = hashlib.sha256()
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
        assert digest.hexdigest() == expected
    payload_bytes = bundle.extractfile(manifest["payload_manifest_name"]).read()
    assert hashlib.sha256(payload_bytes).hexdigest() == manifest["payload_manifest_sha256"]
    payload = json.loads(payload_bytes.decode("utf-8"))

checks = {
    "archive_hash": sha(archive) == manifest["archive_sha256"],
    "archive_bytes": archive.stat().st_size == manifest["archive_bytes"],
    "member_count": len(manifest["members"]) == manifest["member_count"],
    "source_file_count": manifest["source_file_count"] == 2668,
    "rewrite_count": manifest["rewrite_count"] == 31 == len(manifest["path_rewrites"]),
    "payload_members": payload["members"] == manifest["members"],
    "payload_rewrites": payload["path_rewrites"] == manifest["path_rewrites"],
    "outputs_status": outputs["status"] == "PORTABLE_PACKAGE_COMPLETE_AWAITING_SLURM_ACCOUNTING",
    "outputs_job": int(outputs["portable_packaging_job_id"]) == job_id,
    "outputs_checks": all(outputs["source_validation_checks"].values()) and all(outputs["archive_validation_checks"].values()),
    "no_training": outputs["formal_training_rerun"] is False,
    "no_verification": outputs["independent_verification_rerun"] is False,
    "no_plotting": outputs["plotting_rerun"] is False,
}
assert all(checks.values()), checks
completion = {
    "schema_version": "tukf20_hpc_portable_package_retry1_slurm_completion_v1",
    "recovery_id": "TUKF20_HPC_PORTABLE_PACKAGE_RETRY1_V1",
    "scientific_experiment_id": "TUKF20_HBV_ROLLING_ORIGIN_JOINT_LEARNING_V1",
    "status": "PORTABLE_PACKAGE_SLURM_COMPLETED",
    "source_formal_job_id": 210748,
    "verifier_recovery_job_id": 211130,
    "first_packaging_job_id": 211139,
    "portable_packaging_job_id": job_id,
    "slurm_state": "COMPLETED",
    "slurm_exit_code": "0:0",
    "validation_checks": checks,
    "archive_sha256": manifest["archive_sha256"],
    "archive_bytes": manifest["archive_bytes"],
    "archive_member_count": manifest["member_count"],
    "rewrite_count": manifest["rewrite_count"],
    "manifest_sha256": sha(manifest_path),
    "outputs_sha256": sha(outputs_path),
    "evidence": {
        "sacct_sha256": sha(sacct),
        "stdout_sha256": sha(stdout),
        "stderr_sha256": sha(stderr),
        "submission_receipt_sha256": sha(receipt),
    },
    "formal_training_rerun": False,
    "independent_verification_rerun": False,
    "plotting_rerun": False,
    "technical_verification_is_not_scientific_success": True,
    "recorded_at_utc": datetime.now(timezone.utc).isoformat(),
}
with destination.open("x", encoding="utf-8", newline="\n") as stream:
    json.dump(completion, stream, indent=2, sort_keys=True)
    stream.write("\n")
print(json.dumps({"checks": checks, "archive_sha256": manifest["archive_sha256"], "archive_bytes": manifest["archive_bytes"], "member_count": manifest["member_count"], "rewrite_count": manifest["rewrite_count"]}, indent=2, sort_keys=True))
PY

echo '=== TUKF20 PORTABLE PACKAGE MAILBOX RETRIEVAL ==='
RETRIEVAL_STAGING=$(mktemp -d "$MAILBOX/outbox/kalmannet-tukf20/.retrieved_portable_package_retry1.staging.XXXXXX")
cp "$ARCHIVE" "$MANIFEST" "$RETRIEVAL_STAGING/"
cp "$OUTPUTS" "$COMPLETION" "$RETRIEVAL_STAGING/"
cp "$STDOUT" "$STDERR" "$RETRIEVAL_STAGING/"
cp "$PACKAGE_ROOT/evidence/packaging_sacct_snapshot.txt" "$RETRIEVAL_STAGING/"
cp "$PACKAGE_ROOT/submission/package_submission_receipt.json" "$RETRIEVAL_STAGING/"
cp "$TARGET/_transport/bundle_manifest.sha256.json" "$RETRIEVAL_STAGING/deployment_bundle_manifest.sha256.json"
cp "$TARGET/configs/tukf20_hpc_portable_package_retry1_v1.json" "$RETRIEVAL_STAGING/"
"$PYTHON" -B - "$RETRIEVAL_STAGING" "$PACKAGE_JOB" <<'PY'
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import sys

root = Path(sys.argv[1])
job_id = int(sys.argv[2])
members = {}
for path in sorted(root.iterdir()):
    if path.is_file():
        members[path.name] = {"sha256": hashlib.sha256(path.read_bytes()).hexdigest(), "bytes": path.stat().st_size}
payload = {
    "schema_version": "tukf20_hpc_portable_package_retry1_mailbox_retrieval_v1",
    "recovery_id": "TUKF20_HPC_PORTABLE_PACKAGE_RETRY1_V1",
    "scientific_experiment_id": "TUKF20_HBV_ROLLING_ORIGIN_JOINT_LEARNING_V1",
    "source_formal_job_id": 210748,
    "verifier_recovery_job_id": 211130,
    "first_packaging_job_id": 211139,
    "portable_packaging_job_id": job_id,
    "members": members,
    "formal_training_rerun": False,
    "independent_verification_rerun": False,
    "plotting_rerun": False,
    "technical_verification_is_not_scientific_success": True,
    "recorded_at_utc": datetime.now(timezone.utc).isoformat(),
}
with (root / "mailbox_retrieval_manifest.json").open("x", encoding="utf-8", newline="\n") as stream:
    json.dump(payload, stream, indent=2, sort_keys=True)
    stream.write("\n")
PY
mv "$RETRIEVAL_STAGING" "$RETRIEVAL_FINAL"
RETRIEVAL_STAGING=""

"$PYTHON" -B - "$COMPLETION" "$RETRIEVAL_FINAL/mailbox_retrieval_manifest.json" <<'PY'
import json
from pathlib import Path
import sys
completion = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
retrieval = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))
print(json.dumps({
    "status": completion["status"],
    "source_formal_job_id": completion["source_formal_job_id"],
    "verifier_recovery_job_id": completion["verifier_recovery_job_id"],
    "first_packaging_job_id": completion["first_packaging_job_id"],
    "portable_packaging_job_id": completion["portable_packaging_job_id"],
    "slurm_state": completion["slurm_state"],
    "slurm_exit_code": completion["slurm_exit_code"],
    "archive_sha256": completion["archive_sha256"],
    "archive_bytes": completion["archive_bytes"],
    "archive_member_count": completion["archive_member_count"],
    "rewrite_count": completion["rewrite_count"],
    "retrieved_file_count": len(retrieval["members"]),
    "formal_training_rerun": False,
    "independent_verification_rerun": False,
    "plotting_rerun": False,
    "technical_verification_is_not_scientific_success": True,
}, indent=2, sort_keys=True))
PY
echo TUKF20_PORTABLE_PACKAGE_AND_RETRIEVAL_COMPLETE
exit 0
