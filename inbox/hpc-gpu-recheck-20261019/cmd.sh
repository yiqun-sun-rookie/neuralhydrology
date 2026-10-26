#!/bin/bash
set -euo pipefail
root=/data1/home/sunyiq/hpc_gpu_recheck_20261019_001
mkdir -p "$root/closeout_user_20261026"
date -Iseconds
for pair in ngu201:245333 ngu202:245334; do
 node=${pair%%:*}; id=${pair##*:}
 test "$(tr -d '\r\n' < "$root/nodes/$node/job_id.txt")" = "$id"
 row=$(timeout 25 squeue -h -j "$id" -o '%i|%j|%u|%T')
 printf 'BEFORE|%s|%s\n' "$node" "$row"
 if test -n "$row"; then
  expected_name=ghr_${node#ngu}_261019
  case "$row" in
   "$id|$expected_name|sunyiq|PENDING")
    printf '%s USER_AUTHORIZED_CANCEL %s %s\n' "$(date -Iseconds)" "$node" "$id" >> "$root/closeout_user_20261026/actions.log"
    timeout 25 scancel "$id"
    ;;
   "$id|$expected_name|sunyiq|RUNNING"|"$id|$expected_name|sunyiq|COMPLETING") echo "ALREADY_RUNNING_WAIT_FOR_BOUNDED_SHORT_PROBE|$id" ;;
   *) echo "IDENTITY_OR_STATE_MISMATCH|$row"; exit 7;;
  esac
 fi
 timeout 25 squeue -h -j "$id" -o '%i|%j|%u|%T'
 timeout 25 sacct -X -S 2026-10-19 -j "$id" --format=JobIDRaw,JobName%24,State,ExitCode,Elapsed,NodeList -n -P
 if test -f "$root/nodes/$node/result.json"; then
  echo "RESULT_JSON_NODE=$node"; cat "$root/nodes/$node/result.json"; echo; echo "END_RESULT_JSON_NODE=$node"
 fi
done
echo USER_AUTHORIZED_CLOSEOUT_NO_NEW_SUBMISSIONS
