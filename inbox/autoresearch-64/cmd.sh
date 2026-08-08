#!/bin/bash
# venv instead of conda: fewer moving parts, and it leaves the user's conda config alone.
set -o pipefail
source /data1/home/${USER}/miniconda3/etc/profile.d/conda.sh || exit 1
conda activate nh_final || { echo "BASE_ACTIVATE_FAILED"; exit 1; }

VENV=~/autoresearch64/.venv
echo "=== A. base interpreter ==="
python -V 2>&1

echo "=== B. create venv ==="
if [ -d "$VENV" ]; then echo "venv already exists, reusing"; else python -m venv "$VENV" 2>&1 | tail -5; fi
[ -x "$VENV/bin/python" ] || { echo "VENV_CREATE_FAILED"; ls -la "$VENV" 2>&1 | head; exit 1; }
"$VENV/bin/python" -V 2>&1

echo "=== C. install pinned contract versions ==="
"$VENV/bin/python" -m pip install -q --upgrade pip 2>&1 | tail -3
"$VENV/bin/python" -m pip install "numpy==1.26.4" "pandas==2.3.3" "pyarrow==22.0.0" psutil pytest 2>&1 | tail -10

echo "=== D. verify against declared pins ==="
"$VENV/bin/python" - <<'PY'
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

echo "=== E. selection reproduces on HPC? ==="
cd ~/autoresearch64 || exit 1
PYTHONPATH=$(pwd)/src "$VENV/bin/python" -c "
import json,pathlib
from unified_autoresearch.selection.basins import select_development_basins
b=select_development_basins('src/fair_benchmark/frozen/bundle/track0_statics.csv','examples/06-Finetuning/531_basin_list.txt',count=64)
frozen=json.loads(pathlib.Path('src/unified_autoresearch/selection/development_basins_64_v1.json').read_text())['basins']
print('64-basin selection reproduces on HPC:', b==frozen)
print('prefix equals frozen 8:', b[:8]==json.loads(pathlib.Path('src/unified_autoresearch/selection/development_basins_v1.json').read_text())['basins'])
" 2>&1 | tail -5

echo "=== F. venv must stay out of the workspace git index ==="
grep -q "^\.venv/" .gitignore || printf '.venv/\n' >> .gitignore
git add .gitignore && git commit -q -m "ignore the local virtual environment" 2>&1 | tail -2
git status --porcelain | wc -l
