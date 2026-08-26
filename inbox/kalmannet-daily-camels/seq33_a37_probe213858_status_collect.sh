#!/usr/bin/env bash
set -Eeuo pipefail

RESULT32="/data1/home/sunyiq/hpc_mailbox/outbox/kalmannet-daily-camels/result_32.txt"
[[ -f "$RESULT32" && ! -L "$RESULT32" ]] || {
  echo "sequence 32 receipt is absent or symbolic" >&2
  exit 50
}
grep -Fq 'SEQ32_A37_PROBE_NON_TERMINAL state=PENDING exit_code=0:0 job_id=213858' "$RESULT32" || {
  echo "sequence 32 does not bind the expected pending probe" >&2
  exit 51
}

set +e
bash /data1/home/sunyiq/hpc_mailbox/inbox/kalmannet-daily-camels/seq32_a37_probe213858_status_collect.sh 2>&1 | sed 's/SEQ32_/SEQ33_/g'
collector_exit="${PIPESTATUS[0]}"
set -e
exit "$collector_exit"
