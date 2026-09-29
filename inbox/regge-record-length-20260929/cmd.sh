#!/bin/bash
set -eo pipefail
sequence=12

ROOT=/data1/home/sunyiq/regge_record_length_20260929_001
SOURCE_PREFIX="$ROOT/runtime_probe_002"
PREFIX="$ROOT/runtime_probe_005"
STAGE="$ROOT/runtime_stage_005"

test -d "$ROOT"
test -x "$SOURCE_PREFIX/bin/python"
test ! -e "$PREFIX"
test ! -e "$STAGE"
mkdir "$STAGE"
trap 'rc=$?; printf "status=failed\nexit_code=%s\nutc=%s\n" "$rc" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$STAGE/runtime_failed.txt"; exit "$rc"' ERR

echo "=== clone exact core runtime into exclusive complete attempt ==="
cp -a "$SOURCE_PREFIX" "$PREFIX"
timeout 1200 "$PREFIX/bin/python" -m pip install --no-input --only-binary=:all: \
  pandas==2.3.2 threadpoolctl==3.6.0 pytest==9.1.1

echo "=== validate complete old-glibc-compatible runtime ==="
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

import numpy
import pandas
import psutil
import pytest
import threadpoolctl
import torch

values = {
    "schema": "regge_private_runtime_complete_v03",
    "python": platform.python_version(),
    "numpy": numpy.__version__,
    "pandas": pandas.__version__,
    "torch": torch.__version__,
    "psutil": psutil.__version__,
    "threadpoolctl": threadpoolctl.__version__,
    "pytest": pytest.__version__,
    "torch_threads": torch.get_num_threads(),
    "cuda_available": torch.cuda.is_available(),
    "threadpools": threadpoolctl.threadpool_info(),
    "prefix": str(Path(sys.prefix).resolve()),
    "source_prefix": "/data1/home/sunyiq/regge_record_length_20260929_001/runtime_probe_002",
    "mkl_threading_layer": os.environ.get("MKL_THREADING_LAYER"),
    "mkl_service_force_intel": os.environ.get("MKL_SERVICE_FORCE_INTEL"),
}
expected = {
    "python": "3.11.5", "numpy": "1.26.4", "pandas": "2.3.2",
    "torch": "2.2.2", "psutil": "5.9.0", "threadpoolctl": "3.6.0",
    "pytest": "9.1.1",
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
"$PREFIX/bin/python" -m pip freeze --all > "$STAGE/pip_freeze.txt"
sha256sum "$STAGE/runtime_ready.json" "$STAGE/pip_freeze.txt"
du -sh "$PREFIX"
rm -f "$STAGE/runtime_failed.txt"
trap - ERR
