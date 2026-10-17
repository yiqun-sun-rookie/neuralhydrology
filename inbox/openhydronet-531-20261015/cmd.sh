#!/bin/bash
set -o pipefail
# seq 27: (a) ensemble of the five NSE-loss ID18 runs, (b) the native CAMELS-531 run with real HRES/GraphCast forecasts
ROOT=/data1/home/sunyiq/openhydronet_531_20261015
P4="$HOME/hpc_mailbox/inbox/openhydronet-531-20261015/payload/v4"
date --iso-8601=seconds
[ -f "$P4/ohn_ens_eval.py" ] || { echo "MISSING payload ohn_ens_eval.py"; exit 1; }
source ~/miniconda3/etc/profile.d/conda.sh; conda activate nh_final || { echo CONDA_FAILED; exit 1; }
export PYTHONPATH="$ROOT/pysite"
mkdir -p "$ROOT/results"

echo "=============== (a) ID18-protocol NSE-loss ensemble"
ZS=""
for D in "$ROOT"/runs/id18_nse_[0-9]* "$ROOT"/runs/id18_nse_s101_* "$ROOT"/runs/id18_nse_s102_* "$ROOT"/runs/id18_nse_s103_* "$ROOT"/runs/id18_nse_s104_*; do
  Z=$(ls -d "$D"/test/model_epoch0*/test_results.zarr 2>/dev/null | tail -1)
  echo "member: $(basename "$D")  ->  ${Z:+found}${Z:-MISSING}"
  [ -n "$Z" ] && ZS="$ZS $Z"
done
nice -n 10 python "$P4/ohn_ens_eval.py" 1989-10-01 1999-09-30 "$ROOT/results/id18_nse_ens5" $ZS 2>&1 | grep -v -i warn

echo "=============== (b) native CAMELS-531 run (2021-2025, real HRES + GraphCast forecasts)"
D=$(ls -td "$ROOT"/runs/native531_* | head -1); echo "run: $D"
Z=$(ls -d "$D"/test/model_epoch0*/test_results.zarr 2>/dev/null | tail -1); echo "zarr: $Z"
if [ -n "$Z" ]; then nice -n 10 python "$P4/ohn_ens_eval.py" 2021-01-01 2025-12-31 "$ROOT/results/native531" "$Z" 2>&1 | grep -v -i warn; else echo NO_TEST_RESULTS; fi

echo "=== CSV_BEGIN id18_nse_ens5 (basin, ens, members at time_step 0)"
cut -d, -f1-7 "$ROOT/results/id18_nse_ens5_per_basin.csv"
echo "=== CSV_END"
exit 0
