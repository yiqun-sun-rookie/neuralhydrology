#!/bin/bash
# id26-v09-strict seq=9 : create the one-use A09-NEST-01 receipt, then SUBMIT the strict
# training and return immediately. Does NOT wait -- the run is ~2.7 h and the mailbox
# worker is killed at 2 h. Polling happens in later seq rounds.
export LC_ALL=C
ROOT=/data1/home/sunyiq/v09_strict
REPO=$ROOT/neuralhydrology
GITENV=$ROOT/gitenv
D=$REPO/results/26_historical_band_experts/formal_v09
export PATH=$GITENV/bin:$PATH

echo "=== A GATE: prerequisites present, stage unused ==="
for f in R09-NEST-S100.legacy_checkpoint_bridge_external_audit.json \
         R09-NEST-S100.training_resource_preflight_external_audit.json; do
  [ -f "$D/$f" ] && echo "OK      $f" || { echo "MISSING $f -- stopping"; exit 1; }
done
for p in "$D/authorizations/A09-NEST-01.authorization.json" \
         "$D/authorizations/A09-NEST-01.consumption.json" \
         "$D/strict_nesting"; do
  [ -e "$p" ] && { echo "PRESENT(BAD) $(basename "$p") -- stopping"; exit 1; }
done
echo "stage unused: confirmed"
cd "$REPO" || exit 1
echo "git=$(git --version)  dirty_files=$(git status --porcelain --untracked-files=all | wc -l) (want 0)"

echo "=== B CREATE THE ONE-USE AUTHORIZATION (no GPU, no training) ==="
"$HOME/miniconda3/envs/nh_final/bin/python" -u \
  src/26_historical_band_experts/create_formal_strict_authorization_v09.py 2>&1 | tail -30
echo "create_rc=$?"

echo "=== C VERIFY THE RECEIPT ON DISK ==="
if [ -f "$D/authorizations/A09-NEST-01.authorization.json" ]; then
  "$HOME/miniconda3/envs/nh_final/bin/python" - <<'PY' 2>&1 | tail -14
import json, pathlib
p = pathlib.Path.home()/"v09_strict/neuralhydrology/results/26_historical_band_experts/formal_v09/authorizations/A09-NEST-01.authorization.json"
r = json.loads(p.read_text(encoding="utf-8"))
for k in ("status","receipt_id","scope","maximum_attempts","allowed_runs","git_commit",
          "formal_prediction_generation_authorized","official_scoring_authorized"):
    print(f"{k:40s} {r.get(k)}")
print("approval_text_ok                        ", r["approval"]["text"].startswith("批准版本09严格嵌套训练阶段"))
PY
else
  echo "NO RECEIPT -- stopping"; exit 1
fi

echo "=== D WRITE TRAINING SLURM ==="
cat > "$ROOT/jobs/train.slurm" <<'SLURM'
#!/usr/bin/env bash
#SBATCH -J v09train
#SBATCH -p hgpu2p
#SBATCH -N 1
#SBATCH -n 1
#SBATCH --cpus-per-task=4
#SBATCH --gres=gpu:1
#SBATCH --exclude=ngu002
#SBATCH -t 12:00:00
#SBATCH -o /data1/home/sunyiq/v09_strict/logs/train_%j.out
#SBATCH -e /data1/home/sunyiq/v09_strict/logs/train_%j.err
# no --mem on this platform

set -eo pipefail

source /data1/home/sunyiq/miniconda3/etc/profile.d/conda.sh
conda activate nh_final || { echo "CONDA_FAILED"; exit 1; }

export PATH=/data1/home/sunyiq/v09_strict/gitenv/bin:$PATH
export MKL_THREADING_LAYER=GNU
export MKL_SERVICE_FORCE_INTEL=1

cd /data1/home/sunyiq/v09_strict/neuralhydrology
export PYTHONPATH=$(pwd):$PYTHONPATH

echo "node=$(hostname) start=$(date -Iseconds)"
echo "git=$(git --version)"
nvidia-smi --query-gpu=index,name,memory.free --format=csv,noheader
free -g | sed -n 2p

echo "=== RUN STRICT NESTING TRAINING (531 basins, 30 epochs, seed 100) ==="
python -u src/26_historical_band_experts/run_formal_strict_stage_v09.py
echo "end=$(date -Iseconds)"
SLURM
sed -i 's/\r$//' "$ROOT/jobs/train.slurm"
file "$ROOT/jobs/train.slurm"

echo "=== E SUBMIT (do not wait) ==="
cd "$ROOT/jobs"
JID=$(sbatch --parsable train.slurm 2>&1)
echo "TRAIN_JOBID=$JID"
echo "$JID" > "$ROOT/train_jobid.txt"
sleep 20
squeue -j "$JID" -o "%.10i %.10j %.9P %.8T %.10M %R" 2>&1 | head -5

echo "=== F NOTE ==="
echo "expected wall clock ~2-3 h; checkpoints at epochs 10/20/30"
echo "outputs land in: $D/strict_nesting/R09-NEST-S100"
echo "poll with a later seq; this worker exits now on purpose"
echo "=== END ==="
