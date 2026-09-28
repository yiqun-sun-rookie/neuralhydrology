#!/usr/bin/env bash
set -eo pipefail
parent=/data1/home/sunyiq/kalmannet_wrr_closeout_20260928_v1
sacct -n -P -j 229130,229131 -o JobID,JobName,State,ExitCode,Elapsed,NodeList,MaxRSS
for package in plain adaptive; do
  if [ "$package" = plain ]; then subtree=numerical_impact; job=229130; logroot=formal_launch_001/logs; stem=original-bridge; else subtree=adaptive_comparison; job=229131; logroot=logs; stem=adaptive-validation; fi
  root="$parent/${package}_preflight_v1"
  echo "${package}_FORMAL_COMPLETION_FILES"
  find "$root/$subtree/runs" -path '*__formal_attempt01/completion.json' -type f -printf '%P\n' | sort
  echo "${package}_FORMAL_FAILURES"
  find "$root/$subtree/runs" -path '*__formal_attempt01/failure.json' -type f -exec cat {} \;
  for suffix in out err; do
    echo "${package}_${suffix}_TAIL"
    if [ -f "$root/$logroot/$stem-$job.$suffix" ]; then tail -n 25 "$root/$logroot/$stem-$job.$suffix"; fi
  done
done
state=$(sacct -n -X -P -j 229130 -o State | head -n 1 | cut -d'|' -f1)
case "$state" in
  COMPLETED|FAILED|CANCELLED*|TIMEOUT|OUT_OF_MEMORY|NODE_FAIL|PREEMPTED|BOOT_FAIL|DEADLINE)
    root="$parent/plain_preflight_v1"
    archive="$parent/plain_formal_failure_receipts_001.tar.gz"
    test ! -e "$archive"
    cd "$root"
    find numerical_impact/runs -type f -path '*__formal_attempt01/*.json' -print0 | tar -czf "$archive" --null -T - deployed_manifest.json
    echo "PLAIN_RECEIPTS_SHA256=$(sha256sum "$archive" | cut -d' ' -f1)"
    echo BEGIN_PLAIN_RECEIPTS_TAR_GZ
    base64 "$archive"
    echo END_PLAIN_RECEIPTS_TAR_GZ
    ;;
  *) echo "PLAIN_RECEIPTS_NOT_TERMINAL=$state" ;;
esac
