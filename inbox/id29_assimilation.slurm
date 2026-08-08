#!/usr/bin/env bash
#SBATCH -J id29_da
#SBATCH -p hgpu4
#SBATCH -N 1
#SBATCH -n 1
#SBATCH --cpus-per-task=8
#SBATCH --gres=gpu:1
#SBATCH -t 24:00:00
#SBATCH -o /data1/home/sunyiq/nearing2022_da/logs/da_%j.out
#SBATCH -e /data1/home/sunyiq/nearing2022_da/logs/da_%j.err

# Nearing et al. 2022 reproduction, arm 3 of 3: variational data assimilation, lag 1 day, 0% holdout.
# No training: reuses the weights of the finished simulation run. Target: median NSE = 0.862
# Measured on A40: ~40 s per basin over the 10-year test period -> ~6 h for 531 basins.
set -o pipefail
ROOT=/data1/home/sunyiq/nearing2022_da
PY=/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python

cd "$ROOT" || exit 1
export PYTHONPATH="$ROOT:$PYTHONPATH"

SIM=$(ls -dt results/29_nearing2022_da_ar/nearing2022_simulation_seed0_*/ 2>/dev/null | head -1)
if [ -z "$SIM" ]; then echo "FATAL: no finished simulation run found"; exit 1; fi
SIM=${SIM%/}
echo "host=$(hostname) started=$(date -Is)"
echo "simulation_run=$SIM"
ls "$SIM"/model_epoch030.pt >/dev/null 2>&1 || { echo "FATAL: $SIM has no model_epoch030.pt"; exit 1; }

$PY src/29_nearing2022_da_ar/scripts/make_assimilation_run.py \
    --simulation-run-dir "$SIM" --lead 1 --holdout 0.0 --overwrite
echo "MAKE_EXIT=$?"

DA=$(ls -dt results/29_nearing2022_da_ar/assimilation_lead_1_holdout_0.0_from_*/ 2>/dev/null | head -1)
DA=${DA%/}
echo "assimilation_run=$DA"

$PY -m neuralhydrology.nh_run evaluate --run-dir "$DA" --period test --data-assimilation --gpu 0
echo "EVAL_EXIT=$?"

echo "=== install comparison script (added after the code payload was shipped) ==="
mkdir -p src/29_nearing2022_da_ar/scripts
cp -f /data1/home/sunyiq/hpc_mailbox/inbox/id29_compare_to_paper.py src/29_nearing2022_da_ar/scripts/compare_to_paper.py && echo "  installed"

echo "=== HEADLINE TABLE vs PAPER ==="
AR=$(ls -dt results/29_nearing2022_da_ar/nearing2022_autoregression_*/ 2>/dev/null | head -1)
AR=${AR%/}
ARG=""
[ -n "$AR" ] && [ -d "$AR/test" ] && ARG="--autoregression $AR"
$PY src/29_nearing2022_da_ar/scripts/compare_to_paper.py \
    --simulation "$SIM" $ARG --assimilation "$DA" \
    --out results/29_nearing2022_da_ar/headline_table.csv 2>&1 | tail -25

echo "finished=$(date -Is)"
