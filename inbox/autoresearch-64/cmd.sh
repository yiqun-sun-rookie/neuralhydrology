#!/bin/bash
set -o pipefail
source /data1/home/${USER}/miniconda3/etc/profile.d/conda.sh || exit 1
export CONDA_NO_PLUGINS=true

echo "=== A. create env (plugins disabled) ==="
conda env list | grep -qE "^autoresearch64\s" && echo "already exists" || conda create -y -n autoresearch64 python=3.11 2>&1 | tail -25

echo "=== B. confirm it exists ==="
conda env list | grep -E "autoresearch64|^base" 2>&1

echo "=== C. install pinned versions ==="
conda activate autoresearch64 || { echo "ACTIVATE_FAILED"; exit 1; }
python -V 2>&1
pip install "numpy==1.26.4" "pandas==2.3.3" "pyarrow==22.0.0" psutil pytest 2>&1 | tail -12

echo "=== D. verify against the declared pins ==="
python - <<'PY'
import importlib.metadata as md
want = {"numpy": "1.26.4", "pandas": "2.3.3", "pyarrow": "22.0.0"}
ok = True
for name, target in want.items():
    try: got = md.version(name)
    except Exception as e: got = f"MISSING({e})"
    if got != target: ok = False
    print(f"{'OK ' if got==target else 'MISMATCH'} {name}: declared {target}, installed {got}")
for extra in ("psutil", "pytest"):
    try: print(f"    {extra}: {md.version(extra)}")
    except Exception as e: print(f"    {extra}: MISSING")
print("CONTRACT_VERSIONS_MATCH" if ok else "CONTRACT_VERSIONS_DIFFER")
PY

echo "=== E. selection reproduces on HPC? ==="
cd ~/autoresearch64 || exit 1
PYTHONPATH=$(pwd)/src python -c "
import json,pathlib
from unified_autoresearch.selection.basins import select_development_basins
b=select_development_basins('src/fair_benchmark/frozen/bundle/track0_statics.csv','examples/06-Finetuning/531_basin_list.txt',count=64)
frozen=json.loads(pathlib.Path('src/unified_autoresearch/selection/development_basins_64_v1.json').read_text())['basins']
print('64-basin selection reproduces on HPC:', b==frozen)
" 2>&1 | tail -4

echo "=== F. nh_final untouched ==="
conda activate nh_final && python -c "import numpy,pandas,pyarrow;print('nh_final still:',numpy.__version__,pandas.__version__,pyarrow.__version__)" 2>&1 | tail -2
