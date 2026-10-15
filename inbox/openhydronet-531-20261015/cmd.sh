#!/bin/bash
set -o pipefail
# seq 2: clone pinned source, install missing pure/manylinux2014 wheels into OWN pysite, itertools.batched shim, py3.11 compile + import test
ROOT=/data1/home/sunyiq/openhydronet_531_20261015
date --iso-8601=seconds
source ~/miniconda3/etc/profile.d/conda.sh; conda activate nh_final || { echo CONDA_FAILED; exit 1; }
cd "$ROOT/src"
if [ ! -d flood-forecasting/.git ]; then timeout 900 git clone -q https://github.com/google-research/flood-forecasting.git flood-forecasting || { echo CLONE_FAILED; exit 1; }; fi
cd flood-forecasting && git checkout -q 011265446e113cf849394efe6514221dc7c3f124 && git rev-parse HEAD && git status --porcelain | wc -l
echo "=== pip --target (own pysite only) ==="
python -m pip install --no-input --no-deps --only-binary=:all: --target "$ROOT/pysite"   zarr==3.1.5 numcodecs==0.17.0 dask==2025.12.0 cachey==0.2.1 toolz==1.2.0 cloudpickle==3.1.2 heapdict==1.0.1   donfig==0.8.1.post1 pydantic==2.12.5 pydantic-core==2.41.5 annotated-types==0.8.0 typing-inspection==0.4.4   more-itertools==10.8.0 partd==1.4.2 locket==1.0.0 google-crc32c==1.9.0 click==8.5.0 2>&1 | tail -6
cat > "$ROOT/pysite/sitecustomize.py" <<'PY'
# Python 3.11 shim: itertools.batched exists only from 3.12 (googlehydrology uses it). Semantics per the 3.12 docs.
import itertools
if not hasattr(itertools, "batched"):
    def batched(iterable, n):
        if n < 1:
            raise ValueError("n must be at least one")
        it = iter(iterable)
        while batch := tuple(itertools.islice(it, n)):
            yield batch
    itertools.batched = batched
PY
export PYTHONPATH="$ROOT/pysite:$ROOT/src/flood-forecasting"
echo "=== compile all under py3.11 ==="
cd "$ROOT/src/flood-forecasting" && python -m compileall -q googlehydrology multimet 2>&1 | head -20; echo "compileall rc=$?"
echo "=== import test ==="
python - <<'PY'
import itertools, importlib, sys
print(sys.version.split()[0], "batched:", hasattr(itertools, "batched"))
for m in ["zarr", "dask", "cachey", "pydantic", "more_itertools", "googlehydrology.run", "googlehydrology.modelzoo", "googlehydrology.datasetzoo", "googlehydrology.training.train", "googlehydrology.evaluation"]:
    try:
        x = importlib.import_module(m); print("OK     ", m, getattr(x, "__version__", ""))
    except Exception as e:
        print("FAIL   ", m, type(e).__name__, str(e)[:200])
PY
du -sh "$ROOT/pysite" "$ROOT/src"
exit 0
