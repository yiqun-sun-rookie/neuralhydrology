#!/bin/bash
# ID29: 204860_6 confirmed stalled (log unwritten 25.4 h, epoch-30 checkpoint 12 h overdue
# against a regular 1h16m cadence). Cancel it and resubmit the same frozen coordinate
# excluding the suspect nodes. Only --exclude / --job-name / --time change.
set -o pipefail
ROOT=/data1/home/sunyiq/nearing2022_da
SCRIPT="$ROOT/src/29_nearing2022_da_ar/hpc/run_registered_training_array.slurm"
BATCH=src/29_nearing2022_da_ar/registry/time_split_remaining_training_batch.txt
AR="$ROOT/closure_20260810/time_split/autoregression"

echo "=== TIME ==="; date --iso-8601=seconds

echo "=== RECHECK STALL IMMEDIATELY BEFORE CANCELLING ==="
SO="$ROOT/closure_20260810/logs/N22-retime_204860_6.out"
NOW=$(date +%s); MT=$(stat -c %Y "$SO" 2>/dev/null || echo 0)
IDLE=$((NOW-MT)); echo "idle_seconds=$IDLE"
DONE=$(find "$AR" -maxdepth 2 -path '*lead2_holdout0.75_seed0*' -name 'model_epoch030.pt' 2>/dev/null | head -1)
echo "epoch030_present=${DONE:-none}"

if [ -n "$DONE" ]; then
  echo "ABORT: epoch 30 checkpoint appeared after all; nothing to cancel."
elif [ "$IDLE" -lt 3600 ]; then
  echo "ABORT: log wrote within the last hour; job is alive, not cancelling."
else
  echo "=== CANCEL 204860 ==="
  scancel 204860 && echo "scancel_issued=yes"
  sleep 12
  sacct -X -n -P -j 204860 --format=JobID,State,Elapsed,End 2>/dev/null || true

  echo "=== RESUBMIT (exclude ngu002,ngu101) ==="
  EXISTING=$(squeue -u sunyiq -h -o '%j' 2>/dev/null | grep -c 'N22-re075' || true)
  echo "existing_re075_jobs=$EXISTING"
  if [ "$EXISTING" -eq 0 ]; then
    echo "task6_config=$(sed -n '7p' "$ROOT/$BATCH")"
    JID=$(sbatch --parsable \
      --job-name=N22-re075 \
      --array=6 \
      --time=3-12:00:00 \
      --exclude=ngu002,ngu101 \
      --export=ALL,BATCH_FILE_REL="$BATCH" \
      "$SCRIPT" 2>&1)
    echo "resubmitted_job=$JID"
  else
    echo "SKIP: N22-re075 already queued"
  fi
fi

echo "=== PRESERVED FAILED RUN DIR (evidence, not deleted) ==="
ls -1d "$AR"/*lead2_holdout0.75_seed0* 2>/dev/null || true

echo "=== QUEUE ==="
squeue -u sunyiq -h -o '%.12i %.14j %.9T %.11M %.11L %R' 2>/dev/null | grep -E 'N22|re075|re214|retime' || true

echo "=== END ==="; date --iso-8601=seconds
exit 0
