#!/bin/bash
# id26-v09-strict seq=24 : submit the remaining 21 serial trainings and return immediately.
export LC_ALL=C
ROOT=/data1/home/sunyiq/v09_strict
CODE=$ROOT/codetest/neuralhydrology
FORMAL=$CODE/results/26_historical_band_experts/formal_v09
OLD_JID=$(cat "$ROOT/suite_jobid.txt" 2>/dev/null || echo 201861)
OLD_STATE=$(sacct -j "$OLD_JID" -X -n -o State 2>/dev/null | awk 'NF {print $1; exit}')
if [ "$OLD_STATE" != "COMPLETED" ]; then
  echo "REFUSE: prior suite job $OLD_JID state is $OLD_STATE"
  exit 2
fi
DIRTY=$(find "$FORMAL" -type d \( -name '*.building' -o -name '*.failed' \) -print 2>/dev/null)
if [ -n "$DIRTY" ]; then
  echo "REFUSE: half-written or failed run directories exist"
  printf '%s\n' "$DIRTY"
  exit 3
fi
if [ -n "$(squeue -h -u "$USER" -n v09main21 2>/dev/null)" ]; then
  echo "REFUSE: a v09main21 job already exists"
  squeue -u "$USER" -n v09main21
  exit 4
fi
mkdir -p "$ROOT/jobs" "$ROOT/logs"
cat > "$ROOT/jobs/suite_remaining_21.slurm" <<'SLURM'
#!/usr/bin/env bash
#SBATCH -J v09main21
#SBATCH -p hgpu2p
#SBATCH -N 1
#SBATCH -n 1
#SBATCH --cpus-per-task=4
#SBATCH --gres=gpu:1
#SBATCH --exclude=ngu002
#SBATCH -t 3-00:00:00
#SBATCH -o /data1/home/sunyiq/v09_strict/logs/suite_remaining_%j.out
#SBATCH -e /data1/home/sunyiq/v09_strict/logs/suite_remaining_%j.err

set -eo pipefail
source /data1/home/sunyiq/miniconda3/etc/profile.d/conda.sh
conda activate nh_final || { echo "CONDA_FAILED"; exit 1; }
export PATH=/data1/home/sunyiq/v09_strict/gitenv/bin:$PATH
export MKL_THREADING_LAYER=GNU
export MKL_SERVICE_FORCE_INTEL=1
export CUBLAS_WORKSPACE_CONFIG=:4096:8

cd /data1/home/sunyiq/v09_strict/codetest/neuralhydrology
export PYTHONPATH=$(pwd):$(pwd)/src/26_historical_band_experts:$PYTHONPATH

echo "node=$(hostname) start=$(date -Iseconds)"
nvidia-smi --query-gpu=index,name,memory.free --format=csv,noheader
free -g | sed -n 2p
echo "=== RUN SUITE: remaining formal trainings (no max-runs) ==="
python -u src/26_historical_band_experts/run_formal_training_v09.py \
  --worktree-root . --device cuda:0
echo "end=$(date -Iseconds)"
SLURM
sed -i 's/\r$//' "$ROOT/jobs/suite_remaining_21.slurm"
echo "CODE_HEAD=$(git -C "$CODE" rev-parse HEAD)"
NEW_JID=$(sbatch --parsable "$ROOT/jobs/suite_remaining_21.slurm")
printf '%s\n' "$NEW_JID" > "$ROOT/suite_jobid.txt"
printf '%s\n' "$NEW_JID" > "$ROOT/suite_remaining_jobid.txt"
echo "SUBMITTED_JOB=$NEW_JID"
scontrol show job "$NEW_JID" -o 2>&1
echo "=== END ==="
