#!/usr/bin/env bash
#SBATCH -J zj_r2_envprobe
#SBATCH -p hgpu2p
#SBATCH -N 1
#SBATCH -n 1
#SBATCH --cpus-per-task=1
#SBATCH -t 00:10:00
#SBATCH -o /data1/home/sunyiq/zhenjiang_stage_direction_r2_20260819/logs/environment_probe_%j.out
#SBATCH -e /data1/home/sunyiq/zhenjiang_stage_direction_r2_20260819/logs/environment_probe_%j.err

set -o pipefail

ROOT=/data1/home/sunyiq/zhenjiang_stage_direction_r2_20260819
export CUDA_VISIBLE_DEVICES=-1
export OMP_NUM_THREADS=1
export MKL_NUM_THREADS=1
export OPENBLAS_NUM_THREADS=1
export NUMEXPR_NUM_THREADS=1

echo "=== EXISTING PYTHON ENVIRONMENT PROBE ==="
for PYTHON_BIN in \
    /data1/home/sunyiq/miniconda3/bin/python \
    /data1/home/sunyiq/miniconda3/envs/*/bin/python \
    /data1/home/sunyiq/.conda/envs/*/bin/python \
    /data1/home/sunyiq/anaconda3/bin/python \
    /data1/home/sunyiq/anaconda3/envs/*/bin/python
do
    if [ ! -x "$PYTHON_BIN" ]; then
        continue
    fi
    "$PYTHON_BIN" - "$PYTHON_BIN" <<'PY'
import hashlib
import importlib
import json
from pathlib import Path
import sys

path = Path(sys.argv[1]).resolve()
modules = {}
all_available = True
for name in ("numpy", "pandas", "psutil", "threadpoolctl", "torch", "pytest"):
    try:
        module = importlib.import_module(name)
        modules[name] = {
            "available": True,
            "version": str(getattr(module, "__version__", "unknown")),
        }
    except Exception as exc:
        all_available = False
        modules[name] = {
            "available": False,
            "error_type": type(exc).__name__,
            "error": str(exc),
        }
payload = {
    "path": str(path),
    "bytes": path.stat().st_size,
    "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
    "version": sys.version,
    "all_required_available": all_available,
    "modules": modules,
}
print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
PY
done

echo "=== ROOT STATE ==="
test -d "$ROOT/payload_frozen" && echo "payload_frozen_exists=true" || echo "payload_frozen_exists=false"
test -e "$ROOT/execution_root" && echo "execution_root_exists=true" || echo "execution_root_exists=false"
test -e "$ROOT/migration/hpc_acceptance.json" && echo "acceptance_json_exists=true" || echo "acceptance_json_exists=false"
echo "ENVIRONMENT_PROBE_COMPLETED"
