#!/usr/bin/env bash
set -eo pipefail

SOURCE=/data1/home/sunyiq/kalmannet_tukf20_20260824
TARGET=/data1/home/sunyiq/kalmannet_tukf20_20260824_verifier_recovery1
SUBMISSION_ROOT=/data1/home/sunyiq/kalmannet_tukf20_20260824_verifier_recovery1_submission
MAILBOX=/data1/home/sunyiq/hpc_mailbox
PAYLOAD="$MAILBOX/payload/kalmannet-tukf20/recovery1"
ARCHIVE="$PAYLOAD/tukf20_hpc_verifier_recovery_payload_v1.tar.gz"
MANIFEST="$PAYLOAD/bundle_manifest.sha256.json"
EXPECTED_ARCHIVE_SHA=129e2adb82fa7bade28ca8ab4809eaf9c515964cf6e7f396e24639091a3f54e1
EXPECTED_ARCHIVE_BYTES=22319
EXPECTED_MANIFEST_SHA=ebf7bcdb3d8c7a63ce92e4f3eff0e54d773b6cd147916160379e2b732745d4af
SOURCE_RESULT="$SOURCE/results/tukf20_hbv_rolling_origin_joint_learning_v1"
SOURCE_STATUS="$SOURCE/artifacts/tukf20_hpc_deployment_v1/status"
SOURCE_JOB=210748
PYTHON=/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python
STAGING=""

echo '=== TUKF20 RECOVERY IMMUTABLE SOURCE GATES ==='
ACCOUNTING=$(sacct -X -n -P -j "$SOURCE_JOB" --format=JobIDRaw,State,ExitCode,Elapsed 2>/dev/null | \
  awk -F'|' -v id="$SOURCE_JOB" '$1 == id {print $2 "|" $3 "|" $4; exit}')
test "$ACCOUNTING" = 'FAILED|1:0|02:19:56'
test "$(sha256sum "$SOURCE/_transport/bundle_manifest.sha256.json" | awk '{print $1}')" = \
  16bbe1922ddfa57dc34270a10e61fcf84e3135a3dd91d6ab8f7cb9adbdeb1ab8
test "$(sha256sum "$SOURCE/configs/tukf20_hbv_rolling_origin_joint_learning_v1.json" | awk '{print $1}')" = \
  76be9c7b0efadfa24bf42ec54b8fe089a156f9a92da841349257feda693bf056
test "$(sha256sum "$SOURCE/scripts/verify_tukf20_hbv_rolling_origin_joint_learning.py" | awk '{print $1}')" = \
  a0b3aa14ccaf1e5fb998bd04cb8ec2dba474f5acb618f3f3281cfaac7d9475eb
test "$(sha256sum "$SOURCE_RESULT/registry.json" | awk '{print $1}')" = \
  f7dc3514371d86f0cb83c5a5c4908ff7c1d13f4343d2af015a0ac362436c295c
test "$(sha256sum "$SOURCE_RESULT/manifest.json" | awk '{print $1}')" = \
  457138aec772a9552bb521386f111b86e0af76c17ee36f6aeba5653f642cbdf3
test "$(sha256sum "$SOURCE_RESULT/independent_verification.json" | awk '{print $1}')" = \
  081120fcc7f93f327ea9db16c7577250e22cc9188e0b2ec829aad84e39477494
test "$(sha256sum "$SOURCE/logs/formal-210748.out" | awk '{print $1}')" = \
  d2722e0aaa77bbe9cf203f9ecbd307aca752975088c3f787b81303dbcaca788f
test "$(sha256sum "$SOURCE/logs/formal-210748.err" | awk '{print $1}')" = \
  b514115eac4bdd001d5bfbeaa9955225f624f6fd7c9b7aef76ceed65d9a9359e
test "$(sha256sum "$SOURCE_STATUS/formal_pipeline_started.json" | awk '{print $1}')" = \
  371ceea8ed8fcc767f4b90f0ec09709ecbc8de55f8ee3aaad2aa1cfd790295a5
test ! -e "$SOURCE_STATUS/formal_pipeline_complete.json"
test ! -e "$SOURCE_STATUS/formal_completion.json"
SOURCE_COUNTS=$(find "$SOURCE_RESULT" -type f -printf '%s\n' | \
  awk '{n+=1; b+=$1} END {printf "%d|%.0f", n, b}')
test "$SOURCE_COUNTS" = '2543|16646985'
test ! -e "$TARGET"
test ! -e "$SUBMISSION_ROOT"
echo 'TUKF20_RECOVERY_SOURCE_EVIDENCE_PINNED'

