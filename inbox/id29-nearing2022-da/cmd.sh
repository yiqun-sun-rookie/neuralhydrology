#!/bin/bash
# ID29 seq=62: register fail-closed dependent arrays for the remaining evaluation and hyperparameter coordinates.
set -eo pipefail

ROOT=/data1/home/sunyiq/nearing2022_da
SCRIPT="$ROOT/src/29_nearing2022_da_ar/hpc/run_registered_evaluation_array.slurm"
EVAL_REGISTRY_REL=src/29_nearing2022_da_ar/registry/evaluation_registry.csv
HYPER_REGISTRY_REL=src/29_nearing2022_da_ar/registry/assimilation_hyperparameter_registry.csv
TIME_BATCH_REL=src/29_nearing2022_da_ar/registry/time_split_pending_source_evaluation_batch.txt
BASIN_BATCH_REL=src/29_nearing2022_da_ar/registry/basin_assimilation_evaluation_batch.txt
HYPER_BATCH_REL=src/29_nearing2022_da_ar/registry/hyperparameter_evaluation_batch.txt

echo "=== PREFLIGHT ==="
test -f "$SCRIPT"
test "$(grep -cv '^[[:space:]]*$' "$ROOT/$TIME_BATCH_REL")" -eq 120
test "$(grep -cv '^[[:space:]]*$' "$ROOT/$BASIN_BATCH_REL")" -eq 10
test "$(grep -cv '^[[:space:]]*$' "$ROOT/$HYPER_BATCH_REL")" -eq 660
sha256sum \
  "$SCRIPT" \
  "$ROOT/$EVAL_REGISTRY_REL" \
  "$ROOT/$HYPER_REGISTRY_REL" \
  "$ROOT/$TIME_BATCH_REL" \
  "$ROOT/$BASIN_BATCH_REL" \
  "$ROOT/$HYPER_BATCH_REL"
scontrol show job 202214 >/dev/null
scontrol show job 202215 >/dev/null
scontrol show job 202216 >/dev/null

if squeue -h -u "$USER" -n N22-eval-later,N22-basin-da,N22-hyper | grep -q .; then
  echo "Refusing duplicate dependent evaluation submission" >&2
  squeue -u "$USER" -n N22-eval-later,N22-basin-da,N22-hyper
  exit 3
fi

echo "=== SUBMIT ==="
TIME_EVAL_JOB=$(sbatch --parsable --job-name=N22-eval-later --dependency=afterok:202214:202215 \
  --array=0-119%4 \
  --export=ALL,REGISTRY_KIND=evaluation,REGISTRY_REL="$EVAL_REGISTRY_REL",BATCH_FILE_REL="$TIME_BATCH_REL" \
  "$SCRIPT")
BASIN_DA_JOB=$(sbatch --parsable --job-name=N22-basin-da --dependency=afterok:202216 \
  --array=0-9%2 \
  --export=ALL,REGISTRY_KIND=evaluation,REGISTRY_REL="$EVAL_REGISTRY_REL",BATCH_FILE_REL="$BASIN_BATCH_REL" \
  "$SCRIPT")
HYPER_JOB=$(sbatch --parsable --job-name=N22-hyper --dependency=afterok:202216 \
  --array=0-659%2 \
  --export=ALL,REGISTRY_KIND=hyperparameter,REGISTRY_REL="$HYPER_REGISTRY_REL",BATCH_FILE_REL="$HYPER_BATCH_REL" \
  "$SCRIPT")

echo "time_evaluation_job_id=$TIME_EVAL_JOB tasks=120 max_concurrent=4 dependency=afterok:202214:202215"
echo "basin_assimilation_job_id=$BASIN_DA_JOB tasks=10 max_concurrent=2 dependency=afterok:202216"
echo "hyperparameter_job_id=$HYPER_JOB tasks=660 max_concurrent=2 dependency=afterok:202216"
squeue -j "$TIME_EVAL_JOB,$BASIN_DA_JOB,$HYPER_JOB" -o '%.18i %.18j %.2t %.10M %.6D %R'
