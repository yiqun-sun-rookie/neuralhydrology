#!/usr/bin/env bash
set -eo pipefail

SOURCE=/data1/home/sunyiq/kalmannet_tukf20_20260824
TARGET=/data1/home/sunyiq/kalmannet_tukf20_20260824_verifier_recovery1
RECOVERY_JOB=211130
SOURCE_JOB=210748
MAILBOX=/data1/home/sunyiq/hpc_mailbox
CLAIM=/data1/home/sunyiq/kalmannet_tukf20_20260824_verifier_recovery1_package_submission
STATUS="$TARGET/artifacts/tukf20_hpc_verifier_recovery_v1/status"
EVIDENCE="$TARGET/artifacts/tukf20_hpc_verifier_recovery_v1/evidence"
SUBMISSION="$TARGET/artifacts/tukf20_hpc_verifier_recovery_v1/submission"
RESULT="$TARGET/results/tukf20_hbv_rolling_origin_joint_learning_v1"
FIGURES="$TARGET/artifacts/tukf20_hbv_rolling_origin_joint_learning_v1/formal_verified_summary_v1"
PACKAGE="$TARGET/artifacts/tukf20_hpc_verifier_recovery_v1/tukf20_hpc_verifier_recovery_result_v1.tar.gz"
PACKAGE_MANIFEST="$PACKAGE.sha256.json"
PACKAGE_OUTPUTS="$STATUS/packaging_outputs_complete.json"
PACKAGE_COMPLETION="$STATUS/packaging_slurm_completion.json"
RECOVERY_OUTPUTS="$STATUS/verifier_recovery_outputs_complete.json"
RECOVERY_COMPLETION="$STATUS/verifier_recovery_slurm_completion.json"
PACKAGE_SLURM="$TARGET/recovery_deployment/hpc/tukf20_hbv_rolling_origin_joint_learning/submit_verifier_recovery_package_cpu1.slurm"
EXPECTED_PACKAGE_SLURM_SHA=3c75319c9f9519dc865e46a02a19f64c90ea3d406b4b2e4ff745e397a619975b
EXPECTED_PACKAGE_SCRIPT_SHA=ef047a34ec49ac0777bc5c8ebfb3777585d1394d4dd9c1f061b1196f0175e58d
EXPECTED_RECOVERY_BUNDLE_SHA=129e2adb82fa7bade28ca8ab4809eaf9c515964cf6e7f396e24639091a3f54e1
EXPECTED_FORMAL_BUNDLE_SHA=721fa666319cc448e901515d066bb217560c87ec8edd19e5cbb2300269074f76
RETRIEVAL_FINAL="$MAILBOX/outbox/kalmannet-tukf20/retrieved_verifier_recovery1"
RETRIEVAL_STAGING=""

source /data1/home/sunyiq/miniconda3/etc/profile.d/conda.sh
conda activate nh_final || { echo '[FATAL] conda activate failed'; exit 1; }
PYTHON=$(command -v python)
test -n "$PYTHON"

cleanup_retrieval_staging() {
  if test -n "$RETRIEVAL_STAGING" -a -d "$RETRIEVAL_STAGING"; then
    case "$RETRIEVAL_STAGING" in
      "$MAILBOX"/outbox/kalmannet-tukf20/.retrieved_verifier_recovery1.staging.*)
        rm -rf -- "$RETRIEVAL_STAGING"
        ;;
      *)
        echo "refusing unsafe staging cleanup: $RETRIEVAL_STAGING" >&2
        ;;
    esac
  fi
}
trap cleanup_retrieval_staging EXIT

echo '=== TUKF20 POST-RECOVERY PACKAGE IMMUTABLE GATES ==='
SOURCE_ACCOUNTING=$(sacct -X -n -P -j "$SOURCE_JOB" --format=JobIDRaw,State,ExitCode,Elapsed 2>/dev/null | \
  awk -F'|' -v id="$SOURCE_JOB" '$1 == id {print $2 "|" $3 "|" $4; exit}')
RECOVERY_ACCOUNTING=$(sacct -X -n -P -j "$RECOVERY_JOB" --format=JobIDRaw,State,ExitCode 2>/dev/null | \
  awk -F'|' -v id="$RECOVERY_JOB" '$1 == id {print $2 "|" $3; exit}')