echo '=== TUKF20 RECOVERY BUNDLE GATE ==='
test -f "$ARCHIVE" -a -f "$MANIFEST"
test "$(wc -c < "$ARCHIVE")" = "$EXPECTED_ARCHIVE_BYTES"
test "$(sha256sum "$ARCHIVE" | awk '{print $1}')" = "$EXPECTED_ARCHIVE_SHA"
test "$(sha256sum "$MANIFEST" | awk '{print $1}')" = "$EXPECTED_MANIFEST_SHA"

mkdir "$SUBMISSION_ROOT"
mkdir "$SUBMISSION_ROOT/.verifier_recovery_submission_claim"
mkdir "$SUBMISSION_ROOT/logs"
STAGING=$(mktemp -d /data1/home/sunyiq/.kalmannet_tukf20_verifier_recovery_upload.XXXXXX)
mkdir "$STAGING/_transport"
cp "$ARCHIVE" "$STAGING/_transport/tukf20_hpc_verifier_recovery_payload_v1.tar.gz"
cp "$MANIFEST" "$STAGING/_transport/bundle_manifest.sha256.json"
tar -xzf "$STAGING/_transport/tukf20_hpc_verifier_recovery_payload_v1.tar.gz" -C "$STAGING"
"$PYTHON" -B - "$STAGING" <<'PY'
import hashlib
import json
from pathlib import Path, PurePosixPath
import sys

root = Path(sys.argv[1]).resolve()
external_path = root / "_transport/bundle_manifest.sha256.json"
external = json.loads(external_path.read_text(encoding="utf-8"))
archive = root / "_transport" / external["archive_name"]
assert archive.stat().st_size == int(external["archive_bytes"])
assert hashlib.sha256(archive.read_bytes()).hexdigest() == external["archive_sha256"]
payload_path = root / external["payload_manifest_name"]
payload_bytes = payload_path.read_bytes()
assert hashlib.sha256(payload_bytes).hexdigest() == external["payload_manifest_sha256"]
payload = json.loads(payload_bytes.decode("utf-8"))
assert payload["members"] == external["members"]
assert payload["formal_training_rerun_forbidden"] is True
for name, expected in payload["members"].items():
    pure = PurePosixPath(name)
    assert not pure.is_absolute() and ".." not in pure.parts
    path = root.joinpath(*pure.parts).resolve()
    path.relative_to(root)
    assert path.is_file(), name
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    assert digest.hexdigest() == expected, name
print(f"TUKF20_RECOVERY_BUNDLE_MEMBERS_VERIFIED={len(payload['members'])}")
PY
if grep -rU $'\r' "$STAGING/hpc" >/dev/null; then
  echo 'CRLF detected in recovery Slurm scripts' >&2
  exit 91
fi
mv "$STAGING" "$SUBMISSION_ROOT/deployment"
STAGING=""

echo '=== TUKF20 UNIQUE VERIFIER RECOVERY SUBMISSION ==='
RAW="$SUBMISSION_ROOT/recovery_submission_raw.txt"
JOB_ID_FILE="$SUBMISSION_ROOT/recovery_job_id.txt"
RECEIPT="$SUBMISSION_ROOT/recovery_submission_receipt.json"
SQUEUE_SNAPSHOT="$SUBMISSION_ROOT/recovery_squeue_snapshot.txt"
set +e
sbatch "$SUBMISSION_ROOT/deployment/hpc/tukf20_hbv_rolling_origin_joint_learning/submit_verifier_recovery_cpu1.slurm" \
  > "$RAW" 2>&1
SUBMIT_RC=$?
set -e
cat "$RAW"
test "$SUBMIT_RC" -eq 0
RECOVERY_JOB=$(awk '/^Submitted batch job [0-9]+$/ {print $4; exit}' "$RAW")
test -n "$RECOVERY_JOB"
printf '%s' "$RECOVERY_JOB" > "$JOB_ID_FILE"
squeue -j "$RECOVERY_JOB" -o '%.18i|%.12P|%.30j|%.10T|%.10M|%.10l|%R' \
  > "$SQUEUE_SNAPSHOT" 2>&1 || true
"$PYTHON" -B - "$RECEIPT" "$RECOVERY_JOB" "$RAW" "$SQUEUE_SNAPSHOT" \
  "$EXPECTED_ARCHIVE_SHA" "$EXPECTED_MANIFEST_SHA" <<'PY'
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import sys

