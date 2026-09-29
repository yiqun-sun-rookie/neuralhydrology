#!/bin/bash
set -eo pipefail
sequence=8

ROOT=/data1/home/sunyiq/regge_record_length_20260929_001
PRIOR_STAGE="$ROOT/runtime_stage_002"
STAGE="$ROOT/runtime_stage_003"
PREFIX="$ROOT/runtime_probe_003"
MICROMAMBA="$PRIOR_STAGE/tool/bin/micromamba"

test -d "$ROOT"
test -x "$MICROMAMBA"
test -d "$PRIOR_STAGE/mamba_root/pkgs"
test ! -e "$STAGE"
test ! -e "$PREFIX"
mkdir "$STAGE"
trap 'rc=$?; printf "status=failed\nexit_code=%s\nutc=%s\n" "$rc" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$STAGE/runtime_failed.txt"; exit "$rc"' ERR

echo "=== create complete exact isolated Linux runtime ==="
export MAMBA_ROOT_PREFIX="$PRIOR_STAGE/mamba_root"
timeout 1200 "$MICROMAMBA" create -q -y -p "$PREFIX" \
  -c pytorch -c defaults \
  python=3.11.5 numpy=1.26.4 pandas=2.3.3 pytorch=2.2.2 cpuonly \
  psutil=5.9.0 mkl=2023.1.0 intel-openmp=2023.1.0 \
  matplotlib-base=3.10.6 conda-pack pytest
timeout 180 "$PREFIX/bin/python" -m pip install -q --no-input --no-deps \
  --only-binary=:all: --index-url https://pypi.org/simple threadpoolctl==3.6.0

echo "=== validate complete exact isolated Linux runtime ==="
export MKL_THREADING_LAYER=GNU
export MKL_SERVICE_FORCE_INTEL=1
export OMP_NUM_THREADS=1
export MKL_NUM_THREADS=1
"$PREFIX/bin/python" - "$STAGE/runtime_ready.json" <<'PY'
import json
import os
import platform
import sys
from pathlib import Path

import matplotlib
import numpy
import pandas
import psutil
import pytest
import threadpoolctl
import torch

values = {
    "schema": "regge_private_runtime_complete_v01",
    "python": platform.python_version(),
    "numpy": numpy.__version__,
    "pandas": pandas.__version__,
    "torch": torch.__version__,
    "psutil": psutil.__version__,
    "threadpoolctl": threadpoolctl.__version__,
    "matplotlib": matplotlib.__version__,
    "pytest": pytest.__version__,
    "torch_threads": torch.get_num_threads(),
    "cuda_available": torch.cuda.is_available(),
    "threadpools": threadpoolctl.threadpool_info(),
    "prefix": str(Path(sys.prefix).resolve()),
    "mkl_threading_layer": os.environ.get("MKL_THREADING_LAYER"),
    "mkl_service_force_intel": os.environ.get("MKL_SERVICE_FORCE_INTEL"),
}
expected = {
    "python": "3.11.5", "numpy": "1.26.4", "pandas": "2.3.3",
    "torch": "2.2.2", "psutil": "5.9.0", "threadpoolctl": "3.6.0",
    "matplotlib": "3.10.6",
}
if {key: values[key] for key in expected} != expected:
    raise RuntimeError(f"runtime versions differ: {values}")
if values["torch_threads"] != 1 or values["cuda_available"]:
    raise RuntimeError(f"runtime device or thread contract differs: {values}")
if any(int(pool.get("num_threads", 1)) != 1 for pool in values["threadpools"]):
    raise RuntimeError(f"loaded numeric thread pool differs: {values}")
target = Path(sys.argv[1])
target.write_text(json.dumps(values, indent=2, sort_keys=True) + "\n", encoding="utf-8")
print(json.dumps({key: values[key] for key in expected}, sort_keys=True))
print(json.dumps({"torch_threads": values["torch_threads"], "cuda_available": values["cuda_available"]}))
PY
"$MICROMAMBA" list -p "$PREFIX" --explicit > "$STAGE/environment.explicit.txt"
"$PREFIX/bin/python" -m pip freeze --all > "$STAGE/pip_freeze.txt"
sha256sum "$STAGE/runtime_ready.json" "$STAGE/environment.explicit.txt" "$STAGE/pip_freeze.txt"
du -sh "$PREFIX" "$PRIOR_STAGE/mamba_root/pkgs"
rm -f "$STAGE/runtime_failed.txt"
trap - ERR