test "$SOURCE_ACCOUNTING" = 'FAILED|1:0|02:19:56'
test "$RECOVERY_ACCOUNTING" = 'COMPLETED|0:0'
test "$(sha256sum "$SOURCE/_transport/bundle_manifest.sha256.json" | awk '{print $1}')" = \
  16bbe1922ddfa57dc34270a10e61fcf84e3135a3dd91d6ab8f7cb9adbdeb1ab8
test "$(sha256sum "$PACKAGE_SLURM" | awk '{print $1}')" = "$EXPECTED_PACKAGE_SLURM_SHA"
test "$(sha256sum "$TARGET/scripts/package_tukf20_hpc_verifier_recovery.py" | awk '{print $1}')" = \
  "$EXPECTED_PACKAGE_SCRIPT_SHA"
test -f "$RECOVERY_OUTPUTS" -a -f "$RECOVERY_COMPLETION"
test -f "$RESULT/independent_verification.json" -a -f "$FIGURES/manifest.json"
test ! -e "$PACKAGE" -a ! -e "$PACKAGE_MANIFEST" -a ! -e "$PACKAGE_OUTPUTS"
test ! -e "$STATUS/packaging_started.json" -a ! -e "$STATUS/packaging_failure.json"
test ! -e "$PACKAGE_COMPLETION" -a ! -e "$RETRIEVAL_FINAL"

"$PYTHON" -B - "$TARGET" "$RECOVERY_JOB" "$EXPECTED_FORMAL_BUNDLE_SHA" \
  "$EXPECTED_RECOVERY_BUNDLE_SHA" <<'PY'
import hashlib
import json
from pathlib import Path
import sys

root = Path(sys.argv[1])
recovery_job = int(sys.argv[2])
formal_bundle_sha = sys.argv[3]
recovery_bundle_sha = sys.argv[4]

def read(relative):
    return json.loads((root / relative).read_text(encoding="utf-8"))

outputs = read("artifacts/tukf20_hpc_verifier_recovery_v1/status/verifier_recovery_outputs_complete.json")
completion = read("artifacts/tukf20_hpc_verifier_recovery_v1/status/verifier_recovery_slurm_completion.json")
verification = read("results/tukf20_hbv_rolling_origin_joint_learning_v1/independent_verification.json")
figures = read("artifacts/tukf20_hbv_rolling_origin_joint_learning_v1/formal_verified_summary_v1/manifest.json")
formal_manifest = read("_transport/bundle_manifest.sha256.json")
recovery_manifest = read("recovery_deployment/_transport/bundle_manifest.sha256.json")
checks = {
    "recovery_outputs_status": outputs.get("status") == "VERIFIER_RECOVERY_OUTPUTS_VERIFIED_AWAITING_SLURM_ACCOUNTING",
    "recovery_job_identity": str(outputs.get("recovery_slurm_job_id")) == str(recovery_job),
    "recovery_no_training": outputs.get("formal_training_rerun") is False,
    "recovery_contract_unchanged": outputs.get("scientific_contract_changed") is False,
    "completion_status": completion.get("status") == "VERIFIER_RECOVERY_SLURM_COMPLETED",
    "completion_accounting": completion.get("slurm_state") == "COMPLETED" and completion.get("slurm_exit_code") == "0:0",
    "completion_job_identity": int(completion.get("recovery_slurm_job_id", -1)) == recovery_job,
    "formal_bundle_identity": formal_manifest.get("archive_sha256") == formal_bundle_sha,
    "recovery_bundle_identity": recovery_manifest.get("archive_sha256") == recovery_bundle_sha,
    "verification_status": verification.get("status") == "FORMAL_VERIFIED",
    "verification_checks": len(verification.get("checks", {})) == 20 and all(verification.get("checks", {}).values()),
    "readout_count": verification.get("test_readout_count") == 108,
    "clean_error_count": verification.get("primary_clean_error_count") == 13608,
    "figure_status": figures.get("status") == "VERIFIED_FIGURES_COMPLETE",
    "figure_count": len(figures.get("files", {})) == 5,
}
assert all(checks.values()), checks
print(json.dumps({"checks": checks, "status": "TUKF20_PACKAGE_GATES_PASSED"}, sort_keys=True))
PY

echo '=== TUKF20 UNIQUE PACKAGE SUBMISSION ==='
RAW="$CLAIM/package_submission_raw.txt"
JOB_ID_FILE="$CLAIM/package_job_id.txt"
RECEIPT="$CLAIM/package_submission_receipt.json"
SQUEUE_SNAPSHOT="$CLAIM/package_squeue_snapshot.txt"
SACCT_SNAPSHOT="$CLAIM/package_sacct_snapshot.txt"

