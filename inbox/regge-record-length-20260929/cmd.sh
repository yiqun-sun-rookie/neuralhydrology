#!/bin/bash
set -eo pipefail
sequence=6

echo "=== login compatibility and exact-base check ==="
ldd --version 2>&1 | sed -n '1p'
/data1/home/sunyiq/miniconda3/bin/python - <<'PY'
import json
import platform
import sys
print(json.dumps({"executable": sys.executable, "python": platform.python_version()}))
PY

echo "=== private download endpoints from login node ==="
for url in \
  https://micro.mamba.pm/api/micromamba/linux-64/latest \
  https://repo.anaconda.com/pkgs/main/linux-64/repodata.json \
  https://conda.anaconda.org/pytorch/linux-64/repodata.json; do
  curl -LIsS --max-time 20 -o /dev/null -w '%{http_code} %{url_effective}\n' "$url"
done

echo "=== shared environment dependency versions ==="
source /data1/home/sunyiq/miniconda3/etc/profile.d/conda.sh
conda list -p /data1/home/sunyiq/miniconda3/envs/nh_final | awk '$1 ~ /^(python|pytorch|torch|numpy|mkl|intel-openmp|llvm-openmp|tbb|psutil)$/ {print}'

echo "=== isolated root remains exclusive ==="
ROOT=/data1/home/sunyiq/regge_record_length_20260929_001
test -d "$ROOT"
find "$ROOT" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort
