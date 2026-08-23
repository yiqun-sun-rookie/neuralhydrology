#!/usr/bin/env bash
set -eo pipefail

TARGET=/data1/home/sunyiq/kalmannet_tukf19_20260823_retry4
SOURCE_TARGET=/data1/home/sunyiq/kalmannet_tukf19_20260823_retry2
FAILED_RECOVERY_TARGET=/data1/home/sunyiq/kalmannet_tukf19_20260823_retry3
MAILBOX=/data1/home/sunyiq/hpc_mailbox
PAYLOAD_DIR="$MAILBOX/payload/kalmannet-tukf19"
ARCHIVE_NAME=tukf19_hpc_payload_retry4_v1.tar.gz
SOURCE_MANIFEST_NAME=bundle_manifest_retry4.sha256.json
TARGET_MANIFEST_NAME=bundle_manifest.sha256.json
SOURCE_ARCHIVE="$PAYLOAD_DIR/$ARCHIVE_NAME"
SOURCE_MANIFEST="$PAYLOAD_DIR/$SOURCE_MANIFEST_NAME"
EXPECTED_ARCHIVE_SHA=792f29f30ab215e1da2e211597455bc12f936d7cf04174c556ec0c12e1c25450
EXPECTED_ARCHIVE_BYTES=274022
EXPECTED_MANIFEST_SHA=954639d6b3859b4d0a03db22811aefa48040485e29d12cd3fde072bfaebab576
EXPECTED_SOURCE_BUNDLE_SHA=3d1b118be805a95746fb8c7ac999df627675bb18573fb66311f8572395a7f629
EXPECTED_REGISTRY_SHA=5f39f8d71736f04af89ec7ab220966817351ab99541efdbaf0d638a870684974
EXPECTED_VERIFICATION_SHA=d792a58d848f65d9fc226b249234fb3e3ee338e4aaf5a0c91d5cb970961ac3c7
EXPECTED_RESULT_MANIFEST_SHA=a2caf3088f82cc9a54f2a1112d3fbb890c1ed2cc68271386935732e07f8b6f2a
EXPECTED_SMOKE_SHA=da3ff78101afa609b183ae283e2f5db7500f8c52356db32b96191920d72ea4aa
EXPECTED_FAILURE_SHA=e9f973531202cb02789f3285fd76b82efbc29f2a4f9f940db0037404b4c3e5a1
EXPECTED_SOURCE_STDERR_SHA=b396a0bef8ab19203dafa7eddf67a34f30b005d57ae3cc19656aa4f8a8c33cb1
EXPECTED_RETRY3_SUBMISSION_SHA=af07f09972ba6438dd7cc29f3a2165576e388caa883433080073ef1265304898
EXPECTED_RETRY3_FAILURE_SHA=effec19c256e5bcff91bdf969b92fcff11701414f8a0967bbde14b98a4035e49
EXPECTED_RETRY3_STDERR_SHA=236b410d1a8291d86d300c1c9fee812dd84d33e94a6545807ac67293b1e79733
SOURCE_RESULT="$SOURCE_TARGET/results/tukf19_hbv_rolling_origin_formal_execution_v1"
SOURCE_STATUS="$SOURCE_TARGET/artifacts/tukf19_hpc_deployment_retry2_v1/status"
SOURCE_SMOKE="$SOURCE_TARGET/artifacts/tukf19_hpc_deployment_retry2_v1/smoke/smoke_report.json"
RETRY3_STATUS="$FAILED_RECOVERY_TARGET/artifacts/tukf19_hpc_deployment_retry3_v1/status"
STAGING=""

source /data1/home/sunyiq/miniconda3/etc/profile.d/conda.sh
conda activate nh_final
PYTHON=$(command -v python)
test -n "$PYTHON"

