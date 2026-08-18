#!/bin/bash
# ID29 seq=284: REPAIR. Resubmit the two timed-out time-split training array tasks with a
# longer wall limit, and recover the provenance of standalone job 202214 for its own rerun.
# Frozen configs, seeds and registries are untouched; only --time changes.
set -o pipefail
ROOT=/data1/home/sunyiq/nearing2022_da
IDEA="$ROOT/src/29_nearing2022_da_ar"
BATCH=src/29_nearing2022_da_ar/registry/time_split_remaining_training_batch.txt
SCRIPT="$IDEA/hpc/run_registered_training_array.slurm"

echo "=== PREFLIGHT ==="
date --iso-8601=seconds
cd "$ROOT"
test -f "$BATCH" && echo "batch_ok lines=$(wc -l < "$BATCH")"
echo "task6_config=$(sed -n '7p' "$BATCH")"
echo "task7_config=$(sed -n '8p' "$BATCH")"
sha256sum "$BATCH" "$SCRIPT"

echo "=== IDEMPOTENCE CHECK (do not double-submit) ==="
EXISTING=$(squeue -u sunyiq -h -o '%i|%j|%T' 2>/dev/null | grep -c 'N22-retime' || true)
echo "existing_retime_jobs=$EXISTING"

if [ "$EXISTING" -eq 0 ]; then
  echo "=== SUBMIT RERUNS (--time=3-12:00:00) ==="
  for T in 6 7; do
    JID=$(sbatch --parsable \
      --job-name=N22-retime \
      --array="$T" \
      --time=3-12:00:00 \
      --export=ALL,BATCH_FILE_REL="$BATCH" \
      "$SCRIPT" 2>&1)
    echo "task=$T submitted_job=$JID"
  done
else
  echo "SKIP: N22-retime jobs already present, not resubmitting"
fi

echo "=== 202214 PROVENANCE (for its separate rerun) ==="
sacct -X -n -P -j 202214 --format=JobID,JobName,Partition,Timelimit,State,Elapsed,End,WorkDir 2>/dev/null || true
grep -rl '202214' "$ROOT/closure_20260810/provenance" 2>/dev/null | head -5 || true
ls -la "$ROOT/closure_20260810/logs/" 2>/dev/null | grep -i '202214' | head -5 || true
head -40 "$ROOT/closure_20260810/logs/N22-train_202214.out" 2>/dev/null || true

echo "=== QUEUE AFTER ==="
squeue -u sunyiq -o '%.10i %.9P %.14j %.9T %.11M %R' 2>/dev/null | head -20 || true

echo "=== END seq=284 ==="; date --iso-8601=seconds
exit 0
