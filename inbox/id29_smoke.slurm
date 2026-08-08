#!/usr/bin/env bash
#SBATCH -J id29_smoke
#SBATCH -p hgpu4
#SBATCH -N 1
#SBATCH -n 1
#SBATCH --cpus-per-task=4
#SBATCH --gres=gpu:1
#SBATCH -t 00:30:00
#SBATCH -o /data1/home/sunyiq/hpc_mailbox/outbox/slurm_%j.out
#SBATCH -e /data1/home/sunyiq/hpc_mailbox/outbox/slurm_%j.err

set -o pipefail
ROOT=/data1/home/sunyiq/nearing2022_da
PY=/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python

cd "$ROOT" || exit 1
export PYTHONPATH="$ROOT:$PYTHONPATH"

echo "host=$(hostname) gpu=$CUDA_VISIBLE_DEVICES"
$PY -c "import torch;print('torch',torch.__version__,'cuda_ok',torch.cuda.is_available(),torch.cuda.get_device_name(0))"

# 6-basin, 1-epoch smoke against the real reproduction config: proves the extended forcings load,
# the assimilation code imports, and the three arms run on this cluster.
head -6 src/29_nearing2022_da_ar/basin_lists/531_basin_list.txt > /tmp/id29_smoke_basins.txt

$PY - <<'PYEOF'
import re
from pathlib import Path
t = Path('src/29_nearing2022_da_ar/configs/simulation_531.yml').read_text(encoding='utf-8')
t = re.sub(r'^experiment_name: .*$', 'experiment_name: hpc_smoke', t, flags=re.M)
t = re.sub(r'^run_dir: .*$', 'run_dir: runs_smoke', t, flags=re.M)
t = re.sub(r'^(train|validation|test)_basin_file: .*$', r'\1_basin_file: /tmp/id29_smoke_basins.txt', t, flags=re.M)
t = re.sub(r'^epochs: 30$', 'epochs: 1', t, flags=re.M)
t = re.sub(r'^validate_every: 30$', 'validate_every: 1', t, flags=re.M)
t = re.sub(r'^num_workers: 4$', 'num_workers: 2', t, flags=re.M)
Path('/tmp/id29_smoke.yml').write_text(t, encoding='utf-8')
print('smoke config written')
PYEOF

echo "=== TRAIN ==="
$PY -m neuralhydrology.nh_run train --config-file /tmp/id29_smoke.yml --gpu 0 2>&1 | tail -6

RUN=$(ls -dt runs_smoke/hpc_smoke_* 2>/dev/null | head -1)
echo "run_dir=$RUN"

echo "=== EVALUATE (open loop) ==="
$PY -m neuralhydrology.nh_run evaluate --run-dir "$RUN" --period test --gpu 0 2>&1 | tail -3

echo "=== ASSIMILATION ==="
$PY src/29_nearing2022_da_ar/scripts/make_assimilation_run.py \
    --simulation-run-dir "$RUN" --lead 1 --holdout 0.0 --overwrite 2>&1 | head -2
DA=$(ls -dt runs_smoke/assimilation_lead_1_* 2>/dev/null | head -1)
$PY -m neuralhydrology.nh_run evaluate --run-dir "$DA" --period test --data-assimilation --gpu 0 2>&1 | tail -3

echo "=== METRICS ==="
$PY - <<'PYEOF'
import glob
import pandas as pd
for label, pat in [('sim', 'runs_smoke/hpc_smoke_*/test/*/test_metrics.csv'),
                   ('da ', 'runs_smoke/assimilation_lead_1_*/test/*/test_metrics_data_assimilation.csv')]:
    fs = glob.glob(pat)
    if not fs:
        print(f'{label}: NO METRICS FILE ({pat})')
        continue
    df = pd.read_csv(sorted(fs)[-1], index_col=0)
    print(f'{label}: n={len(df)}  median NSE={df["NSE"].median():.4f}  KGE={df["KGE"].median():.4f}')
PYEOF
echo "=== DONE ==="
