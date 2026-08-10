#!/bin/bash
# ID29 seq=97: read-only inventory of existing Python environments after job 202365 showed pytest missing from nh_final.
set -eo pipefail

ROOT=/data1/home/sunyiq/nearing2022_da

echo "=== CONDA ENVIRONMENTS ==="
source ~/miniconda3/etc/profile.d/conda.sh
conda env list

echo "=== PYTHON CAPABILITY MATRIX ==="
for python_executable in ~/miniconda3/bin/python ~/miniconda3/envs/*/bin/python; do
  if [ ! -x "$python_executable" ]; then
    continue
  fi
  "$python_executable" - "$python_executable" <<'PY'
import importlib.util
import json
import sys

modules = ('pytest', 'numpy', 'pandas', 'scipy', 'torch', 'xarray', 'yaml')
payload = {
    'python': sys.argv[1],
    'version': sys.version.split()[0],
    'modules': {name: importlib.util.find_spec(name) is not None for name in modules},
}
print(json.dumps(payload, sort_keys=True))
PY
done

echo "=== EXISTING PYTEST ENTRYPOINTS ==="
find ~/miniconda3 -maxdepth 4 -type f -path '*/bin/pytest' -print | sort || true

echo "=== FAILED JOB LOG HASHES ==="
sha256sum \
  "$ROOT/closure_20260810/logs/N22-preclosure-check_202365.out" \
  "$ROOT/closure_20260810/logs/N22-preclosure-check_202365.err"

echo "=== SAFETY BOUNDARY ==="
test "$(squeue -h -j 202293 -o '%i|%T|%r|%j')" = "202293|PENDING|JobHeldUser|N22-manifest"
test "$(squeue -h -j 202315 -o '%i|%T|%r|%j')" = "202315|PENDING|Dependency|N22-gate"
test ! -e "$ROOT/closure_20260810/aggregation/final_reproduction_gate.json"
test ! -e "$ROOT/closure_20260810/aggregation/final_reproduction_differences.csv"
