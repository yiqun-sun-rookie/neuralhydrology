#!/bin/bash
# id26-v09-strict seq=7 : submit the v09 prerequisite entry as a GPU job (go/no-go gate).
# Login node does NOT compute here -- it only writes the slurm file, submits, and waits.
# The slurm script lives OUTSIDE the repo so the worktree stays clean (a v09 gate requires it).
export LC_ALL=C
ROOT=/data1/home/sunyiq/v09_strict
REPO=$ROOT/neuralhydrology
mkdir -p "$ROOT/jobs" "$ROOT/logs"

cat > "$ROOT/jobs/prepare.slurm" <<'SLURM'
#!/usr/bin/env bash
#SBATCH -J v09prep
#SBATCH -p hgpu2p
#SBATCH -N 1
#SBATCH -n 1
#SBATCH --cpus-per-task=4
#SBATCH --gres=gpu:1
#SBATCH --exclude=ngu002
#SBATCH -t 01:00:00
#SBATCH -o /data1/home/sunyiq/v09_strict/logs/prep_%j.out
#SBATCH -e /data1/home/sunyiq/v09_strict/logs/prep_%j.err
# no --mem on this platform

set -eo pipefail

source /data1/home/sunyiq/miniconda3/etc/profile.d/conda.sh
conda activate nh_final || { echo "CONDA_FAILED"; exit 1; }

export MKL_THREADING_LAYER=GNU
export MKL_SERVICE_FORCE_INTEL=1

cd /data1/home/sunyiq/v09_strict/neuralhydrology
export PYTHONPATH=$(pwd):$PYTHONPATH

echo "node=$(hostname)"
nvidia-smi --query-gpu=index,name,memory.total,memory.free --format=csv,noheader
python -c "import torch,numpy,sys;print('py',sys.version.split()[0],'torch',torch.__version__,'numpy',numpy.__version__,'cuda_ok',torch.cuda.is_available())"
free -g | head -2

echo "=== RUN PREPARE ==="
python -u src/26_historical_band_experts/prepare_formal_strict_stage_v09.py
SLURM

sed -i 's/\r$//' "$ROOT/jobs/prepare.slurm"
echo "=== SLURM FILE ==="
file "$ROOT/jobs/prepare.slurm"

echo "=== PRE-FLIGHT: worktree must be clean, stage must be unused ==="
cd "$REPO" || exit 1
echo "dirty_files=$(git status --porcelain --untracked-files=all | wc -l) (want 0)"
D=$REPO/results/26_historical_band_experts/formal_v09
for p in "$D/authorizations/A09-NEST-01.authorization.json" "$D/strict_nesting" \
         "$D/R09-NEST-S100.legacy_checkpoint_bridge_external_audit.json"; do
  [ -e "$p" ] && echo "PRESENT(BAD) $(basename "$p")" || echo "absent(good) $(basename "$p")"
done

echo "=== SUBMIT ==="
cd "$ROOT/jobs"
JID=$(sbatch --parsable prepare.slurm 2>&1)
echo "jobid=$JID"

echo "=== WAIT (max 45 min) ==="
for i in $(seq 1 270); do
  ST=$(squeue -j "$JID" -h -o "%t" 2>/dev/null)
  [ -z "$ST" ] && { echo "finished at t=$((i*10))s"; break; }
  [ $((i % 6)) -eq 0 ] && echo "  t=$((i*10))s state=$ST"
  sleep 10
done

echo "=== ACCOUNTING ==="
sacct -j "$JID" -X --format=JobID%10,JobName%10,NodeList%9,State%12,ExitCode%8,Elapsed%10 2>&1

echo "=== STDOUT ==="
cat "$ROOT/logs/prep_${JID}.out" 2>&1 | tail -60

echo "=== STDERR (tail 30) ==="
tail -30 "$ROOT/logs/prep_${JID}.err" 2>&1

echo "=== DID THE TWO PREREQUISITE REPORTS APPEAR? ==="
for f in R09-NEST-S100.legacy_checkpoint_bridge_external_audit.json \
         R09-NEST-S100.training_resource_preflight_external_audit.json; do
  if [ -f "$D/$f" ]; then echo "OK  $f  sha256=$(sha256sum "$D/$f" | cut -c1-16)"; else echo "MISSING $f"; fi
done

echo "=== BRIDGE VERDICT (the number that decides go/no-go) ==="
"$HOME/miniconda3/envs/nh_final/bin/python" - <<'PY' 2>&1 | tail -12
import json, pathlib
p = pathlib.Path.home()/"v09_strict/neuralhydrology/results/26_historical_band_experts/formal_v09/R09-NEST-S100.legacy_checkpoint_bridge_external_audit.json"
if not p.is_file():
    print("no bridge report")
else:
    r = json.loads(p.read_text(encoding="utf-8"))
    for k in ("status","maximum_prediction_difference","run_count","real_panel_rows_total",
              "training_target_value_reads","formal_evaluation_observation_reads"):
        print(f"{k:38s} {r.get(k)}")
    print("legacy_dynamic_input_names            ", r.get("legacy_dynamic_input_names"))
    print("torch                                 ", r.get("environment_binding",{}).get("torch_version"))
    print("git_head                              ", r.get("environment_binding",{}).get("git_head"))
PY

echo "=== END ==="
