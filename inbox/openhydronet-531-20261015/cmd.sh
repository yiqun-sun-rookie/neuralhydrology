#!/bin/bash
set -o pipefail
# seq 24: per-basin NSE by time_step for the two ID18-protocol runs (reads the runs' test_results.zarr; writes only into own ROOT/results)
ROOT=/data1/home/sunyiq/openhydronet_531_20261015
P3="$HOME/hpc_mailbox/inbox/openhydronet-531-20261015/payload/v3"
date --iso-8601=seconds
mkdir -p "$ROOT/results"
source ~/miniconda3/etc/profile.d/conda.sh; conda activate nh_final || { echo CONDA_FAILED; exit 1; }
export PYTHONPATH="$ROOT/pysite"
for CFG in id18_cmal id18_nse; do
  RUN=$(ls -td "$ROOT"/runs/${CFG}_* 2>/dev/null | head -1)
  echo "=============== $CFG : $RUN"
  ls "$RUN" | head -20 | tr '\n' ' '; echo
  Z=$(ls -d "$RUN"/test/model_epoch0*/test_results.zarr 2>/dev/null | tail -1)
  echo "zarr=$Z"
  [ -n "$Z" ] || { echo "NO_TEST_RESULTS"; continue; }
  nice -n 10 python - "$Z" <<'PY'
import sys, xarray as xr
ds = xr.open_zarr(sys.argv[1], consolidated=False)
print({k: int(v) for k, v in ds.sizes.items()}, list(ds.data_vars))
PY
  nice -n 10 python "$P3/ohn_eval.py" "$Z" 1989-10-01 1999-09-30 "$ROOT/results/${CFG}_nse_by_step.csv" 2>&1 | grep -v -i warn
done
echo "=== CSV_BEGIN id18_cmal"; cut -d, -f1,3,5,7,9,11,13,15,17 "$ROOT/results/id18_cmal_nse_by_step.csv"; echo "=== CSV_END"
echo "=== CSV_BEGIN id18_nse"; cut -d, -f1,3,5,7,9,11,13,15,17 "$ROOT/results/id18_nse_nse_by_step.csv"; echo "=== CSV_END"
exit 0
