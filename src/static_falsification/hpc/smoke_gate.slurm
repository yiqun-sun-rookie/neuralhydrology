#!/usr/bin/env bash
#SBATCH -J id17-smoke
#SBATCH -p hgpu2p
#SBATCH -N 1
#SBATCH -n 1
#SBATCH --cpus-per-task=4
#SBATCH --gres=gpu:1
#SBATCH --exclude=ngu002
#SBATCH -t 01:00:00
#SBATCH -o /data1/home/sunyiq/id17_film_gate/logs/17_entity_awareness_hypernet/smoke-%j.out
#SBATCH -e /data1/home/sunyiq/id17_film_gate/logs/17_entity_awareness_hypernet/smoke-%j.err
# never write --mem (platform allocates memory per node/card)

set -eo pipefail          # never -u: it kills conda activate and breaks bash 4.2 array expansion

source /data1/home/${USER}/miniconda3/etc/profile.d/conda.sh || \
source $HOME/miniconda3/etc/profile.d/conda.sh
conda activate "${CONDA_ENV:-nh_final}" || { echo "[FATAL] conda activate failed"; exit 1; }

export MKL_THREADING_LAYER=GNU
export MKL_SERVICE_FORCE_INTEL=1

cd ${SLURM_SUBMIT_DIR}
export PYTHONPATH=$(pwd):$PYTHONPATH
IDEA="17_entity_awareness_hypernet"
mkdir -p "logs/${IDEA}" "results/${IDEA}"

echo "=========================================="
echo "[$(date)] ID17 gate SMOKE TEST (both arms, 2 epochs, 20 train basins)"
echo "[INFO] Job $SLURM_JOB_ID on $(hostname)"
echo "=========================================="
python -c "import torch;print(f'[INFO] torch {torch.__version__} cuda={torch.cuda.is_available()} dev={torch.cuda.get_device_name(0) if torch.cuda.is_available() else None}')"

# --- pre-flight: data dir, basin files, model import (silent-failure sources) ---
[ -d "data/camels_us/basin_mean_forcing/daymet" ] || { echo "[FATAL] daymet forcing dir missing"; exit 1; }
[ -d "data/camels_us/camels_attributes_v2.0" ] || { echo "[FATAL] attributes dir missing"; exit 1; }
[ -f "src/static_falsification/data/fold0_train.txt" ] || { echo "[FATAL] fold0 basin file missing"; exit 1; }
python -c "from neuralhydrology.modelzoo.filmlstm import FiLMLSTM; print('[INFO] FiLMLSTM import OK')" \
    || { echo "[FATAL] FiLMLSTM import failed"; exit 1; }

# 20-basin training subset for the smoke run
head -20 src/static_falsification/data/fold0_train.txt > src/static_falsification/data/smoke20.txt
python src/static_falsification/hpc/gen_configs.py

for CFG in src/static_falsification/configs/hpc_smoke/smoke_ea_fold0_seed0.yml \
           src/static_falsification/configs/hpc_smoke/smoke_film_fold0_seed0.yml; do
    echo "------------------------------------------"
    echo "[$(date)] TRAIN $CFG"
    T0=$(date +%s)
    python -u -m neuralhydrology.nh_run train --config-file "$CFG" --gpu 0
    echo "[TIMING] $(basename $CFG) train 2 epochs: $(( $(date +%s) - T0 ))s"

    EXP=$(basename "$CFG" .yml)
    RUN_DIR=$(find runs -maxdepth 1 -type d -name "${EXP}_*" -printf '%T@ %p\n' | sort -n | tail -1 | cut -d' ' -f2)
    echo "[$(date)] EVALUATE $RUN_DIR"
    T1=$(date +%s)
    python -u -m neuralhydrology.nh_run evaluate --run-dir "$RUN_DIR" --epoch 2 --period test --gpu 0
    echo "[TIMING] $(basename $CFG) test eval: $(( $(date +%s) - T1 ))s"
    python - "$RUN_DIR" <<'PY'
import sys, glob, numpy as np, pandas as pd
f = glob.glob(f"{sys.argv[1]}/test/model_epoch002/*_metrics.csv")
print("[RESULT]", sys.argv[1].split('/')[-1], "median NSE =",
      round(float(np.nanmedian(pd.read_csv(f[0])["NSE"])), 4) if f else "NO METRICS")
PY
done

echo "=========================================="
echo "[$(date)] SMOKE DONE"
scontrol show job $SLURM_JOB_ID | head -20
echo "=========================================="