destination, job_id, raw_path, queue_path, bundle_sha, manifest_sha = sys.argv[1:]
raw = Path(raw_path).read_bytes()
queue = Path(queue_path).read_bytes()
payload = {
    "schema_version": "tukf20_hpc_verifier_recovery_submission_v1",
    "recovery_id": "TUKF20_HPC_VERIFIER_RECOVERY_V1",
    "scientific_experiment_id": "TUKF20_HBV_ROLLING_ORIGIN_JOINT_LEARNING_V1",
    "job_kind": "verifier_only_recovery",
    "source_formal_job_id": 210748,
    "recovery_job_id": int(job_id),
    "raw_output_sha256": hashlib.sha256(raw).hexdigest(),
    "squeue_snapshot_sha256": hashlib.sha256(queue).hexdigest(),
    "recovery_bundle_sha256": bundle_sha,
    "recovery_bundle_manifest_sha256": manifest_sha,
    "formal_training_rerun": False,
    "submitted_at_utc": datetime.now(timezone.utc).isoformat(),
}
with Path(destination).open("x", encoding="utf-8", newline="\n") as stream:
    json.dump(payload, stream, indent=2, sort_keys=True)
    stream.write("\n")
PY
echo "TUKF20_VERIFIER_RECOVERY_JOB_ID=$RECOVERY_JOB"
cat "$SQUEUE_SNAPSHOT"

echo '=== TUKF20 VERIFIER RECOVERY WAIT ==='
RECOVERY_COMPLETE=0
for attempt in $(seq 1 360); do
  ROW=$(sacct -X -n -P -j "$RECOVERY_JOB" --format=JobIDRaw,State,ExitCode 2>/dev/null | \
    awk -F'|' -v id="$RECOVERY_JOB" '$1 == id {print $2 "|" $3; exit}')
  STATE=$(printf '%s' "$ROW" | awk -F'|' '{print $1}' | sed 's/+.*$//')
  EXIT_CODE=$(printf '%s' "$ROW" | awk -F'|' '{print $2}')
  if test "$STATE" = 'COMPLETED' -a "$EXIT_CODE" = '0:0'; then
    RECOVERY_COMPLETE=1
    break
  fi
  case "$STATE" in
    FAILED|CANCELLED|TIMEOUT|NODE_FAIL|OUT_OF_MEMORY|PREEMPTED|BOOT_FAIL|DEADLINE)
      echo "TUKF20_VERIFIER_RECOVERY_TERMINAL_FAILURE state=$STATE exit_code=$EXIT_CODE" >&2
      tail -n 200 "$SUBMISSION_ROOT/logs/verifier-recovery-${RECOVERY_JOB}.out" 2>/dev/null || true
      tail -n 200 "$SUBMISSION_ROOT/logs/verifier-recovery-${RECOVERY_JOB}.err" 2>/dev/null || true
      exit 92
      ;;
  esac
  if test $((attempt % 6)) -eq 0; then
    echo "TUKF20_VERIFIER_RECOVERY_WAIT attempt=$attempt state=${STATE:-UNKNOWN} exit_code=${EXIT_CODE:-UNKNOWN}"
  fi
  sleep 10
done
test "$RECOVERY_COMPLETE" -eq 1

echo '=== TUKF20 VERIFIER RECOVERY ACCOUNTING AND COMPLETION ==='
SACCT="$SUBMISSION_ROOT/recovery_sacct_snapshot.txt"
sacct -X -n -P -j "$RECOVERY_JOB" \
  --format=JobIDRaw,JobName,Partition,AllocCPUS,State,ExitCode,Elapsed,Start,End,NodeList,MaxRSS \
  > "$SACCT"
OUT_EXTERNAL="$SUBMISSION_ROOT/logs/verifier-recovery-${RECOVERY_JOB}.out"
ERR_EXTERNAL="$SUBMISSION_ROOT/logs/verifier-recovery-${RECOVERY_JOB}.err"
test -f "$OUT_EXTERNAL" -a -f "$ERR_EXTERNAL"
test -d "$TARGET"
OUTPUTS="$TARGET/artifacts/tukf20_hpc_verifier_recovery_v1/status/verifier_recovery_outputs_complete.json"
COMPLETION="$TARGET/artifacts/tukf20_hpc_verifier_recovery_v1/status/verifier_recovery_slurm_completion.json"
test -f "$OUTPUTS"
test ! -e "$COMPLETION"
OUT_TARGET="$TARGET/logs/verifier-recovery-${RECOVERY_JOB}.out"
ERR_TARGET="$TARGET/logs/verifier-recovery-${RECOVERY_JOB}.err"
SACCT_TARGET="$TARGET/artifacts/tukf20_hpc_verifier_recovery_v1/evidence/verifier_recovery_sacct_snapshot.txt"
test ! -e "$OUT_TARGET" -a ! -e "$ERR_TARGET" -a ! -e "$SACCT_TARGET"
cp "$OUT_EXTERNAL" "$OUT_TARGET"
cp "$ERR_EXTERNAL" "$ERR_TARGET"
cp "$SACCT" "$SACCT_TARGET"
SUBMISSION_TARGET="$TARGET/artifacts/tukf20_hpc_verifier_recovery_v1/submission"
test ! -e "$SUBMISSION_TARGET"
mkdir "$SUBMISSION_TARGET"
cp "$RAW" "$JOB_ID_FILE" "$RECEIPT" "$SQUEUE_SNAPSHOT" "$SUBMISSION_TARGET/"
"$PYTHON" -B - "$COMPLETION" "$OUTPUTS" "$SACCT_TARGET" "$OUT_TARGET" "$ERR_TARGET" \
  "$RECOVERY_JOB" <<'PY'
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import sys