echo '=== TUKF19 RETRY4 IMMUTABLE EVIDENCE GATES ==='
SOURCE_ACCOUNTING=$(sacct -j 209845 -X -n -P --format=JobIDRaw,State,ExitCode 2>/dev/null | awk -F'|' '$1 == "209845" {print $2 "|" $3; exit}')
RETRY3_ACCOUNTING=$(sacct -j 209938 -X -n -P --format=JobIDRaw,State,ExitCode 2>/dev/null | awk -F'|' '$1 == "209938" {print $2 "|" $3; exit}')
test "$SOURCE_ACCOUNTING" = "FAILED|1:0"
test "$RETRY3_ACCOUNTING" = "FAILED|1:0"
SOURCE_BUNDLE_SHA=$("$PYTHON" -B - "$SOURCE_TARGET/_transport/bundle_manifest.sha256.json" <<'PY'
import json
from pathlib import Path
import sys
print(json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))["archive_sha256"])
PY
)
test "$SOURCE_BUNDLE_SHA" = "$EXPECTED_SOURCE_BUNDLE_SHA"
test "$(sha256sum "$SOURCE_RESULT/registry.json" | awk '{print $1}')" = "$EXPECTED_REGISTRY_SHA"
test "$(sha256sum "$SOURCE_RESULT/independent_verification.json" | awk '{print $1}')" = "$EXPECTED_VERIFICATION_SHA"
test "$(sha256sum "$SOURCE_RESULT/manifest.json" | awk '{print $1}')" = "$EXPECTED_RESULT_MANIFEST_SHA"
test "$(sha256sum "$SOURCE_SMOKE" | awk '{print $1}')" = "$EXPECTED_SMOKE_SHA"
test "$(sha256sum "$SOURCE_STATUS/formal_failure_209845.json" | awk '{print $1}')" = "$EXPECTED_FAILURE_SHA"
test "$(sha256sum "$SOURCE_TARGET/logs/formal-209845.err" | awk '{print $1}')" = "$EXPECTED_SOURCE_STDERR_SHA"
test "$(sha256sum "$RETRY3_STATUS/postprocessing_recovery_submission.json" | awk '{print $1}')" = "$EXPECTED_RETRY3_SUBMISSION_SHA"
test "$(sha256sum "$RETRY3_STATUS/postprocessing_recovery_failure_209938.json" | awk '{print $1}')" = "$EXPECTED_RETRY3_FAILURE_SHA"
test "$(sha256sum "$FAILED_RECOVERY_TARGET/logs/postprocessing-recovery-209938.err" | awk '{print $1}')" = "$EXPECTED_RETRY3_STDERR_SHA"
test ! -e "$RETRY3_STATUS/postprocessing_recovery_started.json"
test ! -e "$RETRY3_STATUS/postprocessing_recovery_complete.json"
test ! -e "$FAILED_RECOVERY_TARGET/results/tukf19_hbv_rolling_origin_formal_execution_v1"
test ! -e "$FAILED_RECOVERY_TARGET/artifacts/tukf19_hbv_rolling_origin_formal_execution_v1/formal_verified_summary_v1"
test ! -e "$FAILED_RECOVERY_TARGET/artifacts/tukf19_hpc_deployment_retry3_v1/tukf19_hpc_postprocessing_recovery_result_retry3_v1.tar.gz"
echo TUKF19_RETRY4_ALL_PRIOR_EVIDENCE_PINNED

verify_transport() {
  archive=$1
  manifest=$2
  test -f "$archive" -a -f "$manifest"
  test "$(wc -c < "$archive")" = "$EXPECTED_ARCHIVE_BYTES"
  test "$(sha256sum "$archive" | awk '{print $1}')" = "$EXPECTED_ARCHIVE_SHA"
  test "$(sha256sum "$manifest" | awk '{print $1}')" = "$EXPECTED_MANIFEST_SHA"
}

verify_extracted() {
  root=$1
  "$PYTHON" -B - "$root" <<'PY'
import hashlib
import json
from pathlib import Path, PurePosixPath
import sys

root = Path(sys.argv[1]).resolve()
external = json.loads(
    (root / "_transport/bundle_manifest.sha256.json").read_text(encoding="utf-8")
)
payload_path = root / external["payload_manifest_name"]
payload_bytes = payload_path.read_bytes()
assert hashlib.sha256(payload_bytes).hexdigest() == external["payload_manifest_sha256"]
payload = json.loads(payload_bytes.decode("utf-8"))
assert payload["deployment_id"] == external["deployment_id"]
assert payload["members"] == external["members"]
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
print(f"PAYLOAD_MEMBERS_VERIFIED={len(payload['members'])}")
PY
}

