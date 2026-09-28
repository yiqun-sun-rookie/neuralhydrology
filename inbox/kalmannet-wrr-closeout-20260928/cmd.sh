#!/usr/bin/env bash
set -eo pipefail
parent=/data1/home/sunyiq/kalmannet_wrr_closeout_20260928_v1
test "$(cat "$parent/adaptive_preflight_jobid.txt")" = 228839
sacct -n -P -j 228835,228839 -o JobID,JobName,State,ExitCode,Elapsed,NodeList,MaxRSS
root="$parent/adaptive_preflight_v1"
find "$root/adaptive_comparison/runs" -mindepth 2 -maxdepth 2 -name completion.json -printf '%P\n' | sort
find "$root/adaptive_comparison/runs" -maxdepth 2 -name failure.json -exec cat {} \;
for suffix in out err; do
  echo "ADAPTIVE_${suffix}_TAIL"
  if [ -f "$root/logs/adaptive-preflight-228839.${suffix}" ]; then tail -n 60 "$root/logs/adaptive-preflight-228839.${suffix}"; fi
done
state=$(sacct -n -X -P -j 228839 -o State | head -n 1 | cut -d'|' -f1)
case "$state" in
  COMPLETED|FAILED|CANCELLED*|TIMEOUT|OUT_OF_MEMORY|NODE_FAIL|PREEMPTED|BOOT_FAIL|DEADLINE)
    archive="$parent/adaptive_receipts_001.tar.gz"
    test ! -e "$archive"
    cd "$root"
    find adaptive_comparison/runs -type f -not -path '*/cache/*' \( -name '*.json' -o -name 'physical_plain_*.py' \) -print0 | tar -czf "$archive" --null -T -
    echo "ADAPTIVE_RECEIPTS_SHA256=$(sha256sum "$archive" | cut -d' ' -f1)"
    echo BEGIN_ADAPTIVE_RECEIPTS_TAR_GZ
    base64 "$archive"
    echo END_ADAPTIVE_RECEIPTS_TAR_GZ
    ;;
  *) echo "ADAPTIVE_RECEIPTS_NOT_TERMINAL=$state" ;;
esac
