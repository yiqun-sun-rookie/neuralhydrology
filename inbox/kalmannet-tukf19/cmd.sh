#!/usr/bin/env bash
set -o pipefail

TARGET=/data1/home/sunyiq/kalmannet_tukf19_20260823_retry2
STATUS_ROOT="$TARGET/artifacts/tukf19_hpc_deployment_retry2_v1/status"
SMOKE_REPORT="$TARGET/artifacts/tukf19_hpc_deployment_retry2_v1/smoke/smoke_report.json"
FORMAL_STDOUT="$TARGET/logs/formal-209845.out"
FORMAL_STDERR="$TARGET/logs/formal-209845.err"

echo '=== TUKF19 RETRY2 SMOKE AND FORMAL ACCOUNTING ==='
sacct -j 209844,209845 -X -n -P --format=JobIDRaw,JobName,Partition,State,ExitCode,Elapsed,Start,End,NodeList 2>&1 || true
echo '=== TUKF19 FORMAL QUEUE ==='
squeue -j 209845 -o '%.18i|%.12P|%.30j|%.10T|%.10M|%.10l|%R' 2>&1 || true

echo '=== TUKF19 BOUND SUBMISSIONS ==='
for path in "$SMOKE_REPORT" "$STATUS_ROOT/smoke_submission.json" "$STATUS_ROOT/formal_submission.json"; do
  echo "--- $path"
  if [[ -f "$path" ]]; then
    sha256sum "$path" 2>&1 || true
    cat "$path" 2>&1 || true
  else
    echo FILE_ABSENT
  fi
done

echo '=== TUKF19 FORMAL LOG TAILS ==='
for path in "$FORMAL_STDOUT" "$FORMAL_STDERR"; do
  echo "--- $path"
  if [[ -f "$path" ]]; then
    wc -c "$path" 2>&1 || true
    tail -n 120 "$path" 2>&1 || true
  else
    echo FILE_ABSENT
  fi
done

echo '=== TUKF19 FORMAL OUTPUT INVENTORY ==='
find "$TARGET/results/tukf19_hbv_rolling_origin_formal_execution_v1" -maxdepth 3 -type f -printf '%P|%s\n' 2>&1 | sort || true
find "$TARGET/artifacts/tukf19_hpc_deployment_retry2_v1" -maxdepth 3 -type f -printf '%P|%s\n' 2>&1 | sort || true
echo TUKF19_FORMAL_STATUS_SNAPSHOT_COMPLETE
exit 0
