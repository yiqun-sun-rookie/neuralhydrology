#!/usr/bin/env bash
set -o pipefail

TARGET=/data1/home/sunyiq/kalmannet_tukf19_20260823_retry1
REPORT="$TARGET/artifacts/tukf19_hpc_deployment_retry1_v1/smoke/smoke_report.json"
STATUS_ROOT="$TARGET/artifacts/tukf19_hpc_deployment_retry1_v1/status"
STDOUT="$TARGET/logs/smoke-209825.out"
STDERR="$TARGET/logs/smoke-209825.err"

echo '=== TUKF19 RETRY1 ACCOUNTING ==='
sacct -j 209825 -X -n -P --format=JobIDRaw,JobName,Partition,State,ExitCode,Elapsed,NodeList 2>&1 || true
squeue -j 209825 -o '%.18i|%.12P|%.30j|%.10T|%.10M|%.10l|%R' 2>&1 || true

echo '=== TUKF19 RETRY1 FORMAL SUBMISSION BOUNDARY ==='
if [[ -e "$STATUS_ROOT/formal_submission.json" ]]; then
  echo FORMAL_SUBMISSION_UNEXPECTEDLY_PRESENT
  cat "$STATUS_ROOT/formal_submission.json" 2>&1 || true
else
  echo FORMAL_SUBMISSION_ABSENT
fi

for path in "$REPORT" "$STATUS_ROOT/smoke_submission.json" "$STATUS_ROOT/smoke_sbatch_output.txt" "$STDOUT" "$STDERR"; do
  echo "=== FILE $path ==="
  if [[ -f "$path" ]]; then
    sha256sum "$path" 2>&1 || true
    wc -c "$path" 2>&1 || true
    sed -n '1,260p' "$path" 2>&1 || true
  else
    echo FILE_ABSENT
  fi
done

echo '=== TUKF19 RETRY1 ARTIFACT INVENTORY ==='
find "$TARGET/artifacts/tukf19_hpc_deployment_retry1_v1" -maxdepth 4 -type f -printf '%P|%s\n' 2>&1 | sort || true
echo TUKF19_RETRY1_FAILURE_DIAGNOSTIC_COMPLETE
exit 0
