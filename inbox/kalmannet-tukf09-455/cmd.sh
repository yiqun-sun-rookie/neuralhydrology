#!/bin/bash
# TUKF09-455: read-only progress of the v2r14 training job. Changes nothing.
set -eo pipefail
ROOT=/data1/home/sunyiq/kalmannet_tukf09_455_basin_zero_validation_target_variance_revision_v1_a800_exclusive_v2r14_20260909
N="$ROOT/bundle/kalmannet/results/tukf09_455_basin_zero_validation_target_variance_revision_v1/neural"
JOB=$(cat "$ROOT/status/training_job_id.txt")
echo "TIME=$(date -Is)  TRAINING_JOB=$JOB"
sacct -j "$JOB" -o JobID,State,ExitCode,Elapsed,NodeList -P 2>&1 | head -5

echo "=== WHAT THE CARDS ARE DOING ==="
srun --jobid="$JOB" --overlap -N1 -n1 bash -c "nvidia-smi --query-gpu=index,utilization.gpu,memory.used --format=csv,noheader" 2>&1 | head -6 || echo "(could not attach)"

echo "=== NEURAL UNITS SO FAR ==="
if [ -d "$N" ]; then
  echo "SHARED_SCALER=$(test -f "$N/shared/training_scaler.json" && echo present || echo absent)"
  for d in "$N"/lead_*; do
    test -d "$d" || continue
    echo "$(basename "$d") checkpoints=$(ls "$d"/checkpoints/epoch_*.pt 2>/dev/null | wc -l) latest=$(ls -t "$d"/checkpoints/epoch_*.pt 2>/dev/null | head -1 | xargs -r basename)"
  done
  echo "TOTAL_CHECKPOINTS=$(find "$N" -name "epoch_*.pt" 2>/dev/null | wc -l)"
else
  echo "(the neural tree does not exist yet)"
fi

echo "=== TRAINING STDOUT TAIL ==="
tail -n 20 "$ROOT/logs/training-$JOB.out" 2>/dev/null | cut -c1-260 || echo "(nothing yet)"
echo "=== TRAINING STDERR TAIL ==="
tail -n 20 "$ROOT/logs/training-$JOB.err" 2>/dev/null | cut -c1-260 || echo "(nothing yet)"

echo TUKF09_455_V2R14_TRAINING_STATUS_READ_ONLY_DONE
