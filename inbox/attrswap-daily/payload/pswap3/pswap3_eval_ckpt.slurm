#!/usr/bin/env bash
# Stage-3 E4 (PREREG_20260916 section 5.2, conditional): copy the 26 Stage-2 run directories INTO THIS ROOT
# (runs_s2_copy/, whole directory incl. train_data/), point their config.yml run_dir/train_dir/img_log_dir at the
# copies, register weight + scaler hashes, run the pipeline self-test (one copy re-evaluated at epoch 30 must match
# the Stage-2 test_metrics.csv within 1e-4 per basin), then evaluate the 8 reference copies at epochs 10 and 20
# FIRST (noise floors ep10/ep20 are registered before any candidate copy is parsed -- stop condition 5), then the 18
# candidate copies. The Stage-2 landing dir is read only. No backslash literals anywhere in this file.
#SBATCH -J pswap3_eval_ckpt
#SBATCH -p __PART__
#SBATCH -N 1
#SBATCH -n 1
#SBATCH --cpus-per-task=4
#SBATCH --gres=gpu:1
#SBATCH -t 05:00:00
#SBATCH -o /data1/home/sunyiq/precip_swap3_daily_2026_09/logs/slurm_%x_%j.out
#SBATCH -e /data1/home/sunyiq/precip_swap3_daily_2026_09/logs/slurm_%x_%j.err

set -eo pipefail
ROOT=/data1/home/sunyiq/precip_swap3_daily_2026_09
S2=/data1/home/sunyiq/precip_swap2_daily_2026_09
source /data1/home/${USER}/miniconda3/etc/profile.d/conda.sh || source $HOME/miniconda3/etc/profile.d/conda.sh
conda activate nh_final || { echo CONDA_FAILED; exit 1; }
export MKL_THREADING_LAYER=GNU
export MKL_SERVICE_FORCE_INTEL=1
export CUDA_DEVICE_ORDER=PCI_BUS_ID
cd "$ROOT"
export PYTHONPATH="$ROOT/code_1f9804e"
[ -f "$ROOT/logs/gate_ref.txt" ] || { echo "GATE MARKER MISSING: gate_ref.txt"; exit 3; }
echo "=== E4 on $(hostname) job $SLURM_JOB_ID $(date '+%F %T') ==="

echo "=== V18 checkpoint existence in the Stage-2 landing dir ==="
n10=$(ls $S2/runs/*_ep30/model_epoch010.pt 2>/dev/null | wc -l) || true; n20=$(ls $S2/runs/*_ep30/model_epoch020.pt 2>/dev/null | wc -l) || true
nsc=$(ls $S2/runs/*_ep30/train_data/train_data_scaler.yml 2>/dev/null | wc -l) || true
echo "model_epoch010=$n10 model_epoch020=$n20 scaler=$nsc (expect 26 each)"
[ "$n10" -eq 26 ] && [ "$n20" -eq 26 ] && [ "$nsc" -eq 26 ] || { echo "E4 NOT EXECUTABLE (V18)"; echo "E4 not executed: checkpoints $n10/$n20 scaler $nsc" > logs/e4_not_executed.txt; exit 0; }

echo "=== copy 26 run dirs -> runs_s2_copy/ and repoint config paths ==="
mkdir -p runs_s2_copy
python -u hpc_deploy/e4_copy_runs.py --src "$S2/runs" --dst "$ROOT/runs_s2_copy" --manifest logs/e4_copy_manifest.json

echo "=== pipeline self-test: re-evaluate one reference copy at epoch 30 ==="
rd=$(ls -d runs_s2_copy/ref_daymet_s100_* | head -1)
python -u -m neuralhydrology.nh_run evaluate --run-dir "$rd" --period test --epoch 30
python -u -c "
import pandas as pd, glob, numpy as np
a = pd.read_csv(glob.glob('$rd/test/model_epoch030/test_metrics.csv')[0], dtype={'basin': str}).set_index('basin')['NSE']
b = pd.read_csv(glob.glob('$S2/runs/ref_daymet_s100_*/test/model_epoch030/test_metrics.csv')[0], dtype={'basin': str}).set_index('basin')['NSE']
d = (a - b).abs().max()
print('self-test max |dNSE| =', d)
assert d < 1e-4, 'pipeline self-test failed'
" || { echo "SELF-TEST FAIL"; exit 1; }

# The noise floors ep10/ep20 are registered locally from the FIRST retrieval (reference copies only) before the
# candidate copies are retrieved: stop condition 5 is enforced on the retrieval / parsing side (PREREG 18.1).
echo "=== epochs 10/20: reference copies first (8), then candidates (18) ==="
for ep in 10 20; do
  for rd in $(ls -d runs_s2_copy/ref_daymet_s*_ep30); do
    python -u -m neuralhydrology.nh_run evaluate --run-dir "$rd" --period test --epoch $ep
  done
done
echo "REFERENCE COPIES EVALUATED AT 10/20 $(date '+%F %T')" > logs/e4_ref_done.txt
for ep in 10 20; do
  for rd in $(ls -d runs_s2_copy/pswap2_armP_*_ep30); do
    python -u -m neuralhydrology.nh_run evaluate --run-dir "$rd" --period test --epoch $ep
  done
done
n=$(ls runs_s2_copy/*_ep30/test/model_epoch010/test_metrics.csv runs_s2_copy/*_ep30/test/model_epoch020/test_metrics.csv 2>/dev/null | wc -l) || true
echo "evaluations produced: $n (expect 52)"
[ "$n" -eq 52 ] || { echo "E4 INCOMPLETE"; exit 1; }
echo "E4 OK $(date '+%F %T')" > logs/e4_done.txt
echo "=== E4 DONE ==="
