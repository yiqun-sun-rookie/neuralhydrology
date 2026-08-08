#!/bin/bash
# Build a dedicated env matching the frozen candidate contract. nh_final is NOT touched.
set -o pipefail
source /data1/home/${USER}/miniconda3/etc/profile.d/conda.sh || exit 1

echo "=== A. does the env already exist? ==="
conda env list | grep -E "^autoresearch64\s" && { echo "already exists, skipping create"; } || {
  echo "creating..."
  conda create -y -q -n autoresearch64 python=3.11 2>&1 | tail -5
}

echo "=== B. install the pinned contract versions ==="
conda activate autoresearch64 || { echo "ACTIVATE_FAILED"; exit 1; }
python -V
pip install -q "numpy==1.26.4" "pandas==2.3.3" "pyarrow==22.0.0" 2>&1 | tail -8
pip install -q psutil pytest 2>&1 | tail -4

echo "=== C. verify versions match the declared pins ==="
python - <<'PY'
import importlib.metadata as md
want = {"numpy": "1.26.4", "pandas": "2.3.3", "pyarrow": "22.0.0"}
ok = True
for name, target in want.items():
    got = md.version(name)
    flag = "OK " if got == target else "MISMATCH"
    if got != target: ok = False
    print(f"{flag} {name}: declared {target}, installed {got}")
for extra in ("psutil", "pytest"):
    print(f"    {extra}: {md.version(extra)}")
print("CONTRACT_VERSIONS_MATCH" if ok else "CONTRACT_VERSIONS_DIFFER")
PY

echo "=== D. package imports under the new env ==="
cd ~/autoresearch64 || exit 1
PYTHONPATH=$(pwd)/src python -c "
from unified_autoresearch.selection.basins import select_development_basins
b=select_development_basins('src/fair_benchmark/frozen/bundle/track0_statics.csv','examples/06-Finetuning/531_basin_list.txt',count=64)
import json,pathlib
frozen=json.loads(pathlib.Path('src/unified_autoresearch/selection/development_basins_64_v1.json').read_text())['basins']
print('64-basin selection reproduces on HPC:', b==frozen)
print('first three:', b[:3])
" 2>&1 | tail -6

echo "=== E. nh_final untouched? ==="
conda activate nh_final && python -c "import numpy,pandas,pyarrow;print('nh_final still:',numpy.__version__,pandas.__version__,pyarrow.__version__)" 2>&1 | tail -2
