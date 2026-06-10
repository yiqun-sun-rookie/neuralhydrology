#!/usr/bin/env bash
# Chained driver: wait for iter0 (already running) -> iter1 (PT) -> iter2 (PT+warmup).
# Emits a single "BATCH DONE" when all three big-lever runs are on disk.
set -u
cd "$(dirname "$0")/../../.." || exit 1
D="results/10_global_conceptual_model_benchmark/camels_us_531_repro_v01"
MANIFEST="src/xaj_global_pilot/configs/xaj_playbook_iter_subset_40.txt"
COMMON="--manifest $MANIFEST --workers 12 --trials 2000 --restarts 2"

echo "[driver] waiting for iter0 (39 basins)..."
until [ "$(ls $D/iter0_oudin_calfinal/*.csv 2>/dev/null | wc -l)" -ge 39 ]; do sleep 15; done
echo "[driver] iter0 complete."

echo "[driver] === iter1: PT PET, cal-final init ==="
python -X utf8 -m src.xaj_global_pilot.scripts.run_xaj_pdd_cma_repro_v01 \
  $COMMON --pet-method priestley_taylor --bounds-preset v1 \
  --output-subdir iter1_pt_calfinal

echo "[driver] === iter2: PT PET + warmup-year init ==="
python -X utf8 -m src.xaj_global_pilot.scripts.run_xaj_pdd_cma_repro_v01 \
  $COMMON --pet-method priestley_taylor --bounds-preset v1 --warmup-year \
  --output-subdir iter2_pt_warmup

echo "[driver] BATCH DONE (iter0/1/2 all on disk)"
