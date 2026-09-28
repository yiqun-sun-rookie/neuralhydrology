#!/usr/bin/env bash
set -eo pipefail
parent=/data1/home/sunyiq/kalmannet_wrr_closeout_20260928_v1
test "$(cat "$parent/plain_preflight_jobid.txt")" = 228835
test "$(cat "$parent/adaptive_preflight_jobid.txt")" = 228839
sacct -n -P -j 228835,228839 -o JobID,JobName,State,ExitCode,Elapsed,NodeList,MaxRSS
for unit in plain adaptive; do
  if [ "$unit" = plain ]; then job=228835; subtree=numerical_impact; else job=228839; subtree=adaptive_comparison; fi
  root="$parent/${unit}_preflight_v1"
  echo "${unit}_COMPLETIONS"
  find "$root/$subtree/runs" -mindepth 2 -maxdepth 2 -name completion.json -printf '%P\n' | sort
  echo "${unit}_FAILURES"
  find "$root/$subtree/runs" -maxdepth 2 -name failure.json -exec cat {} \;
  for suffix in out err; do
    echo "${unit}_${suffix}_TAIL"
    if [ -f "$root/logs/${unit}-preflight-${job}.${suffix}" ]; then tail -n 60 "$root/logs/${unit}-preflight-${job}.${suffix}"; fi
  done
done
state=$(sacct -n -X -P -j 228835 -o State | head -n 1 | cut -d'|' -f1)
case "$state" in
  COMPLETED|FAILED|CANCELLED*|TIMEOUT|OUT_OF_MEMORY|NODE_FAIL|PREEMPTED|BOOT_FAIL|DEADLINE)
    root="$parent/plain_preflight_v1"
    archive="$parent/plain_receipts_001.tar.gz"
    test ! -e "$archive"
    cd "$root"
    find numerical_impact/runs -type f -name '*.json' -print0 | tar -czf "$archive" --null -T - deployed_manifest.json
    echo "PLAIN_RECEIPTS_SHA256=$(sha256sum "$archive" | cut -d' ' -f1)"
    echo BEGIN_PLAIN_RECEIPTS_TAR_GZ
    base64 "$archive"
    echo END_PLAIN_RECEIPTS_TAR_GZ
    ;;
  *) echo "PLAIN_RECEIPTS_NOT_TERMINAL=$state" ;;
esac