destination, outputs_path, sacct_path, stdout_path, stderr_path, job_id = sys.argv[1:]
paths = [Path(value) for value in (outputs_path, sacct_path, stdout_path, stderr_path)]
outputs, sacct, stdout, stderr = paths
report = json.loads(outputs.read_text(encoding="utf-8"))
assert report["status"] == "VERIFIER_RECOVERY_OUTPUTS_VERIFIED_AWAITING_SLURM_ACCOUNTING"
assert str(report["recovery_slurm_job_id"]) == str(job_id)
payload = {
    "schema_version": "tukf20_hpc_verifier_recovery_slurm_completion_v1",
    "recovery_id": "TUKF20_HPC_VERIFIER_RECOVERY_V1",
    "scientific_experiment_id": "TUKF20_HBV_ROLLING_ORIGIN_JOINT_LEARNING_V1",
    "status": "VERIFIER_RECOVERY_SLURM_COMPLETED",
    "source_formal_job_id": 210748,
    "recovery_slurm_job_id": int(job_id),
    "slurm_state": "COMPLETED",
    "slurm_exit_code": "0:0",
    "outputs_complete_sha256": hashlib.sha256(outputs.read_bytes()).hexdigest(),
    "evidence": {
        "sacct_path": sacct.relative_to(outputs.parents[3]).as_posix(),
        "sacct_sha256": hashlib.sha256(sacct.read_bytes()).hexdigest(),
        "stdout_path": stdout.relative_to(outputs.parents[3]).as_posix(),
        "stdout_sha256": hashlib.sha256(stdout.read_bytes()).hexdigest(),
        "stderr_path": stderr.relative_to(outputs.parents[3]).as_posix(),
        "stderr_sha256": hashlib.sha256(stderr.read_bytes()).hexdigest(),
    },
    "formal_training_rerun": False,
    "technical_verification_is_not_scientific_success": True,
    "recorded_at_utc": datetime.now(timezone.utc).isoformat(),
}
with Path(destination).open("x", encoding="utf-8", newline="\n") as stream:
    json.dump(payload, stream, indent=2, sort_keys=True)
    stream.write("\n")
PY

"$PYTHON" -B - "$TARGET" "$OUTPUTS" "$COMPLETION" <<'PY'
import json
from pathlib import Path
import sys

root, outputs_path, completion_path = map(Path, sys.argv[1:])
verification = json.loads((root / "results/tukf20_hbv_rolling_origin_joint_learning_v1/independent_verification.json").read_text(encoding="utf-8"))
figures = json.loads((root / "artifacts/tukf20_hbv_rolling_origin_joint_learning_v1/formal_verified_summary_v1/manifest.json").read_text(encoding="utf-8"))
outputs = json.loads(outputs_path.read_text(encoding="utf-8"))
completion = json.loads(completion_path.read_text(encoding="utf-8"))
contrasts = verification["independent_aggregates"]["primary"]["contrasts"]
checks = {
    "verification_status": verification["status"] == "FORMAL_VERIFIED",
    "all_20_checks": len(verification["checks"]) == 20 and all(verification["checks"].values()),
    "readout_count": verification["test_readout_count"] == 108,
    "clean_error_count": verification["primary_clean_error_count"] == 13608,
    "figure_status": figures["status"] == "VERIFIED_FIGURES_COMPLETE",
    "figure_count": len(figures["files"]) == 5,
    "output_validation": all(outputs["validation"]["checks"].values()),
    "recovery_completed": completion["slurm_state"] == "COMPLETED" and completion["slurm_exit_code"] == "0:0",
    "no_training_rerun": outputs["formal_training_rerun"] is False,
}
assert all(checks.values()), checks
print(json.dumps({
    "checks": checks,
    "scientific_classification": verification["scientific_classification"],
    "primary_contrasts": {
        name: {
            "median_ratio": value["median_ratio"],
            "wins_below_one": value["wins_below_one"],
            "benefit_sign_test_one_sided_p": value["benefit_sign_test_one_sided_p"],
            "classification": value["classification"],
        }
        for name, value in contrasts.items()
    },
    "technical_verification_is_not_scientific_success": True,
}, indent=2, sort_keys=True))
PY
echo "TUKF20_VERIFIER_RECOVERY_COMPLETED job_id=$RECOVERY_JOB"
exit 0
