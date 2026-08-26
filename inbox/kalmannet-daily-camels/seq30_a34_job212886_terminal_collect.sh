#!/usr/bin/env bash
set -Eeuo pipefail

# Sequence 30 is a monotonic replay of the fixed sequence 29 status/terminal
# collector. It cannot submit, cancel, reprioritize, or signal a Slurm job.
set +e
bash /data1/home/sunyiq/hpc_mailbox/inbox/kalmannet-daily-camels/seq29_a34_job212886_terminal_collect.sh 2>&1 \
  | sed 's/SEQ29_/SEQ30_/g'
collector_exit="${PIPESTATUS[0]}"
set -e
exit "$collector_exit"
