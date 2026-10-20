#!/bin/bash
set -o pipefail
# screening evaluation: per-basin NSE of the four tune_v* runs on the held-out window 2006-10-01..2008-09-30 (read-only on runs)
ROOT=/data1/home/sunyiq/openhydronet_531_20261015
P3="$HOME/hpc_mailbox/inbox/openhydronet-531-20261015/payload/v3"
date --iso-8601=seconds
source ~/miniconda3/etc/profile.d/conda.sh; conda activate nh_final || { echo CONDA_FAILED; exit 1; }
export PYTHONPATH="$ROOT/pysite"
mkdir -p "$ROOT/results"
for V in v0 v1 v2 v3; do
  D=$(ls -td "$ROOT"/runs/tune_${V}_* 2>/dev/null | head -1)
  Z=$(ls -d "$D"/test/model_epoch0*/test_results.zarr 2>/dev/null | tail -1)
  echo "=============== tune_$V : $(basename "$D")  zarr=${Z:+ok}${Z:-MISSING}"
  [ -n "$Z" ] || continue
  nice -n 10 python "$P3/ohn_eval.py" "$Z" 2006-10-01 2008-09-30 "$ROOT/results/tune_${V}_nse_by_step.csv" 2>&1 | grep -v -i warn | head -4
done
echo "=== CSV_BEGIN (basin, nse_0 of v0 v1 v2 v3)"
paste -d, <(cut -d, -f1,3 "$ROOT/results/tune_v0_nse_by_step.csv") <(cut -d, -f3 "$ROOT/results/tune_v1_nse_by_step.csv") <(cut -d, -f3 "$ROOT/results/tune_v2_nse_by_step.csv") <(cut -d, -f3 "$ROOT/results/tune_v3_nse_by_step.csv")
echo "=== CSV_END"
exit 0