cleanup_staging() {
  if [[ -n "$STAGING" && -d "$STAGING" ]]; then
    rm -rf -- "$STAGING"
  fi
}
trap cleanup_staging EXIT

echo '=== TUKF19 RETRY4 DEPLOYMENT ==='
if [[ -e "$TARGET" ]]; then
  test -d "$TARGET"
  verify_transport "$TARGET/_transport/$ARCHIVE_NAME" "$TARGET/_transport/$TARGET_MANIFEST_NAME"
  verify_extracted "$TARGET"
  echo "TUKF19_RETRY4_EXACT_DEPLOYMENT_ALREADY_PRESENT=$TARGET"
else
  STAGING=$(mktemp -d /data1/home/sunyiq/.kalmannet_tukf19_retry4_staging.XXXXXX)
  mkdir -p "$STAGING/_transport"
  cp "$SOURCE_ARCHIVE" "$STAGING/_transport/$ARCHIVE_NAME"
  cp "$SOURCE_MANIFEST" "$STAGING/_transport/$TARGET_MANIFEST_NAME"
  verify_transport "$STAGING/_transport/$ARCHIVE_NAME" "$STAGING/_transport/$TARGET_MANIFEST_NAME"
  tar -xzf "$STAGING/_transport/$ARCHIVE_NAME" -C "$STAGING"
  verify_extracted "$STAGING"
  sed -i 's/\r$//' "$STAGING"/hpc/tukf19_hbv_rolling_origin_formal_execution/*.slurm
  verify_extracted "$STAGING"
  mkdir -p "$STAGING/logs"
  mv "$STAGING" "$TARGET"
  STAGING=""
  echo "TUKF19_RETRY4_DEPLOYED=$TARGET"
fi

STATUS_ROOT="$TARGET/artifacts/tukf19_hpc_deployment_retry4_v1/status"
SUBMISSION="$STATUS_ROOT/postprocessing_recovery_submission.json"
SUBMIT_OUTPUT_FILE="$STATUS_ROOT/postprocessing_recovery_sbatch_output.txt"
mkdir -p "$STATUS_ROOT"

read_job_id() {
  "$PYTHON" -B - "$1" <<'PY'
import json
from pathlib import Path
import sys
print(int(json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))["job_id"]))
PY
}

write_submission() {
  destination=$1
  job_id=$2
  submit_output=$3
  "$PYTHON" -B - "$destination" "$job_id" "$submit_output" "$EXPECTED_ARCHIVE_SHA" <<'PY'
from datetime import datetime, timezone
import json
from pathlib import Path
import sys

path = Path(sys.argv[1])
payload = {
    "schema_version": "tukf19_hpc_postprocessing_recovery_submission_v1",
    "job_kind": "postprocessing_recovery",
    "job_id": int(sys.argv[2]),
    "source_formal_job_id": 209845,
    "failed_recovery_job_id": 209938,
    "submission_output": sys.argv[3],
    "bundle_sha256": sys.argv[4],
    "submitted_at_utc": datetime.now(timezone.utc).isoformat(),
}
with path.open("x", encoding="utf-8", newline="\n") as handle:
    json.dump(payload, handle, indent=2, sort_keys=True)
    handle.write("\n")
PY
}

echo '=== TUKF19 RETRY4 UNIQUE RECOVERY SUBMISSION ==='
if [[ -f "$SUBMISSION" ]]; then
  RECOVERY_JOB_ID=$(read_job_id "$SUBMISSION")
elif [[ -f "$SUBMIT_OUTPUT_FILE" ]]; then
  RECOVERY_JOB_ID=$(awk '/^Submitted batch job [0-9]+$/ {print $4; exit}' "$SUBMIT_OUTPUT_FILE")
  test -n "$RECOVERY_JOB_ID"
  write_submission "$SUBMISSION" "$RECOVERY_JOB_ID" "$(cat "$SUBMIT_OUTPUT_FILE")"
else
  set +e
  SUBMIT_OUTPUT=$(sbatch "$TARGET/hpc/tukf19_hbv_rolling_origin_formal_execution/submit_postprocessing_recovery_cpu_retry4.slurm" 2>&1)
  SUBMIT_RC=$?
  set -e
  printf '%s\n' "$SUBMIT_OUTPUT" | tee "$SUBMIT_OUTPUT_FILE"
  test "$SUBMIT_RC" -eq 0
  RECOVERY_JOB_ID=$(printf '%s\n' "$SUBMIT_OUTPUT" | awk '/^Submitted batch job [0-9]+$/ {print $4; exit}')
  test -n "$RECOVERY_JOB_ID"
  write_submission "$SUBMISSION" "$RECOVERY_JOB_ID" "$SUBMIT_OUTPUT"
fi
echo "TUKF19_RETRY4_RECOVERY_JOB_ID=$RECOVERY_JOB_ID"
squeue -j "$RECOVERY_JOB_ID" -o '%.18i|%.12P|%.30j|%.10T|%.10M|%.10l|%R' 2>&1 || true

echo '=== TUKF19 RETRY4 WAIT ==='
RECOVERY_COMPLETE=0
for attempt in $(seq 1 90); do
  ACCOUNTING=$(sacct -j "$RECOVERY_JOB_ID" -X -n -P --format=JobIDRaw,State,ExitCode 2>/dev/null | awk -F'|' -v id="$RECOVERY_JOB_ID" '$1 == id {print $2 "|" $3; exit}')
  STATE=$(printf '%s' "$ACCOUNTING" | awk -F'|' '{print $1}' | sed 's/+.*$//')
  EXIT_CODE=$(printf '%s' "$ACCOUNTING" | awk -F'|' '{print $2}')
  if [[ "$STATE" = "COMPLETED" && "$EXIT_CODE" = "0:0" ]]; then
    RECOVERY_COMPLETE=1
    break
  fi
  case "$STATE" in
    FAILED|CANCELLED|TIMEOUT|NODE_FAIL|OUT_OF_MEMORY|PREEMPTED|BOOT_FAIL|DEADLINE)
      echo "TUKF19_RETRY4_TERMINAL_FAILURE state=$STATE exit_code=$EXIT_CODE" >&2
      test -f "$TARGET/logs/postprocessing-recovery-${RECOVERY_JOB_ID}.out" && tail -n 160 "$TARGET/logs/postprocessing-recovery-${RECOVERY_JOB_ID}.out" || true
      test -f "$TARGET/logs/postprocessing-recovery-${RECOVERY_JOB_ID}.err" && tail -n 160 "$TARGET/logs/postprocessing-recovery-${RECOVERY_JOB_ID}.err" || true
      exit 174
      ;;
  esac
  if [[ $((attempt % 3)) -eq 0 ]]; then
    echo "TUKF19_RETRY4_WAIT attempt=$attempt state=${STATE:-UNKNOWN} exit_code=${EXIT_CODE:-UNKNOWN}"
  fi
  sleep 10
done
test "$RECOVERY_COMPLETE" -eq 1

COMPLETE_STATUS="$STATUS_ROOT/postprocessing_recovery_complete.json"
FIGURE_MANIFEST="$TARGET/artifacts/tukf19_hbv_rolling_origin_formal_execution_v1/formal_verified_summary_v1/manifest.json"
PACKAGE="$TARGET/artifacts/tukf19_hpc_deployment_retry4_v1/tukf19_hpc_postprocessing_recovery_result_retry4_v1.tar.gz"
PACKAGE_MANIFEST="$PACKAGE.sha256.json"
test -f "$COMPLETE_STATUS" -a -f "$FIGURE_MANIFEST" -a -f "$PACKAGE" -a -f "$PACKAGE_MANIFEST"

echo '=== TUKF19 RETRY4 COMPLETION SUMMARY ==='
"$PYTHON" -B - "$COMPLETE_STATUS" "$FIGURE_MANIFEST" "$PACKAGE" "$PACKAGE_MANIFEST" "$RECOVERY_JOB_ID" <<'PY'
import hashlib
import json
from pathlib import Path
import sys

complete_path, figure_path, archive_path, manifest_path = map(Path, sys.argv[1:5])
complete = json.loads(complete_path.read_text(encoding="utf-8"))
figures = json.loads(figure_path.read_text(encoding="utf-8"))
manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
digest = hashlib.sha256()
with archive_path.open("rb") as stream:
    for chunk in iter(lambda: stream.read(1024 * 1024), b""):
        digest.update(chunk)
checks = {
    "completion_status": complete.get("status") == "HPC_POSTPROCESSING_RECOVERY_VERIFIED",
    "source_formal_job": int(complete.get("source_formal_job_id", -1)) == 209845,
    "recovery_job": str(complete.get("recovery_slurm_job_id")) == str(sys.argv[5]),
    "formal_training_not_rerun": complete.get("formal_training_rerun") is False,
    "independent_verification_not_rerun": complete.get("independent_verification_rerun") is False,
    "source_failure_checks": bool(complete.get("source_failure_checks"))
        and all(complete["source_failure_checks"].values()),
    "source_result_checks": bool(complete.get("source_result_checks"))
        and all(complete["source_result_checks"].values()),
    "copied_file_count": int(complete.get("copied_result_file_count", -1)) == 2003,
    "copied_total_bytes": int(complete.get("copied_result_total_bytes", -1)) == 10785273,
    "display_pair_count": int(complete.get("selected_display_pair", {}).get("pair_count", -1)) == 27,
    "formal_output_validation": bool(complete.get("validation", {}).get("checks"))
        and all(complete["validation"]["checks"].values()),
    "figure_status": figures.get("status") == "VERIFIED_FIGURES_COMPLETE",
    "figure_member_count": len(figures.get("files", {})) == 6,
    "archive_sha256": digest.hexdigest() == manifest.get("archive_sha256"),
    "archive_bytes": archive_path.stat().st_size == int(manifest.get("archive_bytes", -1)),
}
assert all(checks.values()), checks
print(json.dumps({
    "checks": checks,
    "selected_display_pair": complete.get("selected_display_pair"),
    "archive_sha256": manifest.get("archive_sha256"),
    "archive_bytes": manifest.get("archive_bytes"),
    "member_count": manifest.get("member_count"),
}, indent=2, sort_keys=True))
PY

PACKAGE_SHA=$("$PYTHON" -B - "$PACKAGE_MANIFEST" <<'PY'
import json
from pathlib import Path
import sys
print(json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))["archive_sha256"])
PY
)
PACKAGE_BYTES=$("$PYTHON" -B - "$PACKAGE_MANIFEST" <<'PY'
import json
from pathlib import Path
import sys
print(int(json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))["archive_bytes"]))
PY
)
test "$(sha256sum "$PACKAGE" | awk '{print $1}')" = "$PACKAGE_SHA"
test "$(wc -c < "$PACKAGE")" = "$PACKAGE_BYTES"

echo '=== TUKF19 RETRY4 MAILBOX RETRIEVAL ==='
RETRIEVAL_DIR="$MAILBOX/outbox/kalmannet-tukf19/retrieved_retry4"
RETRIEVED_PACKAGE="$RETRIEVAL_DIR/tukf19_hpc_postprocessing_recovery_result_retry4_v1.tar.gz"
RETRIEVED_MANIFEST="$RETRIEVED_PACKAGE.sha256.json"
mkdir -p "$RETRIEVAL_DIR"
if [[ -f "$RETRIEVED_PACKAGE" ]]; then
  test "$(sha256sum "$RETRIEVED_PACKAGE" | awk '{print $1}')" = "$PACKAGE_SHA"
else
  cp "$PACKAGE" "$RETRIEVED_PACKAGE"
  test "$(sha256sum "$RETRIEVED_PACKAGE" | awk '{print $1}')" = "$PACKAGE_SHA"
fi
if [[ -f "$RETRIEVED_MANIFEST" ]]; then
  cmp -s "$PACKAGE_MANIFEST" "$RETRIEVED_MANIFEST"
else
  cp "$PACKAGE_MANIFEST" "$RETRIEVED_MANIFEST"
  cmp -s "$PACKAGE_MANIFEST" "$RETRIEVED_MANIFEST"
fi
echo "TUKF19_RETRY4_RETRIEVED_ARCHIVE_SHA256=$PACKAGE_SHA"
echo "TUKF19_RETRY4_RETRIEVED_ARCHIVE_BYTES=$PACKAGE_BYTES"
sacct -j "$RECOVERY_JOB_ID" -X -n -P --format=JobIDRaw,JobName,Partition,State,ExitCode,Elapsed,Start,End,NodeList,MaxRSS 2>&1 || true
echo TUKF19_RETRY4_POSTPROCESSING_RECOVERY_COMPLETE
exit 0
