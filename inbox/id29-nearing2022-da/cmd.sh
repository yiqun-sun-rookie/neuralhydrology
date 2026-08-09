#!/bin/bash
# ID29 seq=47: submit the authorized post-completion three-arm comparison. No waiting.
ROOT=/data1/home/sunyiq/nearing2022_da
test -d "$ROOT/logs" || { echo "MISSING_LOG_DIR"; exit 2; }

echo "=== SUBMIT THREE-ARM COMPARISON ==="
sbatch --parsable /data1/home/sunyiq/hpc_mailbox/inbox/id29-nearing2022-da/compare_three_arms.slurm 2>&1
