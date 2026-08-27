#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

MAILBOX_ROOT="/data1/home/sunyiq/hpc_mailbox"
RESULT40="${MAILBOX_ROOT}/outbox/kalmannet-daily-camels/result_40.txt"
COLLECTOR="${MAILBOX_ROOT}/inbox/kalmannet-daily-camels/seq36_a37_probe215178_status_collect.sh"

[[ -f "$RESULT40" && ! -L "$RESULT40" ]] || {
  echo "sequence 40 receipt is absent or symbolic" >&2
  exit 51
}
grep -Fq "SEQ40_A37_PROBE2_NON_TERMINAL state=PENDING exit_code=0:0 job_id=215178" "$RESULT40" || {
  echo "sequence 40 is not the expected pending receipt" >&2
  exit 52
}
[[ -f "$COLLECTOR" && ! -L "$COLLECTOR" ]] || {
  echo "sequence 36 collector is absent or symbolic" >&2
  exit 53
}

set +e
bash "$COLLECTOR" 2>&1 | sed 's/SEQ36_/SEQ41_/g'
collector_exit_code="${PIPESTATUS[0]}"
set -e
exit "$collector_exit_code"
