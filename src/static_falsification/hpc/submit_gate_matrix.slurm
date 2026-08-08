#!/usr/bin/env bash
#SBATCH -J id17-gate
#SBATCH -p hgpu2p
#SBATCH -N 1
#SBATCH -n 1
#SBATCH --cpus-per-task=4
#SBATCH --gres=gpu:1
#SBATCH --exclude=ngu002
#SBATCH -t 48:00:00
#SBATCH --array=0-19%6
#SBATCH -o /data1/home/sunyiq/id17_film_gate/logs/17_entity_awareness_hypernet/gate_%A_%a.out
#SBATCH -e /data1/home/sunyiq/id17_film_gate/logs/17_entity_awareness_hypernet/gate_%A_%a.err
# never write --mem
# %6 caps concurrency at 6 so the co-running a02 campaign keeps its share of the partition.

set -eo pipefail

source /data1/home/${USER}/miniconda3/etc/profile.d/conda.sh || \
source $HOME/miniconda3/etc/profile.d/conda.sh
conda activate "${CONDA_ENV:-nh_final}" || { echo "[FATAL] conda activate failed"; exit 1; }

export MKL_THREADING_LAYER=GNU
export MKL_SERVICE_FORCE_INTEL=1

cd ${SLURM_SUBMIT_DIR}
export PYTHONPATH=$(pwd):$PYTHONPATH
IDEA="17_entity_awareness_hypernet"
mkdir -p "logs/${IDEA}" "results/${IDEA}"

# 20-cell matrix: index -> (fold, seed, model). Layout keeps the two arms of one
# (fold, seed) cell adjacent so a partial run still yields complete paired cells.
FOLDS=(0 1 2 3 4)
SEEDS=(0 1)
MODELS=(ea film)
I=${SLURM_ARRAY_TASK_ID}
MODEL=${MODELS[$(( I % 2 ))]}
SEED=${SEEDS[$(( (I / 2) % 2 ))]}
FOLD=${FOLDS[$(( I / 4 ))]}
EXP="gate_${MODEL}_fold${FOLD}_seed${SEED}"
CFG="src/static_falsification/configs/hpc_gate/${EXP}.yml"

echo "=========================================="
echo "[$(date)] ID17 gate matrix task ${I}: ${EXP}"
echo "[INFO] Job ${SLURM_ARRAY_JOB_ID}_${I} on $(hostname)"
echo "=========================================="
python -c "import torch;print(f'[INFO] torch {torch.__version__} cuda={torch.cuda.is_available()}')"

# --- pre-flight ---
[ -f "$CFG" ] || { echo "[FATAL] config missing: $CFG (run gen_configs.py first)"; exit 1; }
[ -d "data/camels_us/basin_mean_forcing/daymet" ] || { echo "[FATAL] daymet forcing dir missing"; exit 1; }
[ -f "src/static_falsification/data/fold${FOLD}_test.txt" ] || { echo "[FATAL] fold${FOLD} basin files missing"; exit 1; }

# --- resume-safe: skip training if this cell already finished ---
RUN_DIR=$(find runs -maxdepth 1 -type d -name "${EXP}_*" -printf '%T@ %p\n' 2>/dev/null | sort -n | tail -1 | cut -d' ' -f2)
if [ -n "$RUN_DIR" ] && [ -f "$RUN_DIR/model_epoch030.pt" ]; then
    echo "[INFO] epoch-30 checkpoint already present in $RUN_DIR — skipping training"
else
    T0=$(date +%s)
    python -u -m neuralhydrology.nh_run train --config-file "$CFG" --gpu 0
    echo "[TIMING] train 30 epochs: $(( $(date +%s) - T0 ))s"
    RUN_DIR=$(find runs -maxdepth 1 -type d -name "${EXP}_*" -printf '%T@ %p\n' | sort -n | tail -1 | cut -d' ' -f2)
fi
[ -n "$RUN_DIR" ] || { echo "[FATAL] no run dir found for ${EXP}"; exit 1; }

# --- verdict-epoch evaluation (protocol: epoch 30 on the held-out PUB basins) ---
for EP in 20 30; do
    if compgen -G "$RUN_DIR/test/model_epoch$(printf '%03d' $EP)/*_metrics.csv" > /dev/null; then
        echo "[INFO] epoch $EP already evaluated"
        continue
    fi
    python -u -m neuralhydrology.nh_run evaluate --run-dir "$RUN_DIR" --epoch $EP --period test --gpu 0
done

# --- post-run protocol check: the run must be the experiment we think it is ---
python - "$RUN_DIR" "$EXP" "$FOLD" "$SEED" <<'PY'
import sys, glob
from pathlib import Path
from ruamel.yaml import YAML
run_dir, exp, fold, seed = sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4])
cfg = YAML(typ='safe').load(open(Path(run_dir) / 'config.yml', encoding='utf-8'))
assert cfg['experiment_name'] == exp, f"experiment_name mismatch: {cfg['experiment_name']} != {exp}"
assert cfg['seed'] == seed, f"seed mismatch: {cfg['seed']} != {seed}"
assert f"fold{fold}_test.txt" in str(cfg['test_basin_file']), f"fold mismatch in {cfg['test_basin_file']}"
assert cfg['epochs'] == 30 and cfg['seq_length'] == 365 and cfg['loss'] == 'NSE'
if cfg['model'] == 'filmlstm':
    assert cfg.get('film_site') == 'input', f"film_site must be 'input', got {cfg.get('film_site')}"
print(f"[CHECK] protocol OK: {exp} model={cfg['model']} film_site={cfg.get('film_site')}")
import numpy as np, pandas as pd
for ep in (20, 30):
    f = glob.glob(f"{run_dir}/test/model_epoch{ep:03d}/*_metrics.csv")
    if f:
        print(f"[RESULT] {exp} epoch{ep} test median NSE = {float(np.nanmedian(pd.read_csv(f[0])['NSE'])):.4f}")
PY

echo "=========================================="
echo "[$(date)] task ${I} (${EXP}) done"
echo "=========================================="
