#!/bin/bash
# Unpack the payload and probe whether the fsl model code runs under the stock nh_final
# (numpy 2.3.3 / scipy 1.16.2). Login node: unpack + import only, NO model computation.
set -o pipefail

ROOT=~/kuwei_paired
SRC=~/hpc_mailbox/payload/kuwei-paired-recal/v1
mkdir -p $ROOT/fsl $ROOT/laos

echo "=== A. payload integrity ==="
cd $SRC && sha256sum -c bundle_manifest.sha256 2>&1 | head -5 || true

echo "=== B. unpack ==="
tar -xzf $SRC/fsl_code.tar.gz  -C $ROOT/fsl  && echo "fsl unpacked"  || echo "fsl FAILED"
tar -xzf $SRC/laos_code.tar.gz -C $ROOT/laos && echo "laos unpacked" || echo "laos FAILED"
echo "fsl top: $(ls $ROOT/fsl | tr '\n' ' ')"
echo "laos top: $(ls $ROOT/laos | tr '\n' ' ')"

echo "=== C. key files present with expected sizes ==="
for f in \
  $ROOT/fsl/src/runtime/semi_distributed/core/optimize_eval.py \
  $ROOT/fsl/src/runtime/semi_distributed/core/dataio.py \
  $ROOT/fsl/src/kernels/semi_distributed/core/hydromod_numba.py \
  $ROOT/fsl/scripts/event_peak_evaluation.py \
  $ROOT/fsl/basins/namou_kuwei/data/full/sub_area.csv \
  $ROOT/laos/basins/namou_kuwei/dl/highflow_2026_06_17/results/continuous_rainfall_qualification_20260824/grid_hybrid_current.csv \
  $ROOT/laos/data/03_final/namou_kuwei/discharge_clean.csv ; do
  if [ -f "$f" ]; then echo "OK   $(stat -c%s "$f" | numfmt --to=iec) $(basename $f)"; else echo "MISS $f"; fi
done

echo "=== D. verify the two arm inputs survived transfer bit-for-bit ==="
cd $ROOT/laos/basins/namou_kuwei/dl/highflow_2026_06_17/results/continuous_rainfall_qualification_20260824 2>/dev/null && \
  sha256sum grid_hybrid_current.csv grid_hybrid_suspect_excluded.csv 2>&1 | head -4 || true
echo "expected current : 58f3221e00451a63090e54c2adcd0fa668021bfe0f5b024f46216b72b3f6a0f5"
echo "expected excluded: 34868836c259c0967747ad023fe47c7755bb8b6630d38c1427bac4ef867588f1"

echo "=== E. can the stock env import the model chain at all? ==="
source /data1/home/${USER}/miniconda3/etc/profile.d/conda.sh 2>/dev/null || true
conda activate nh_final 2>/dev/null || echo "(activate failed)"
cd $ROOT/fsl
PYTHONPATH=$ROOT/fsl python - <<'PY' 2>&1 | tail -25
import sys, traceback
print("python", sys.version.split()[0])
import numpy, scipy, pandas, numba
print("numpy", numpy.__version__, "| scipy", scipy.__version__, "| numba", numba.__version__)
mods = [
 "src.runtime.semi_distributed.core.optimization_config",
 "src.runtime.semi_distributed.core.dataio",
 "src.runtime.semi_distributed.core.optimizer_facade",
 "src.runtime.semi_distributed.core.optimize_eval",
 "src.runtime.semi_distributed.entry_points",
 "src.kernels.semi_distributed.core.hydromod_numba",
 "src.kernels.semi_distributed.core.simulate_flood_distributed_fast",
]
ok = 0
for m in mods:
    try:
        __import__(m); print("IMPORT OK  ", m); ok += 1
    except Exception as e:
        print("IMPORT FAIL", m, "->", type(e).__name__, str(e)[:160])
print(f"RESULT {ok}/{len(mods)} imports succeeded")
PY

echo "=== F. compute-node OS/glibc (where the real run must happen) ==="
srun -p hcpu48 -n1 -t 00:02:00 bash -c 'echo NODE=$(hostname); cat /etc/redhat-release 2>/dev/null; ldd --version | head -1; grep -m1 "model name" /proc/cpuinfo' 2>&1 | head -8 || echo "(srun probe failed)"

echo "=== DONE ==="
