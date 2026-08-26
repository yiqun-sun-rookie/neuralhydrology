#!/usr/bin/env bash
set -Eeuo pipefail

RESULT33="/data1/home/sunyiq/hpc_mailbox/outbox/kalmannet-daily-camels/result_33.txt"
[[ -f "$RESULT33" && ! -L "$RESULT33" ]] || {
  echo "sequence 33 receipt is absent or symbolic" >&2
  exit 50
}
grep -Fq 'SEQ33_A37_PROBE_NON_TERMINAL state=PENDING exit_code=0:0 job_id=213858' "$RESULT33" || {
  echo "sequence 33 does not bind the expected pending probe" >&2
  exit 51
}

set +e
bash /data1/home/sunyiq/hpc_mailbox/inbox/kalmannet-daily-camels/seq32_a37_probe213858_status_collect.sh 2>&1 | sed 's/SEQ32_/SEQ34_/g'
collector_exit="${PIPESTATUS[0]}"
set -e
exit "$collector_exit"
