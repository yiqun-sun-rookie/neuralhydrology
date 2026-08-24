#!/usr/bin/env bash
set -o pipefail

TARGET=/data1/home/sunyiq/kalmannet_tukf20_20260824
STATUS_ROOT="$TARGET/artifacts/tukf20_hpc_deployment_v1/status"
RESULT_ROOT="$TARGET/results/tukf20_hbv_rolling_origin_joint_learning_v1"
FIGURE_ROOT="$TARGET/artifacts/tukf20_hbv_rolling_origin_joint_learning_v1/figures"
JID=210748

echo '=== TUKF20 SOURCE ACCOUNTING ==='
squeue --jobs "$JID" --format='%.18i|%.12P|%.30j|%.10T|%.10M|%.10l|%R' 2>&1 || true
sacct -X --jobs "$JID" \
  --format=JobID,JobName,Partition,AllocCPUS,State,ExitCode,Elapsed,Start,End 2>&1 || true

echo '=== TUKF20 SOURCE SIZE ==='
du -sh "$TARGET" "$RESULT_ROOT" 2>&1 || true
find "$RESULT_ROOT" -type f -printf '%s\n' 2>/dev/null | \
  awk '{n+=1; b+=$1} END {printf "result_files=%d result_bytes=%.0f\n", n, b}'

echo '=== TUKF20 PINNED SOURCE HASHES ==='
for path in \
  "$TARGET/_transport/bundle_manifest.sha256.json" \
  "$TARGET/logs/formal-${JID}.out" \
  "$TARGET/logs/formal-${JID}.err" \
  "$STATUS_ROOT/formal_pipeline_started.json" \
  "$RESULT_ROOT/registry.json" \
  "$RESULT_ROOT/manifest.json" \
  "$RESULT_ROOT/independent_verification.json"; do
  test -s "$path" || { printf 'missing\t%s\n' "$path"; continue; }
  printf '%s\t%s\t%s\n' "$(sha256sum "$path" | awk '{print $1}')" "$(stat -c '%s' "$path")" "$path"
done

echo '=== TUKF20 RECOVERY TARGET GUARD ==='
RECOVERY=/data1/home/sunyiq/kalmannet_tukf20_20260824_verifier_recovery1
if test -e "$RECOVERY"; then
  printf 'present\t%s\n' "$RECOVERY"
else
  printf 'absent\t%s\n' "$RECOVERY"
fi

echo '=== TUKF20 POSTPROCESSING PRESENCE ==='
if test -d "$FIGURE_ROOT"; then du -sh "$FIGURE_ROOT"; else printf 'absent\t%s\n' "$FIGURE_ROOT"; fi
for path in \
  "$STATUS_ROOT/formal_pipeline_complete.json" \
  "$STATUS_ROOT/formal_completion.json"; do
  if test -f "$path"; then printf 'present\t%s\n' "$path"; else printf 'absent\t%s\n' "$path"; fi
done

echo 'TUKF20_RECOVERY_DIAGNOSTIC_COMPLETE'
exit 0