if test -e "$CLAIM"; then
  test -d "$CLAIM"
  test -f "$RAW"
  PACKAGE_JOB=$(awk '/^Submitted batch job [0-9]+$/ {print $4; exit}' "$RAW")
  test -n "$PACKAGE_JOB"
  if test -f "$JOB_ID_FILE"; then
    test "$(cat "$JOB_ID_FILE")" = "$PACKAGE_JOB"
  else
    printf '%s' "$PACKAGE_JOB" > "$JOB_ID_FILE"
  fi
else
  mkdir "$CLAIM"
  "$PYTHON" -B - "$CLAIM/submission_claim.json" "$RECOVERY_JOB" \
    "$EXPECTED_RECOVERY_BUNDLE_SHA" <<'PY'
from datetime import datetime, timezone
import json
from pathlib import Path
import sys

destination, recovery_job, bundle_sha = sys.argv[1:]
payload = {
    "schema_version": "tukf20_hpc_verifier_recovery_package_claim_v1",
    "recovery_id": "TUKF20_HPC_VERIFIER_RECOVERY_V1",
    "scientific_experiment_id": "TUKF20_HBV_ROLLING_ORIGIN_JOINT_LEARNING_V1",
    "job_kind": "package_verified_existing_results_only",
    "source_formal_job_id": 210748,
    "recovery_slurm_job_id": int(recovery_job),
    "recovery_bundle_sha256": bundle_sha,
    "formal_training_rerun": False,
    "independent_verification_rerun": False,
    "claimed_at_utc": datetime.now(timezone.utc).isoformat(),
}
with Path(destination).open("x", encoding="utf-8", newline="\n") as stream:
    json.dump(payload, stream, indent=2, sort_keys=True)
    stream.write("\n")
PY
  set +e
  sbatch "$PACKAGE_SLURM" > "$RAW" 2>&1
  SUBMIT_RC=$?
  set -e
  cat "$RAW"
  test "$SUBMIT_RC" -eq 0
  PACKAGE_JOB=$(awk '/^Submitted batch job [0-9]+$/ {print $4; exit}' "$RAW")
  test -n "$PACKAGE_JOB"
  printf '%s' "$PACKAGE_JOB" > "$JOB_ID_FILE"
fi

squeue -j "$PACKAGE_JOB" -o '%.18i|%.12P|%.30j|%.10T|%.10M|%.10l|%R' \
  > "$SQUEUE_SNAPSHOT" 2>&1 || true

if test ! -e "$RECEIPT"; then
  "$PYTHON" -B - "$RECEIPT" "$PACKAGE_JOB" "$RECOVERY_JOB" "$RAW" \
    "$SQUEUE_SNAPSHOT" "$EXPECTED_PACKAGE_SLURM_SHA" "$EXPECTED_PACKAGE_SCRIPT_SHA" <<'PY'
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import sys

destination, package_job, recovery_job, raw_path, queue_path, slurm_sha, script_sha = sys.argv[1:]
raw = Path(raw_path).read_bytes()
queue = Path(queue_path).read_bytes()
payload = {
    "schema_version": "tukf20_hpc_verifier_recovery_package_submission_v1",
    "recovery_id": "TUKF20_HPC_VERIFIER_RECOVERY_V1",
    "scientific_experiment_id": "TUKF20_HBV_ROLLING_ORIGIN_JOINT_LEARNING_V1",
    "job_kind": "package_verified_existing_results_only",
    "source_formal_job_id": 210748,
    "recovery_slurm_job_id": int(recovery_job),
    "packaging_slurm_job_id": int(package_job),
    "raw_output_sha256": hashlib.sha256(raw).hexdigest(),
    "squeue_snapshot_sha256": hashlib.sha256(queue).hexdigest(),
    "package_slurm_sha256": slurm_sha,
    "package_script_sha256": script_sha,
    "formal_training_rerun": False,
    "independent_verification_rerun": False,
    "submitted_at_utc": datetime.now(timezone.utc).isoformat(),
}
with Path(destination).open("x", encoding="utf-8", newline="\n") as stream:
    json.dump(payload, stream, indent=2, sort_keys=True)
    stream.write("\n")
PY
fi

echo "TUKF20_VERIFIER_RECOVERY_PACKAGE_JOB_ID=$PACKAGE_JOB"
cat "$SQUEUE_SNAPSHOT"

