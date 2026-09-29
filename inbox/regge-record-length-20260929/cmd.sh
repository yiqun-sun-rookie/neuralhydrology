#!/bin/bash
set -eo pipefail
sequence=7

ROOT=/data1/home/sunyiq/regge_record_length_20260929_001
STAGE="$ROOT/runtime_stage_002"
PREFIX="$ROOT/runtime_probe_002"
MICRO_ARCHIVE="$STAGE/micromamba-2.9.0-linux-64.tar.bz2"
MICRO_SHA=8761c382127e6363bd9e0a2451aa3ef90d071a79133f736e2f759a3bf13040dd

test -d "$ROOT"
test ! -e "$STAGE"
test ! -e "$PREFIX"
mkdir "$STAGE"
trap 'rc=$?; printf "status=failed\nexit_code=%s\nutc=%s\n" "$rc" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$STAGE/runtime_failed.txt"; exit "$rc"' ERR

echo "=== download pinned private environment tool ==="
curl -fLsS --max-time 180 \
  https://micro.mamba.pm/api/micromamba/linux-64/2.9.0 \
  -o "$MICRO_ARCHIVE"
echo "$MICRO_SHA  $MICRO_ARCHIVE" | sha256sum -c -
mkdir "$STAGE/tool"
tar -xjf "$MICRO_ARCHIVE" -C "$STAGE/tool" bin/micromamba
"$STAGE/tool/bin/micromamba" --version

echo "=== create exact isolated Linux runtime ==="
export MAMBA_ROOT_PREFIX="$STAGE/mamba_root"
timeout 1200 "$STAGE/tool/bin/micromamba" create -q -y -p "$PREFIX" \
  -c pytorch -c defaults \
  python=3.11.5 numpy=1.26.4 pytorch=2.2.2 cpuonly psutil=5.9.0 \
  mkl=2023.1.0 intel-openmp=2023.1.0 conda-pack pytest

echo "=== validate exact isolated Linux runtime ==="
export MKL_THREADING_LAYER=GNU
export MKL_SERVICE_FORCE_INTEL=1
export OMP_NUM_THREADS=1
export MKL_NUM_THREADS=1
"$PREFIX/bin/python" - "$STAGE/runtime_ready.json" <<'PY'
import hashlib
import json
import os
import platform
import sys
from pathlib import Path

import numpy
import psutil
import torch

values = {
    "schema": "regge_private_runtime_ready_v01",
    "python": platform.python_version(),
    "numpy": numpy.__version__,
    "torch": torch.__version__,
    "psutil": psutil.__version__,
    "torch_threads": torch.get_num_threads(),
    "cuda_available": torch.cuda.is_available(),
    "prefix": str(Path(sys.prefix).resolve()),
    "mkl_threading_layer": os.environ.get("MKL_THREADING_LAYER"),
    "mkl_service_force_intel": os.environ.get("MKL_SERVICE_FORCE_INTEL"),
}
expected = {"python": "3.11.5", "numpy": "1.26.4", "torch": "2.2.2"}
if {key: values[key] for key in expected} != expected:
    raise RuntimeError(f"primary versions differ: {values}")
if values["torch_threads"] != 1 or values["cuda_available"]:
    raise RuntimeError(f"runtime device or thread contract differs: {values}")
target = Path(sys.argv[1])
target.write_text(json.dumps(values, indent=2, sort_keys=True) + "\n", encoding="utf-8")
print(json.dumps(values, sort_keys=True))
PY
"$STAGE/tool/bin/micromamba" list -p "$PREFIX" --explicit > "$STAGE/environment.explicit.txt"
sha256sum "$STAGE/runtime_ready.json" "$STAGE/environment.explicit.txt"
du -sh "$PREFIX" "$STAGE/mamba_root/pkgs"
rm -f "$STAGE/runtime_failed.txt"
trap - ERR
