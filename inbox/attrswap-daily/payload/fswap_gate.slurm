#!/usr/bin/env bash
# Gate job: build the two ERA5-Land forcing products, verify them, then a 5-basin 1-epoch smoke train.
# Any failure exits non-zero, which cancels the nine dependent training jobs (afterok).
#SBATCH -J fswap_gate
#SBATCH -p hgpu8
#SBATCH -N 1
#SBATCH -n 1
#SBATCH --cpus-per-task=8
#SBATCH --gres=gpu:1
#SBATCH --exclude=ngu201
#SBATCH -t 03:00:00
#SBATCH -o /data1/home/sunyiq/forcing_swap_daily_2026_09/logs/slurm_fswap_gate_%j.out
#SBATCH -e /data1/home/sunyiq/forcing_swap_daily_2026_09/logs/slurm_fswap_gate_%j.err

set -eo pipefail
ROOT=/data1/home/sunyiq/forcing_swap_daily_2026_09
source /data1/home/${USER}/miniconda3/etc/profile.d/conda.sh || source $HOME/miniconda3/etc/profile.d/conda.sh
conda activate nh_final || { echo "CONDA_FAILED"; exit 1; }
export MKL_THREADING_LAYER=GNU
export MKL_SERVICE_FORCE_INTEL=1
export CUDA_DEVICE_ORDER=PCI_BUS_ID
cd "$ROOT"
export PYTHONPATH="$ROOT/code_1f9804e"

echo "=== node $(hostname) job $SLURM_JOB_ID $(date '+%F %T') ==="
python -u -c "
import sys, torch, neuralhydrology
p = neuralhydrology.__file__
assert '/forcing_swap_daily_2026_09/code_1f9804e/' in p.replace('\\\\', '/'), 'WRONG CODE: ' + p
print('archived code OK:', p); print('torch', torch.__version__, 'cuda', torch.cuda.is_available())
" || exit 4

echo "=== BUILD + VERIFY ==="
# determinism check: if a previous attempt already wrote the products, snapshot them and compare afterwards
PREV=""
if [ -d "$ROOT/data_shadow/camels_us/basin_mean_forcing/era5l_caravan" ]; then
  PREV=$(mktemp)
  ( cd "$ROOT/data_shadow/camels_us/basin_mean_forcing" && find era5l_caravan era5l_caravan_pmaurer -type f \
    | LC_ALL=C sort | xargs sha256sum ) > "$PREV"
  echo "previous products present: $(wc -l < "$PREV") files, snapshot taken for a determinism check"
fi
python -u hpc_deploy/build_era5l_forcing.py \
  --maurer "$ROOT/data_shadow/camels_us/basin_mean_forcing/maurer" \
  --dest "$ROOT/data_shadow/camels_us/basin_mean_forcing" \
  --basins "$ROOT/basin_lists/basins_529.txt" \
  --report "$ROOT/logs/convert_verify.json"

if [ -n "$PREV" ]; then
  NOW=$(mktemp)
  ( cd "$ROOT/data_shadow/camels_us/basin_mean_forcing" && find era5l_caravan era5l_caravan_pmaurer -type f \
    | LC_ALL=C sort | xargs sha256sum ) > "$NOW"
  if diff -q "$PREV" "$NOW" >/dev/null; then
    echo "DETERMINISM OK: the rebuild reproduced all $(wc -l < "$NOW") product files byte-for-byte"
  else
    echo "DETERMINISM DIFFERS: $(diff "$PREV" "$NOW" | grep -c '^<') files changed -- investigate before trusting results"
    exit 5
  fi
  rm -f "$PREV" "$NOW"
fi

echo "=== SMOKE TRAIN (5 basins, 1 epoch, era5l_caravan) ==="
python -u -m neuralhydrology.nh_run train --config-file configs/fswap_smoke.yml
sd=$(ls -dt runs_smoke/fswap_smoke_* 2>/dev/null | head -1) || true
[ -n "$sd" ] || { echo "SMOKE RUN DIR NOT FOUND"; exit 1; }
grep -E "number_of_basins|forcings:" "$sd/output.log" || true
python -u -c "
import sys, yaml
c = yaml.safe_load(open('$sd/config.yml'))
assert c['forcings'] == ['era5l_caravan'], c['forcings']
print('smoke forcings OK:', c['forcings'], '| dynamic_inputs:', c['dynamic_inputs'])
"

echo "GATE OK $(date '+%F %T')" > "$ROOT/logs/gate.txt"
echo "=== GATE DONE ==="