echo '=== TUKF20 PACKAGE WAIT ==='
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
      echo "TUKF20_PACKAGE_TERMINAL_FAILURE state=$STATE exit_code=$EXIT_CODE" >&2
      sacct -X -n -P -j "$PACKAGE_JOB" \
        --format=JobIDRaw,JobName,Partition,AllocCPUS,State,ExitCode,Elapsed,Start,End,NodeList,MaxRSS \
        > "$SACCT_SNAPSHOT" 2>&1 || true
      tail -n 200 "$TARGET/logs/verifier-recovery-package-${PACKAGE_JOB}.out" 2>/dev/null || true
      tail -n 200 "$TARGET/logs/verifier-recovery-package-${PACKAGE_JOB}.err" 2>/dev/null || true
      exit 92
      ;;
  esac
  if test $((attempt % 6)) -eq 0; then
    echo "TUKF20_PACKAGE_WAIT attempt=$attempt state=${STATE:-UNKNOWN} exit_code=${EXIT_CODE:-UNKNOWN}"
  fi
  sleep 10
done
test "$PACKAGE_COMPLETE" -eq 1

echo '=== TUKF20 PACKAGE ACCOUNTING AND COMPLETION ==='
sacct -X -n -P -j "$PACKAGE_JOB" \
  --format=JobIDRaw,JobName,Partition,AllocCPUS,State,ExitCode,Elapsed,Start,End,NodeList,MaxRSS \
  > "$SACCT_SNAPSHOT"
FINAL_ACCOUNTING=$(awk -F'|' -v id="$PACKAGE_JOB" '$1 == id {print $5 "|" $6; exit}' "$SACCT_SNAPSHOT")
test "$FINAL_ACCOUNTING" = 'COMPLETED|0:0'
PACKAGE_STDOUT="$TARGET/logs/verifier-recovery-package-${PACKAGE_JOB}.out"
PACKAGE_STDERR="$TARGET/logs/verifier-recovery-package-${PACKAGE_JOB}.err"
test -f "$PACKAGE_STDOUT" -a -f "$PACKAGE_STDERR"
test -f "$PACKAGE" -a -f "$PACKAGE_MANIFEST" -a -f "$PACKAGE_OUTPUTS"
test ! -e "$PACKAGE_COMPLETION"
test ! -e "$EVIDENCE/packaging_sacct_snapshot.txt"
test ! -e "$SUBMISSION/package_submission_raw.txt"
test ! -e "$SUBMISSION/package_job_id.txt"
test ! -e "$SUBMISSION/package_submission_receipt.json"
test ! -e "$SUBMISSION/package_squeue_snapshot.txt"
cp "$SACCT_SNAPSHOT" "$EVIDENCE/packaging_sacct_snapshot.txt"
cp "$RAW" "$JOB_ID_FILE" "$RECEIPT" "$SQUEUE_SNAPSHOT" "$SUBMISSION/"

"$PYTHON" -B - "$TARGET" "$PACKAGE_JOB" "$RECOVERY_JOB" \
  "$EVIDENCE/packaging_sacct_snapshot.txt" "$PACKAGE_STDOUT" "$PACKAGE_STDERR" \
  "$RECEIPT" "$PACKAGE_COMPLETION" <<'PY'
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path, PurePosixPath
import sys
import tarfile

root = Path(sys.argv[1]).resolve()
package_job = int(sys.argv[2])
recovery_job = int(sys.argv[3])
sacct_path, stdout_path, stderr_path, receipt_path, destination = map(Path, sys.argv[4:])
archive = root / "artifacts/tukf20_hpc_verifier_recovery_v1/tukf20_hpc_verifier_recovery_result_v1.tar.gz"
manifest_path = Path(str(archive) + ".sha256.json")
outputs_path = root / "artifacts/tukf20_hpc_verifier_recovery_v1/status/packaging_outputs_complete.json"
manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
outputs = json.loads(outputs_path.read_text(encoding="utf-8"))

def sha(path):
    digest = hashlib.sha256()
    with Path(path).open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()

with tarfile.open(archive, "r:gz") as bundle:
    files = [item for item in bundle.getmembers() if item.isfile()]
    names = [item.name for item in files]
    expected_names = sorted([*manifest["members"], manifest["payload_manifest_name"]])
    assert sorted(names) == expected_names
    for name in names:
        pure = PurePosixPath(name)
        assert not pure.is_absolute() and ".." not in pure.parts
    for name, expected in manifest["members"].items():
        stream = bundle.extractfile(name)
        assert stream is not None
        digest = hashlib.sha256()
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
        assert digest.hexdigest() == expected, name
    payload_bytes = bundle.extractfile(manifest["payload_manifest_name"]).read()
    assert hashlib.sha256(payload_bytes).hexdigest() == manifest["payload_manifest_sha256"]
    payload = json.loads(payload_bytes.decode("utf-8"))

