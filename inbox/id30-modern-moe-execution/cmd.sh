#!/bin/bash
set -eo pipefail

echo "=== AVAILABLE PYTHON ENVIRONMENTS ==="
date -Is
hostname
source /data1/home/sunyiq/miniconda3/etc/profile.d/conda.sh
conda env list

echo "=== DEPENDENCY MATRIX ==="
for python_bin in /data1/home/sunyiq/miniconda3/bin/python /data1/home/sunyiq/miniconda3/envs/*/bin/python; do
  [ -x "$python_bin" ] || continue
  echo "--- $python_bin"
  "$python_bin" - <<'PY'
import importlib.util
import platform

names = ("pytest", "torch", "pandas", "pyarrow", "ruamel.yaml", "xarray")
print("python", platform.python_version())
for name in names:
    print(name, bool(importlib.util.find_spec(name)))
PY
done

echo "=== LOCAL CONDA PACKAGE CACHE ==="
find /data1/home/sunyiq/miniconda3/pkgs -maxdepth 1 -iname 'pytest-*' -printf '%f\n' | sort | tail -20 || true
