#!/bin/bash
# seq=50 single resubmit of the three pre-flight failures (s300/s400: ngu011 saw no GPU; s800: stale registry on ngu005).
set -o pipefail
ROOT=/data1/home/sunyiq/id33_transformer_recipe_repair_20260904/repo
cd "$ROOT" || exit 1
echo "=== STAMP ==="; date -Iseconds
echo "=== A. PRECONDITIONS ==="
ls -la src/transformer_recipe_repair/registry/experiments.csv 2>&1 || { echo "REGISTRY MISSING; abort"; exit 1; }
sha256sum src/transformer_recipe_repair/registry/experiments.csv
for s in 300 400 800; do ls src/transformer_recipe_repair/configs/*_s${s}.yml 2>&1 | wc -l | xargs -I{} echo "s$s configs: {}"; done
squeue -u "$USER" -h -o "%j" | grep -E 'id33_sd_(300|400|800)' && { echo "already queued; abort"; exit 1; }
ls -d results/33_transformer_recipe_repair/*_s300 results/33_transformer_recipe_repair/*_s400 results/33_transformer_recipe_repair/*_s800 2>/dev/null && { echo "run dirs exist; abort"; exit 1; }
echo "clean"
echo "=== B. RESUBMIT (exclude ngu002,ngu011) ==="
submit () {
  local ARMS_LIST="$1" TAG="$2" OUT J
  OUT=$(sbatch --export=ALL,ARMS="$ARMS_LIST" --job-name="id33_sd_${TAG}" --exclude=ngu002,ngu011 \
        src/transformer_recipe_repair/hpc/submit_packed_arms.slurm 2>&1)
  J=$(echo "$OUT" | grep -oE 'Submitted batch job [0-9]+' | grep -oE '[0-9]+' || true)
  [ -n "$J" ] || { echo "SUBMIT_FAILED for $ARMS_LIST: $OUT"; return 1; }
  echo "  s${TAG} ($ARMS_LIST) -> $J"
}
submit "T2_s300 C3_s300 C4_s300" "300" || exit 1
submit "T2_s400 C3_s400 C4_s400" "400" || exit 1
submit "T2_s800 C3_s800 C4_s800" "800" || exit 1
echo "=== C. QUEUE ==="
sleep 20
squeue -u "$USER" -o "%.10i %.14j %.3t %.10M %.8N %R" 2>&1 | grep -E 'JOBID|id33_' || true
echo "=== D. NEW PRE-FLIGHT HEADS ==="
sleep 60
for f in $(ls -t logs/33_transformer_recipe_repair/packed-*.out | head -3); do echo "-- $f"; head -8 "$f" || true; done
