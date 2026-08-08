#!/bin/bash
# conda is the toolchain that already works on this box (nh_final was built with it) and the
# tsinghua mirror is configured. pip failed because CentOS 7 glibc has no wheels for these pins.
set -o pipefail
source /data1/home/${USER}/miniconda3/etc/profile.d/conda.sh || exit 1
rm -rf ~/autoresearch64/.venv

echo "=== A. what can conda actually solve for the declared pins? ==="
conda create -y -n autoresearch64 --solver=classic -c conda-forge \
  python=3.11 numpy=1.26.4 pandas=2.3.3 "pyarrow=22.0.0" psutil pytest 2>&1 | tail -20

echo "=== B. env exists? ==="
conda env list | grep -E "autoresearch64" 2>&1 || echo "NOT CREATED"

echo "=== C. installed versions vs declared pins ==="
if conda env list | grep -qE "^autoresearch64\s"; then
  conda activate autoresearch64
  python -V 2>&1
  python - <<'PY'
import importlib.metadata as md
want = {"numpy": "1.26.4", "pandas": "2.3.3", "pyarrow": "22.0.0"}
ok = True
for name, target in want.items():
    try: got = md.version(name)
    except Exception: got = "MISSING"
    if got != target: ok = False
    print(f"{'OK ' if got==target else 'MISMATCH'} {name}: declared {target}, installed {got}")
for extra in ("psutil", "pytest"):
    try: print(f"    {extra}: {md.version(extra)}")
    except Exception: print(f"    {extra}: MISSING")
print("CONTRACT_VERSIONS_MATCH" if ok else "CONTRACT_VERSIONS_DIFFER")
PY
  echo "=== D. selection reproduces on HPC? ==="
  cd ~/autoresearch64 && PYTHONPATH=$(pwd)/src python -c "
import json,pathlib
from unified_autoresearch.selection.basins import select_development_basins
b=select_development_basins('src/fair_benchmark/frozen/bundle/track0_statics.csv','examples/06-Finetuning/531_basin_list.txt',count=64)
f64=json.loads(pathlib.Path('src/unified_autoresearch/selection/development_basins_64_v1.json').read_text())['basins']
f8=json.loads(pathlib.Path('src/unified_autoresearch/selection/development_basins_v1.json').read_text())['basins']
print('64 selection reproduces on HPC:', b==f64)
print('prefix equals frozen 8:', b[:8]==f8)
" 2>&1 | tail -4
else
  echo "SKIPPING C/D: env was not created"
fi

echo "=== E. nh_final untouched ==="
conda activate nh_final && python -c "import numpy,pandas,pyarrow;print('nh_final still:',numpy.__version__,pandas.__version__,pyarrow.__version__)" 2>&1 | tail -2
