#!/bin/bash
# ID29: four more time-split training tasks hit the 2-day wall (202215_16/20/21/22).
# Resubmit those exact array indices with the longer limit and the suspect nodes excluded.
# Frozen config/seed/batch untouched; only --time, --exclude, --job-name differ.
set -o pipefail
ROOT=/data1/home/sunyiq/nearing2022_da
SCRIPT="$ROOT/src/29_nearing2022_da_ar/hpc/run_registered_training_array.slurm"
BATCH=src/29_nearing2022_da_ar/registry/time_split_remaining_training_batch.txt

echo "=== TIME ==="; date --iso-8601=seconds
echo "=== CONFIRM THE FOUR ARE TIMEOUT AND NOT COMPLETE ==="
sacct -X -n -P -j 202215 --format=JobID,State,Elapsed 2>/dev/null | grep -E '_(16|20|21|22)\|' || true
echo "--- their configs ---"
for T in 16 20 21 22; do printf '  task%-3s line%-3s %s\n' "$T" "$((T+1))" "$(sed -n "$((T+1))p" "$ROOT/$BATCH")"; done

echo "=== IDEMPOTENCE ==="
EXISTING=$(squeue -u sunyiq -h -o '%j' 2>/dev/null | grep -c 'N22-relong' || true)
echo "existing_relong_jobs=$EXISTING"

if [ "$EXISTING" -eq 0 ]; then
  echo "=== SUBMIT (exclude ngu002,ngu101; --time 3-12:00:00; %2 concurrency) ==="
  JID=$(sbatch --parsable \
    --job-name=N22-relong \
    --array=16,20,21,22%2 \
    --time=3-12:00:00 \
    --exclude=ngu002,ngu101 \
    --export=ALL,BATCH_FILE_REL="$BATCH" \
    "$SCRIPT" 2>&1)
  echo "submitted_job=$JID"
else
  echo "SKIP: N22-relong already queued"
fi

echo "=== QUEUE ==="
squeue -u sunyiq -h -o '%.12i %.14j %.9T %.11M %.11L %R' 2>/dev/null | grep -E 'N22|relong' || true
echo "=== END ==="; date --iso-8601=seconds
exit 0
