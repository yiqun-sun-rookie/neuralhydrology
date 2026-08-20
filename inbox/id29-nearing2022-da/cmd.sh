#!/bin/bash
# ID29 seq=288: (a) verify the two finished repair reruns produced epoch-30 checkpoints,
# (b) inspect the 202214 coordinate's run dir, (c) submit its rerun with the longer wall
# limit using a NEW one-line repair batch file. Frozen registries are not touched.
set -o pipefail
ROOT=/data1/home/sunyiq/nearing2022_da
AR="$ROOT/closure_20260810/time_split/autoregression"
REPAIR="$ROOT/closure_20260810/repair"
SCRIPT="$ROOT/src/29_nearing2022_da_ar/hpc/run_registered_training_array.slurm"

echo "=== TIME ==="; date --iso-8601=seconds

echo "=== A. RERUN CHECKPOINTS ==="
sacct -X -n -P -j 204860,204861 --format=JobID,State,Elapsed,End 2>/dev/null || true
for C in lead_2_holdout_0.75_seed_0 lead_2_holdout_1.0_seed_0 lead_1_holdout_0.5_seed_0; do
  echo "--- $C ---"
  find "$AR" -mindepth 1 -maxdepth 1 -type d -name "*${C}*" 2>/dev/null | while read -r D; do
    printf '  dir=%s\n    epoch030=%s  n_ckpt=%s  latest=%s\n' "$(basename "$D")" \
      "$([ -f "$D/model_epoch030.pt" ] && echo YES || echo no)" \
      "$(ls "$D"/model_epoch*.pt 2>/dev/null | wc -l)" \
      "$(ls "$D"/model_epoch*.pt 2>/dev/null | tail -1 | xargs -r basename)"
  done
done

echo "=== B. SUBMIT 202214 COORDINATE RERUN ==="
EXISTING=$(squeue -u sunyiq -h -o '%j' 2>/dev/null | grep -c 'N22-re214' || true)
echo "existing_re214_jobs=$EXISTING"
DONE=$(find "$AR" -mindepth 1 -maxdepth 1 -type d -name '*lead_1_holdout_0.5_seed_0*_ep30' -exec test -f '{}/model_epoch030.pt' \; -print 2>/dev/null | head -1)
echo "already_complete=${DONE:-none}"

if [ "$EXISTING" -eq 0 ] && [ -z "$DONE" ]; then
  mkdir -p "$REPAIR"
  printf 'src/29_nearing2022_da_ar/configs/full_reproduction/time_split/autoregression/lead_1_holdout_0.5_seed_0.yml\n' \
    > "$REPAIR/lead1_holdout050_rerun_batch.txt"
  echo "batch_written sha256=$(sha256sum "$REPAIR/lead1_holdout050_rerun_batch.txt" | cut -d' ' -f1)"
  cat "$REPAIR/lead1_holdout050_rerun_batch.txt"
  JID=$(sbatch --parsable \
    --job-name=N22-re214 \
    --array=0 \
    --time=3-12:00:00 \
    --export=ALL,BATCH_FILE_REL=closure_20260810/repair/lead1_holdout050_rerun_batch.txt \
    "$SCRIPT" 2>&1)
  echo "submitted_job=$JID"
else
  echo "SKIP: already queued or already complete"
fi

echo "=== C. QUEUE ==="
squeue -u sunyiq -h -o '%.12i %.14j %.9T %.11M %.11L %R' 2>/dev/null | grep -E 'N22|re214|retime' | head -14 || true

echo "=== END seq=288 ==="; date --iso-8601=seconds
exit 0
