#!/bin/bash
# id26-v09-strict seq=15 : first real main-training runs -- seed 100, all three arms.
# Runs in ~/v09_strict/codetest so the sealed strict-nesting evidence tree stays at its
# recorded commit f9418320. Submits and returns; the suite is ~4 h and the mailbox worker
# is killed at 2 h, so progress is polled in later rounds.
export LC_ALL=C
ROOT=/data1/home/sunyiq/v09_strict
CODE=$ROOT/codetest/neuralhydrology
TAR=$ROOT/upload_archive/v09_sealed_input.tar.gz
WANT_TAR=feee746c7bda7970c8bac470969bf4247118f8f35d6cf543a44a8a6b4bd1bed7
export PATH=$ROOT/gitenv/bin:$PATH

echo "=== A CODE ==="
cd "$CODE" && git fetch -q origin "+codex/historical-band-experts-pilot:refs/remotes/origin/codex/historical-band-experts-pilot" \
  && git checkout -q refs/remotes/origin/codex/historical-band-experts-pilot
echo "codetest HEAD = $(git rev-parse HEAD)"
echo "dirty = $(git status --porcelain --untracked-files=no | wc -l)"

echo "=== B SEALED INPUTS INTO THE CODE TREE ==="
D=$CODE/results/26_historical_band_experts/formal_v09
if [ -f "$D/input_attempt_01/seal.json" ]; then
  echo "inputs already present"
else
  echo "tar sha256 = $(sha256sum "$TAR" | cut -d' ' -f1)"
  echo "expected   = $WANT_TAR"
  [ "$(sha256sum "$TAR" | cut -d' ' -f1)" = "$WANT_TAR" ] || { echo "TAR HASH MISMATCH"; exit 1; }
  mkdir -p "$CODE/results/26_historical_band_experts"
  tar xzf "$TAR" -C "$CODE" && echo "extracted"
fi
echo "input files: $(find "$D/input_attempt_01" -type f | wc -l) (want 13)"
"$HOME/miniconda3/envs/nh_final/bin/python" - <<'PY'
import hashlib, json, pathlib
root = pathlib.Path.home()/"v09_strict/codetest/neuralhydrology/results/26_historical_band_experts/formal_v09/input_attempt_01"
seal = json.loads((root/"seal.json").read_text(encoding="utf-8"))
bad = sum(hashlib.sha256((root/i["relative_path"].replace("\\","/")).read_bytes()).hexdigest() != i["sha256"]
          for i in seal["sealed_files"])
print(f"sealed files {len(seal['sealed_files'])}, mismatches {bad} (want 0)")
PY

echo "=== C PROGRESS BEFORE ==="
cd "$CODE"
"$HOME/miniconda3/envs/nh_final/bin/python" - <<'PY'
import sys, json, pathlib
sys.path.insert(0, "src/26_historical_band_experts")
from run_formal_training_v09 import scan_progress_v09
from train_formal_v09 import load_run_order_v09
root = pathlib.Path.cwd()
specs = load_run_order_v09("src/26_historical_band_experts/configs/formal_v09_run_order.json")
p = scan_progress_v09(root, specs)
print(json.dumps({k: (v if k != "pending" else v[:4]) for k, v in p.items()}, indent=2))
PY

echo "=== D WRITE SUITE JOB ==="
mkdir -p "$ROOT/jobs" "$ROOT/logs"
cat > "$ROOT/jobs/suite.slurm" <<'SLURM'
#!/usr/bin/env bash
#SBATCH -J v09suite
#SBATCH -p hgpu2p
#SBATCH -N 1
#SBATCH -n 1
#SBATCH --cpus-per-task=4
#SBATCH --gres=gpu:1
#SBATCH --exclude=ngu002
#SBATCH -t 12:00:00
#SBATCH -o /data1/home/sunyiq/v09_strict/logs/suite_%j.out
#SBATCH -e /data1/home/sunyiq/v09_strict/logs/suite_%j.err

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

echo "=== RUN SUITE: seed 100, three arms (max-runs 3) ==="
python -u src/26_historical_band_experts/run_formal_training_v09.py \
  --worktree-root . --device cuda:0 --max-runs 3
echo "end=$(date -Iseconds)"
SLURM
sed -i 's/\r$//' "$ROOT/jobs/suite.slurm"

echo "=== E SUBMIT (do not wait) ==="
cd "$ROOT/jobs"
JID=$(sbatch --parsable suite.slurm 2>&1)
echo "SUITE_JOBID=$JID"
echo "$JID" > "$ROOT/suite_jobid.txt"
sleep 25
squeue -j "$JID" -o "%.10i %.10j %.9P %.8T %.10M %R" 2>&1 | head -5
echo "=== F NOTE ==="
echo "expected ~4 h for three arms; poll with a later seq"
echo "strict evidence tree untouched at: $(cd $ROOT/neuralhydrology && git rev-parse HEAD)"
echo "=== END ==="
