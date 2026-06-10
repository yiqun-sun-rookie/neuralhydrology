#!/usr/bin/env bash
# iter3 (Oudin+warmup) -> iter4 (Oudin+warmup+v2_wide bounds). Single "BATCH DONE".
set -u
cd "$(dirname "$0")/../../.." || exit 1
MANIFEST="src/xaj_global_pilot/configs/xaj_playbook_iter_subset_40.txt"
COMMON="--manifest $MANIFEST --workers 12 --trials 2000 --restarts 2 --pet-method oudin --warmup-year"

echo "[driver] === iter3: Oudin + warmup, bounds v1 ==="
python -X utf8 -m src.xaj_global_pilot.scripts.run_xaj_pdd_cma_repro_v01 \
  $COMMON --bounds-preset v1 --output-subdir iter3_oudin_warmup

echo "[driver] === iter4: Oudin + warmup, bounds v2_wide ==="
python -X utf8 -m src.xaj_global_pilot.scripts.run_xaj_pdd_cma_repro_v01 \
  $COMMON --bounds-preset v2_wide --output-subdir iter4_oudin_warmup_wide

echo "[driver] BATCH DONE (iter3/iter4 on disk)"
