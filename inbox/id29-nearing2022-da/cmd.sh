#!/bin/bash
# ID29 seq=70: install direct basin-evaluation repair and submit its 20 registered coordinates.
set -eo pipefail

ROOT=/data1/home/sunyiq/nearing2022_da
PAYLOAD=/data1/home/sunyiq/hpc_mailbox/payload/id29-nearing2022-da/closure_v6.tar.gz
EXPECTED_PAYLOAD_SHA=ba4e55117d882eb7b763b74545f8c8ff61a6dcc425df6228ef23b232002fb743
SCRIPT="$ROOT/src/29_nearing2022_da_ar/hpc/run_registered_evaluation_array.slurm"
REGISTRY="$ROOT/src/29_nearing2022_da_ar/registry/evaluation_registry.csv"
BATCH="$ROOT/src/29_nearing2022_da_ar/registry/basin_direct_evaluation_batch.txt"
PREPARE="$ROOT/src/29_nearing2022_da_ar/scripts/prepare_evaluation_run.py"
BUILDER="$ROOT/src/29_nearing2022_da_ar/scripts/build_evaluation_registry.py"

echo "=== PAYLOAD ==="
echo "$EXPECTED_PAYLOAD_SHA  $PAYLOAD" | sha256sum -c -
test "$(tar -tzf "$PAYLOAD" | wc -l)" -eq 3
tar -xzf "$PAYLOAD" -C "$ROOT"

echo "=== PREFLIGHT ==="
test -f "$SCRIPT"
test -f "$REGISTRY"
test -f "$BATCH"
test -f "$PREPARE"
test -f "$BUILDER"
echo "ac1f34e12c7238a2dd37de936af18436a6d36d2d1812672b103ac7654f1d8974  $BUILDER" | sha256sum -c -
echo "6e47896c2b3011fe8e93a561f7545397d5a4ddee70b09b38a520f08530646ccf  $PREPARE" | sha256sum -c -
echo "f207192124c07c28369be3a5656a6a55c6fd332595c92eca5b46d81916206d9e  $BATCH" | sha256sum -c -
test "$(wc -l < "$BATCH")" -eq 20
test "$(sort -u "$BATCH" | wc -l)" -eq 20

source ~/miniconda3/etc/profile.d/conda.sh
conda activate nh_final
cd "$ROOT"
export PYTHONPATH="$ROOT${PYTHONPATH:+:$PYTHONPATH}"
python - <<'PY'
from pathlib import Path
import sys
import pandas as pd

root = Path('/data1/home/sunyiq/nearing2022_da')
sys.path.insert(0, str(root / 'src/29_nearing2022_da_ar/scripts'))
from build_evaluation_registry import build_batches, build_hyperparameter_registry

registry = pd.read_csv(root / 'src/29_nearing2022_da_ar/registry/evaluation_registry.csv', keep_default_na=False, dtype=str)
expected = build_batches(registry, build_hyperparameter_registry())['basin_direct_evaluation_batch.txt']
actual = tuple(line.strip() for line in (root / 'src/29_nearing2022_da_ar/registry/basin_direct_evaluation_batch.txt').read_text().splitlines() if line.strip())
if actual != expected:
    raise SystemExit('Direct basin evaluation batch does not match the frozen registry')
print(f'direct_coordinates={len(actual)}')
PY

if squeue -h -u "$USER" -n N22-eval-bs-direct | grep -q .; then
  echo "Refusing duplicate direct basin evaluation submission" >&2
  squeue -u "$USER" -n N22-eval-bs-direct
  exit 3
fi

echo "=== SUBMIT ==="
DIRECT_JOB=$(sbatch --parsable \
  --job-name=N22-eval-bs-direct \
  --array=0-19%2 \
  --dependency=afterok:202216 \
  --export=ALL,REGISTRY_REL=src/29_nearing2022_da_ar/registry/evaluation_registry.csv,BATCH_FILE_REL=src/29_nearing2022_da_ar/registry/basin_direct_evaluation_batch.txt,REGISTRY_KIND=evaluation \
  "$SCRIPT")
scontrol update JobId=202229 Dependency=afterok:202222:202226:202216:"$DIRECT_JOB":202227
echo "direct_basin_evaluation_job_id=$DIRECT_JOB dependency=afterok:202216"
squeue -j "$DIRECT_JOB,202229" -o '%.18i %.24j %.2t %.10M %.6D %R'
scontrol show job -o 202229 | sed -n 's/.*Dependency=\([^ ]*\).*/aggregation_dependency=\1/p'
