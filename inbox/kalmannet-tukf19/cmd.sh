#!/usr/bin/env bash
set -o pipefail

TARGET=/data1/home/sunyiq/kalmannet_tukf19_20260823_retry3
SOURCE=/data1/home/sunyiq/kalmannet_tukf19_20260823_retry2
STATUS="$TARGET/artifacts/tukf19_hpc_deployment_retry3_v1/status"
RESULT="$TARGET/results/tukf19_hbv_rolling_origin_formal_execution_v1"
FIGURES="$TARGET/artifacts/tukf19_hbv_rolling_origin_formal_execution_v1/formal_verified_summary_v1"
PACKAGE="$TARGET/artifacts/tukf19_hpc_deployment_retry3_v1/tukf19_hpc_postprocessing_recovery_result_retry3_v1.tar.gz"

echo '=== TUKF19 RETRY3 RECOVERY ACCOUNTING ==='
sacct -j 209938 -X -n -P --format=JobIDRaw,JobName,Partition,State,ExitCode,Elapsed,Start,End,NodeList,MaxRSS 2>&1 || true
squeue -j 209938 -o '%.18i|%.12P|%.30j|%.10T|%.10M|%.10l|%R' 2>&1 || true

echo '=== TUKF19 RETRY3 FAILURE EVIDENCE ==='
for path in \
  "$STATUS/postprocessing_recovery_submission.json" \
  "$STATUS/postprocessing_recovery_sbatch_output.txt" \
  "$STATUS/postprocessing_recovery_started.json" \
  "$STATUS/postprocessing_recovery_complete.json" \
  "$STATUS/postprocessing_recovery_failure_209938.json" \
  "$TARGET/logs/postprocessing-recovery-209938.out" \
  "$TARGET/logs/postprocessing-recovery-209938.err"; do
  echo "--- $path"
  if [[ -f "$path" ]]; then
    sha256sum "$path" 2>&1 || true
    wc -c "$path" 2>&1 || true
    case "$path" in
      *.json) cat "$path" 2>&1 || true ;;
      *) tail -n 120 "$path" 2>&1 || true ;;
    esac
  else
    echo FILE_ABSENT
  fi
done

echo '=== TUKF19 RETRY3 NONMUTATION GATE ==='
for path in "$RESULT" "$FIGURES" "$PACKAGE" "$PACKAGE.sha256.json"; do
  if [[ -e "$path" ]]; then
    echo "UNEXPECTED_PRESENT $path"
  else
    echo "EXPECTED_ABSENT $path"
  fi
done

echo '=== TUKF19 SOURCE WRAPPED ERROR IDENTITY ==='
python -B - "$SOURCE/artifacts/tukf19_hpc_deployment_retry2_v1/status/formal_failure_209845.json" "$SOURCE/logs/formal-209845.err" <<'PY'
import hashlib
import json
from pathlib import Path
import sys

failure_path = Path(sys.argv[1])
stderr_path = Path(sys.argv[2])
failure = json.loads(failure_path.read_text(encoding="utf-8"))
stderr = stderr_path.read_text(encoding="utf-8")
print(json.dumps({
    "failure_error_type": failure.get("error_type"),
    "failure_error": failure.get("error"),
    "failure_step_count": len(failure.get("steps", ())),
    "failure_step_return_codes": [row.get("return_code") for row in failure.get("steps", ())],
    "stderr_sha256": hashlib.sha256(stderr_path.read_bytes()).hexdigest(),
    "stderr_bytes": stderr_path.stat().st_size,
    "stderr_has_key_error": "KeyError" in stderr,
    "stderr_has_missing_contrast": "state_and_hydrology_update_over_no_update" in stderr,
}, indent=2, sort_keys=True))
PY
echo TUKF19_RETRY3_FAILURE_AUDIT_COMPLETE
exit 0
