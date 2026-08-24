#!/usr/bin/env bash
set -o pipefail

TARGET=/data1/home/sunyiq/kalmannet_tukf20_20260824
STATUS_ROOT="$TARGET/artifacts/tukf20_hpc_deployment_v1/status"
JID=210748

echo '=== TUKF20 FORMAL EVIDENCE PRESENCE ==='
test -d "$STATUS_ROOT/.formal_submission_claim"
test "$(tr -d '[:space:]' < "$STATUS_ROOT/formal_job_id.txt")" = "$JID"
for path in \
  "$STATUS_ROOT/formal_submission_raw.txt" \
  "$STATUS_ROOT/formal_submission_receipt.json" \
  "$STATUS_ROOT/formal_squeue_snapshot.txt"; do
  test -s "$path" || exit 70
  printf '%s\t%s\n' "$(sha256sum "$path" | awk '{print $1}')" "$path"
done

echo '=== TUKF20 FORMAL LIVE STATUS ==='
squeue --jobs "$JID" --format='%.18i|%.12P|%.30j|%.10T|%.10M|%.10l|%R' 2>&1 || true
sacct -X --jobs "$JID" \
  --format=JobID,JobName,Partition,AllocCPUS,State,ExitCode,Elapsed,Start,End 2>&1 || true

echo '=== TUKF20 FORMAL LOG TAIL ==='
tail -n 120 "$TARGET/logs/formal-${JID}.out" 2>/dev/null || true
tail -n 120 "$TARGET/logs/formal-${JID}.err" 2>/dev/null || true

echo '=== TUKF20 FORMAL PIPELINE MARKERS ==='
for path in \
  "$STATUS_ROOT/formal_pipeline_started.json" \
  "$STATUS_ROOT/formal_pipeline_complete.json" \
  "$STATUS_ROOT/formal_completion.json"; do
  if [[ -f "$path" ]]; then
    printf 'present\t%s\t%s\n' "$(sha256sum "$path" | awk '{print $1}')" "$path"
  else
    printf 'absent\t%s\n' "$path"
  fi
done

MAIN=$(sacct -X --noheader --parsable2 --jobs "$JID" \
  --format=JobID,JobName,Partition,AllocCPUS,State,ExitCode 2>/dev/null | \
  awk -F'|' -v id="$JID" '$1 == id {print; exit}')
STATE=$(printf '%s' "$MAIN" | awk -F'|' '{print $5}' | sed 's/+.*$//')
EXIT_CODE=$(printf '%s' "$MAIN" | awk -F'|' '{print $6}')
case "$STATE" in
  FAILED|CANCELLED|TIMEOUT|NODE_FAIL|OUT_OF_MEMORY|PREEMPTED|BOOT_FAIL|DEADLINE)
    echo "TUKF20_FORMAL_TERMINAL_FAILURE state=$STATE exit_code=$EXIT_CODE"
    exit 80
    ;;
esac
echo "TUKF20_FORMAL_MONITOR_OK state=${STATE:-UNKNOWN} exit_code=${EXIT_CODE:-UNKNOWN}"
exit 0
