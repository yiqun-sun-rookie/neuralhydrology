#!/usr/bin/env bash
#SBATCH -J id29_ar
#SBATCH -p hgpu4
#SBATCH -N 1
#SBATCH -n 1
#SBATCH --cpus-per-task=8
#SBATCH --gres=gpu:1
#SBATCH -t 72:00:00
#SBATCH -o /data1/home/sunyiq/nearing2022_da/logs/ar_%j.out
#SBATCH -e /data1/home/sunyiq/nearing2022_da/logs/ar_%j.err

# Nearing et al. 2022 reproduction, arm 2 of 3: autoregression, lag 1 day, 0% training holdout.
# 531 basins, 30 epochs, three forcing products (daymet + maurer_extended + nldas_extended), seed 0.
# Target: median NSE = 0.879
# Wall clock: measured 1.51 it/s x 6821 batches = ~75 min/epoch -> ~38 h for 30 epochs.
# The per-timestep python loop in ARLSTM is the bottleneck (~20x slower than CudaLSTM); a GPU upgrade does not help.
set -o pipefail
ROOT=/data1/home/sunyiq/nearing2022_da
PY=/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python

cd "$ROOT" || exit 1
export PYTHONPATH="$ROOT:$PYTHONPATH"
mkdir -p logs

echo "host=$(hostname) started=$(date -Is)"
$PY -c "import torch;print('gpu:',torch.cuda.get_device_name(0))"

$PY -m neuralhydrology.nh_run train \
    --config-file src/29_nearing2022_da_ar/configs/autoregression_531_lead1_holdout0.yml --gpu 0

echo "TRAIN_EXIT=$?"
RUN=$(ls -dt results/29_nearing2022_da_ar/nearing2022_autoregression_lead1_holdout0.0_seed0_* 2>/dev/null | head -1)
echo "run_dir=$RUN"

$PY -m neuralhydrology.nh_run evaluate --run-dir "$RUN" --period test --gpu 0
echo "EVAL_EXIT=$?"

$PY - <<PYEOF
import glob
import pandas as pd
fs = sorted(glob.glob("$RUN/test/*/test_metrics.csv"))
if fs:
    df = pd.read_csv(fs[-1], index_col=0)
    cols = [c for c in ['NSE','KGE','Alpha-NSE','Beta-NSE','Pearson-r','Peak-Timing','Missed-Peaks'] if c in df.columns]
    print("AUTOREGRESSION n=%d" % len(df))
    print(df[cols].median().round(4).to_string())
else:
    print("NO METRICS FILE")
PYEOF
echo "finished=$(date -Is)"