checks = {
    "archive_hash": sha(archive) == manifest.get("archive_sha256"),
    "archive_bytes": archive.stat().st_size == int(manifest.get("archive_bytes", -1)),
    "archive_member_count": int(manifest.get("member_count", -1)) == len(manifest.get("members", {})),
    "payload_members": payload.get("members") == manifest.get("members"),
    "manifest_identity": manifest.get("scientific_experiment_id") == "TUKF20_HBV_ROLLING_ORIGIN_JOINT_LEARNING_V1",
    "manifest_jobs": int(manifest.get("source_formal_job_id", -1)) == 210748 and int(manifest.get("recovery_slurm_job_id", -1)) == recovery_job and int(manifest.get("packaging_slurm_job_id", -1)) == package_job,
    "outputs_status": outputs.get("status") == "VERIFIER_RECOVERY_PACKAGE_COMPLETE_AWAITING_SLURM_ACCOUNTING",
    "outputs_jobs": int(outputs.get("recovery_slurm_job_id", -1)) == recovery_job and int(outputs.get("packaging_slurm_job_id", -1)) == package_job,
    "outputs_archive": outputs.get("archive", {}).get("sha256") == manifest.get("archive_sha256") and int(outputs.get("archive", {}).get("bytes", -1)) == int(manifest.get("archive_bytes", -2)),
    "formal_validation": bool(outputs.get("formal_output_validation", {}).get("checks")) and all(outputs["formal_output_validation"]["checks"].values()),
    "source_validation": bool(outputs.get("source_validation_checks")) and all(outputs["source_validation_checks"].values()),
    "recovery_completion": bool(outputs.get("recovery_completion_checks")) and all(outputs["recovery_completion_checks"].values()),
    "no_training_rerun": outputs.get("formal_training_rerun") is False and manifest.get("formal_training_rerun") is False and payload.get("formal_training_rerun") is False,
    "no_verifier_rerun": outputs.get("independent_verification_rerun_during_packaging") is False,
}
assert all(checks.values()), checks
completion = {
    "schema_version": "tukf20_hpc_verifier_recovery_package_slurm_completion_v1",
    "recovery_id": "TUKF20_HPC_VERIFIER_RECOVERY_V1",
    "scientific_experiment_id": "TUKF20_HBV_ROLLING_ORIGIN_JOINT_LEARNING_V1",
    "status": "VERIFIER_RECOVERY_PACKAGE_SLURM_COMPLETED",
    "source_formal_job_id": 210748,
    "recovery_slurm_job_id": recovery_job,
    "packaging_slurm_job_id": package_job,
    "slurm_state": "COMPLETED",
    "slurm_exit_code": "0:0",
    "validation_checks": checks,
    "archive_sha256": manifest["archive_sha256"],
    "archive_bytes": manifest["archive_bytes"],
    "archive_member_count": manifest["member_count"],
    "manifest_sha256": sha(manifest_path),
    "packaging_outputs_sha256": sha(outputs_path),
    "evidence": {
        "sacct_sha256": sha(sacct_path),
        "stdout_sha256": sha(stdout_path),
        "stderr_sha256": sha(stderr_path),
        "submission_receipt_sha256": sha(receipt_path),
    },
    "formal_training_rerun": False,
    "independent_verification_rerun_during_packaging": False,
    "technical_verification_is_not_scientific_success": True,
    "recorded_at_utc": datetime.now(timezone.utc).isoformat(),
}
with destination.open("x", encoding="utf-8", newline="\n") as stream:
    json.dump(completion, stream, indent=2, sort_keys=True)
    stream.write("\n")
print(json.dumps({
    "archive_sha256": manifest["archive_sha256"],
    "archive_bytes": manifest["archive_bytes"],
    "archive_member_count": manifest["member_count"],
    "checks": checks,
}, indent=2, sort_keys=True))
PY

