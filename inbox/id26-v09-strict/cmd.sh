#!/bin/bash
# id26-v09-strict seq=8 : give compute nodes a git, then re-submit the prepare gate.
# Creates an ISOLATED env at ~/v09_strict/gitenv. Does NOT touch nh_final
# (a02 and id05-adversarial are using nh_final; upgrading it could break their jobs).
export LC_ALL=C
ROOT=/data1/home/sunyiq/v09_strict
REPO=$ROOT/neuralhydrology
GITENV=$ROOT/gitenv

echo "=== A LOGIN NODE GIT ==="
echo "login git: $(command -v git) $(git --version 2>&1)"

echo "=== B ISOLATED GIT ENV ==="
if [ -x "$GITENV/bin/git" ]; then
  echo "already present: $($GITENV/bin/git --version)"
else
  source /data1/home/sunyiq/miniconda3/etc/profile.d/conda.sh
  echo "creating $GITENV (this can take a few minutes)"
  conda create -y -p "$GITENV" -c conda-forge git 2>&1 | tail -12
fi
if [ -x "$GITENV/bin/git" ]; then
  echo "OK  $($GITENV/bin/git --version)  at $GITENV/bin/git"
else
  echo "FAILED to provide git; stopping"; exit 1
fi

echo "=== C DOES IT SUPPORT THE FLAGS v09 NEEDS? ==="
cd "$REPO" || exit 1
"$GITENV/bin/git" rev-parse --path-format=absolute --git-common-dir 2>&1 | head -2
"$GITENV/bin/git" rev-parse HEAD 2>&1 | head -1
"$GITENV/bin/git" status --porcelain --untracked-files=all 2>&1 | wc -l

echo "=== D REWRITE SLURM WITH GIT ON PATH ==="
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

# compute nodes have no git; use the isolated env (nh_final untouched)
export PATH=/data1/home/sunyiq/v09_strict/gitenv/bin:$PATH

export MKL_THREADING_LAYER=GNU
export MKL_SERVICE_FORCE_INTEL=1

cd /data1/home/sunyiq/v09_strict/neuralhydrology
export PYTHONPATH=$(pwd):$PYTHONPATH

echo "node=$(hostname)"
echo "git=$(command -v git) $(git --version)"
nvidia-smi --query-gpu=index,name,memory.total,memory.free --format=csv,noheader
python -c "import torch,numpy,sys;print('py',sys.version.split()[0],'torch',torch.__version__,'numpy',numpy.__version__)"
free -g | sed -n 2p

echo "=== RUN PREPARE ==="
python -u src/26_historical_band_experts/prepare_formal_strict_stage_v09.py
SLURM
sed -i 's/\r$//' "$ROOT/jobs/prepare.slurm"

echo "=== E PRE-FLIGHT ==="
echo "dirty_files=$("$GITENV/bin/git" status --porcelain --untracked-files=all | wc -l) (want 0)"
D=$REPO/results/26_historical_band_experts/formal_v09
for p in "$D/authorizations/A09-NEST-01.authorization.json" "$D/strict_nesting" \
         "$D/R09-NEST-S100.legacy_checkpoint_bridge_external_audit.json"; do
  [ -e "$p" ] && echo "PRESENT(BAD) $(basename "$p")" || echo "absent(good) $(basename "$p")"
done

echo "=== F SUBMIT ==="
cd "$ROOT/jobs"
JID=$(sbatch --parsable prepare.slurm 2>&1)
echo "jobid=$JID"

echo "=== G WAIT (max 40 min) ==="
for i in $(seq 1 240); do
  ST=$(squeue -j "$JID" -h -o "%t" 2>/dev/null)
  [ -z "$ST" ] && { echo "finished at t=$((i*10))s"; break; }
  [ $((i % 6)) -eq 0 ] && echo "  t=$((i*10))s state=$ST"
  sleep 10
done

echo "=== H ACCOUNTING ==="
sacct -j "$JID" -X --format=JobID%10,JobName%10,NodeList%9,State%12,ExitCode%8,Elapsed%10 2>&1

echo "=== I STDOUT ==="
tail -40 "$ROOT/logs/prep_${JID}.out" 2>&1

echo "=== J STDERR (tail 25) ==="
tail -25 "$ROOT/logs/prep_${JID}.err" 2>&1

echo "=== K BRIDGE VERDICT ==="
"$HOME/miniconda3/envs/nh_final/bin/python" - <<'PY' 2>&1 | tail -14
import json, pathlib
p = pathlib.Path.home()/"v09_strict/neuralhydrology/results/26_historical_band_experts/formal_v09/R09-NEST-S100.legacy_checkpoint_bridge_external_audit.json"
if not p.is_file():
    print("NO BRIDGE REPORT")
else:
    r = json.loads(p.read_text(encoding="utf-8"))
    for k in ("status","maximum_prediction_difference","run_count","real_panel_rows_total",
              "training_target_value_reads","formal_evaluation_observation_reads"):
        print(f"{k:36s} {r.get(k)}")
    print("legacy_dynamic_input_names          ", r.get("legacy_dynamic_input_names"))
    print("torch                               ", r.get("environment_binding",{}).get("torch_version"))
PY

echo "=== END ==="
