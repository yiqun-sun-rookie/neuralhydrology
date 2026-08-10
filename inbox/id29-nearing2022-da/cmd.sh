#!/bin/bash
# ID29 seq=61: install evaluation closure v4 and submit coordinates whose checkpoints already exist.
set -eo pipefail

ROOT=/data1/home/sunyiq/nearing2022_da
PAYLOAD=/data1/home/sunyiq/hpc_mailbox/payload/id29-nearing2022-da/closure_v4.tar.gz
EXPECTED_PAYLOAD_SHA=9ba30a8a4adc2030f9b4f8a6e04eb67b4aa69bc56e103343cfeb9179f5a06dac
SCRIPT="$ROOT/src/29_nearing2022_da_ar/hpc/run_registered_evaluation_array.slurm"
REGISTRY_REL=src/29_nearing2022_da_ar/registry/evaluation_registry.csv
BATCH_REL=src/29_nearing2022_da_ar/registry/time_split_existing_source_evaluation_batch.txt
REGISTRY="$ROOT/$REGISTRY_REL"
BATCH="$ROOT/$BATCH_REL"
TRAINING_REGISTRY="$ROOT/src/29_nearing2022_da_ar/registry/experiment_registry.csv"
PREPARE="$ROOT/src/29_nearing2022_da_ar/scripts/prepare_evaluation_run.py"

echo "=== PAYLOAD ==="
echo "$EXPECTED_PAYLOAD_SHA  $PAYLOAD" | sha256sum -c -
echo "payload_members=$(tar -tzf "$PAYLOAD" | wc -l)"
tar -xzf "$PAYLOAD" -C "$ROOT"

echo "=== PREFLIGHT ==="
test -f "$SCRIPT"
test -f "$REGISTRY"
test -f "$TRAINING_REGISTRY"
test -f "$PREPARE"
test "$(grep -cv '^[[:space:]]*$' "$BATCH")" -eq 30
sha256sum "$SCRIPT" "$REGISTRY" "$TRAINING_REGISTRY" "$BATCH" "$PREPARE"
source ~/miniconda3/etc/profile.d/conda.sh
conda activate nh_final
cd "$ROOT"
export PYTHONPATH="$ROOT${PYTHONPATH:+:$PYTHONPATH}"
python "$PREPARE" \
  --repo-root "$ROOT" \
  --training-registry "$TRAINING_REGISTRY" \
  --evaluation-registry "$REGISTRY" \
  --eval-id N22-EVAL-TS-AR-L01-TR000-TE000-S0 \
  --plain

if squeue -h -u "$USER" -n N22-eval-now | grep -q .; then
  echo "Refusing duplicate N22-eval-now submission" >&2
  squeue -u "$USER" -n N22-eval-now
  exit 3
fi

echo "=== SUBMIT ==="
JOB_ID=$(sbatch --parsable --job-name=N22-eval-now --array=0-29%2 \
  --export=ALL,REGISTRY_KIND=evaluation,REGISTRY_REL="$REGISTRY_REL",BATCH_FILE_REL="$BATCH_REL" \
  "$SCRIPT")
echo "evaluation_job_id=$JOB_ID tasks=30 max_concurrent=2 completed_coordinates_skip_automatically=true"
squeue -j "$JOB_ID" -o '%.18i %.18j %.2t %.10M %.6D %R'