echo '=== TUKF20 MAILBOX RESULT RETRIEVAL ==='
RETRIEVAL_STAGING=$(mktemp -d "$MAILBOX/outbox/kalmannet-tukf20/.retrieved_verifier_recovery1.staging.XXXXXX")
cp "$PACKAGE" "$RETRIEVAL_STAGING/"
cp "$PACKAGE_MANIFEST" "$RETRIEVAL_STAGING/"
cp "$PACKAGE_OUTPUTS" "$RETRIEVAL_STAGING/packaging_outputs_complete.json"
cp "$PACKAGE_COMPLETION" "$RETRIEVAL_STAGING/packaging_slurm_completion.json"
cp "$RECOVERY_OUTPUTS" "$RETRIEVAL_STAGING/verifier_recovery_outputs_complete.json"
cp "$RECOVERY_COMPLETION" "$RETRIEVAL_STAGING/verifier_recovery_slurm_completion.json"
cp "$RESULT/independent_verification.json" "$RETRIEVAL_STAGING/independent_verification.json"
cp "$FIGURES/manifest.json" "$RETRIEVAL_STAGING/figure_manifest.json"
cp "$TARGET/logs/verifier-recovery-${RECOVERY_JOB}.out" "$RETRIEVAL_STAGING/"
cp "$TARGET/logs/verifier-recovery-${RECOVERY_JOB}.err" "$RETRIEVAL_STAGING/"
cp "$PACKAGE_STDOUT" "$RETRIEVAL_STAGING/"
cp "$PACKAGE_STDERR" "$RETRIEVAL_STAGING/"
cp "$EVIDENCE/verifier_recovery_sacct_snapshot.txt" "$RETRIEVAL_STAGING/"
cp "$EVIDENCE/packaging_sacct_snapshot.txt" "$RETRIEVAL_STAGING/"
cp "$SUBMISSION/recovery_submission_receipt.json" "$RETRIEVAL_STAGING/"
cp "$SUBMISSION/package_submission_receipt.json" "$RETRIEVAL_STAGING/"

"$PYTHON" -B - "$RETRIEVAL_STAGING" "$PACKAGE_JOB" "$RECOVERY_JOB" <<'PY'
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import sys

root = Path(sys.argv[1])
package_job = int(sys.argv[2])
recovery_job = int(sys.argv[3])
members = {}
for path in sorted(root.iterdir()):
    if not path.is_file():
        continue
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    members[path.name] = {"sha256": digest.hexdigest(), "bytes": path.stat().st_size}
payload = {
    "schema_version": "tukf20_hpc_verifier_recovery_mailbox_retrieval_v1",
    "recovery_id": "TUKF20_HPC_VERIFIER_RECOVERY_V1",
    "scientific_experiment_id": "TUKF20_HBV_ROLLING_ORIGIN_JOINT_LEARNING_V1",
    "source_formal_job_id": 210748,
    "recovery_slurm_job_id": recovery_job,
    "packaging_slurm_job_id": package_job,
    "members": members,
    "formal_training_rerun": False,
    "independent_verification_rerun_during_packaging": False,
    "technical_verification_is_not_scientific_success": True,
    "recorded_at_utc": datetime.now(timezone.utc).isoformat(),
}
destination = root / "mailbox_retrieval_manifest.json"
with destination.open("x", encoding="utf-8", newline="\n") as stream:
    json.dump(payload, stream, indent=2, sort_keys=True)
    stream.write("\n")
PY
mv "$RETRIEVAL_STAGING" "$RETRIEVAL_FINAL"
RETRIEVAL_STAGING=""

"$PYTHON" -B - "$PACKAGE_COMPLETION" "$RETRIEVAL_FINAL/mailbox_retrieval_manifest.json" <<'PY'
import json
from pathlib import Path
import sys

completion = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
retrieval = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))
print(json.dumps({
    "status": completion["status"],
    "source_formal_job_id": completion["source_formal_job_id"],
    "recovery_slurm_job_id": completion["recovery_slurm_job_id"],
    "packaging_slurm_job_id": completion["packaging_slurm_job_id"],
    "slurm_state": completion["slurm_state"],
    "slurm_exit_code": completion["slurm_exit_code"],
    "archive_sha256": completion["archive_sha256"],
    "archive_bytes": completion["archive_bytes"],
    "archive_member_count": completion["archive_member_count"],
    "retrieved_file_count": len(retrieval["members"]),
    "formal_training_rerun": False,
    "independent_verification_rerun_during_packaging": False,
    "technical_verification_is_not_scientific_success": True,
}, indent=2, sort_keys=True))
PY
echo TUKF20_VERIFIER_RECOVERY_PACKAGE_AND_RETRIEVAL_COMPLETE
exit 0
