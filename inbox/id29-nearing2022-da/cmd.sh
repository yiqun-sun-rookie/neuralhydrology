#!/bin/bash
# ID29: RETRY of the cancel/resubmit that was overwritten by the scheduled watch.
# Self-guarding: re-verifies the stall immediately before acting, aborts if the job recovered.
set -o pipefail
ROOT=/data1/home/sunyiq/nearing2022_da
SCRIPT="$ROOT/src/29_nearing2022_da_ar/hpc/run_registered_training_array.slurm"
BATCH=src/29_nearing2022_da_ar/registry/time_split_remaining_training_batch.txt
AR="$ROOT/closure_20260810/time_split/autoregression"

echo "=== TIME ==="; date --iso-8601=seconds

STATE=$(sacct -X -n -P -j 204860 --format=State 2>/dev/null | head -1)
echo "204860_state=$STATE"
SO="$ROOT/closure_20260810/logs/N22-retime_204860_6.out"
NOW=$(date +%s); MT=$(stat -c %Y "$SO" 2>/dev/null || echo 0); IDLE=$((NOW-MT))
echo "idle_seconds=$IDLE"
DONE=$(find "$AR" -maxdepth 2 -path '*lead2_holdout0.75_seed0*' -name 'model_epoch030.pt' 2>/dev/null | head -1)
echo "epoch030_present=${DONE:-none}"

if [ -n "$DONE" ]; then
  echo "ABORT: epoch-30 checkpoint exists; nothing to do."
elif [ "$IDLE" -lt 3600 ]; then
  echo "ABORT: log wrote within the last hour; job alive."
else
  case "$STATE" in
    RUNNING*|PENDING*)
      echo "=== CANCEL 204860 ==="
      scancel 204860 && echo "scancel_issued=yes"
      sleep 12
      sacct -X -n -P -j 204860 --format=JobID,State,Elapsed,End 2>/dev/null || true
      ;;
    *) echo "204860 already terminal ($STATE); skipping scancel" ;;
  esac

  echo "=== RESUBMIT (exclude ngu002,ngu101) ==="
  EXISTING=$(squeue -u sunyiq -h -o '%j' 2>/dev/null | grep -c 'N22-re075' || true)
  echo "existing_re075_jobs=$EXISTING"
  if [ "$EXISTING" -eq 0 ]; then
    echo "task6_config=$(sed -n '7p' "$ROOT/$BATCH")"
    JID=$(sbatch --parsable --job-name=N22-re075 --array=6 --time=3-12:00:00 \
      --exclude=ngu002,ngu101 --export=ALL,BATCH_FILE_REL="$BATCH" "$SCRIPT" 2>&1)
    echo "resubmitted_job=$JID"
  else
    echo "SKIP: N22-re075 already queued"
  fi
fi

echo "=== PRESERVED RUN DIRS (evidence kept) ==="
ls -1d "$AR"/*lead2_holdout0.75_seed0* 2>/dev/null || true
echo "=== QUEUE ==="
squeue -u sunyiq -h -o '%.12i %.14j %.9T %.11M %.11L %R' 2>/dev/null | grep -E 'N22|re075|re214' || true
echo "=== END ==="; date --iso-8601=seconds
exit 0
