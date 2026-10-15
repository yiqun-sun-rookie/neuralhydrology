#!/bin/bash
set -o pipefail
# seq 3: per-package pip --target into OWN pysite (a failing wheel no longer blocks the rest), then import test
ROOT=/data1/home/sunyiq/openhydronet_531_20261015
date --iso-8601=seconds
source ~/miniconda3/etc/profile.d/conda.sh; conda activate nh_final || { echo CONDA_FAILED; exit 1; }
for P in zarr==3.1.5 numcodecs==0.16.5 dask==2025.12.0 cachey==0.2.1 toolz==1.2.0 cloudpickle==3.1.2 heapdict==1.0.1 \
         donfig==0.8.1.post1 pydantic==2.12.5 pydantic-core==2.41.5 annotated-types==0.8.0 typing-inspection==0.4.4 \
         more-itertools==10.8.0 partd==1.4.2 locket==1.0.0 google-crc32c==1.9.0 click==8.5.0; do
  if out=$(python -m pip install --no-input --no-deps --only-binary=:all: --target "$ROOT/pysite" "$P" 2>&1); then
    echo "OK    $P"
  else
    echo "FAIL  $P"; echo "$out" | grep -E "ERROR" | head -3 | cut -c1-300
  fi
done
export PYTHONPATH="$ROOT/pysite:$ROOT/src/flood-forecasting"
echo "=== import test ==="
python - <<'PY'
import importlib, sys
for m in ["zarr", "numcodecs", "dask", "cachey", "pydantic", "more_itertools", "googlehydrology.run", "googlehydrology.modelzoo", "googlehydrology.datasetzoo",
          "googlehydrology.training.train", "googlehydrology.evaluation", "googlehydrology.datasetzoo.multimet"]:
    try:
        x = importlib.import_module(m); print("OK     ", m, getattr(x, "__version__", ""))
    except Exception as e:
        print("FAIL   ", m, type(e).__name__, str(e)[:240])
PY
du -sh "$ROOT/pysite"
exit 0
