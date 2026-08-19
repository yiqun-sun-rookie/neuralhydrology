#!/usr/bin/env bash
# zhenjiang out-of-year validation :: HPC environment qualification, step 1
# READ-ONLY. No sbatch, no writes, no package installs, no repository changes.
set -o pipefail

echo "=== A. HOST AND TIME ==="
hostname
date -u +%Y-%m-%dT%H:%M:%SZ
uname -r
head -3 /etc/os-release 2>/dev/null || true

echo "=== B. CONDA ENVS ==="
source /data1/home/${USER}/miniconda3/etc/profile.d/conda.sh 2>/dev/null || \
source ${HOME}/miniconda3/etc/profile.d/conda.sh 2>/dev/null || echo "CONDA_SH_NOT_FOUND"
conda env list 2>&1 | head -20 || true

echo "=== C. nh_final PACKAGE PROBE (login node; cuda expected False here) ==="
conda activate nh_final 2>&1 || echo "CONDA_ACTIVATE_FAILED"
command -v python || true
python - <<'PY'
import importlib
import json
import platform
import sys

names = ("numpy", "pandas", "scipy", "sklearn", "psutil", "threadpoolctl", "torch")
out = {
    "python_executable": sys.executable,
    "python_version": platform.python_version(),
    "operating_system": platform.platform(),
    "modules": {},
}
missing = []
for name in names:
    try:
        module = importlib.import_module(name)
        out["modules"][name] = str(getattr(module, "__version__", "unknown"))
    except Exception as exc:
        out["modules"][name] = "MISSING:%s:%s" % (type(exc).__name__, exc)
        missing.append(name)
out["missing"] = missing
try:
    import torch
    out["torch_cuda_build"] = torch.version.cuda
    out["torch_cuda_available_on_login"] = torch.cuda.is_available()
    out["torch_cudnn_version"] = torch.backends.cudnn.version()
except Exception as exc:
    out["torch_probe_error"] = "%s:%s" % (type(exc).__name__, exc)
print(json.dumps(out, sort_keys=True, indent=2))
PY

echo "=== D. PIP CAPABILITY (probe only, nothing installed) ==="
python -m pip --version 2>&1 | head -2 || true

echo "=== E. PARTITIONS AND GPU TYPE HOMOGENEITY ==="
sinfo -o '%.12P %.6a %.6D %.26N %.18G %.10T' 2>&1 | head -20 || true
echo "--- per-node gres on hgpu2p ---"
sinfo -N -p hgpu2p -o '%.10N %.10T %.18G %.6c' 2>&1 | head -20 || true
echo "--- per-node gres on hgpu2 / hgpu4 ---"
sinfo -N -p hgpu2,hgpu4 -o '%.10N %.10T %.18G %.6c' 2>&1 | head -20 || true
echo "--- drained/down reasons ---"
sinfo -R 2>&1 | head -12 || true

echo "=== F. MY QUEUE ==="
squeue -u "$USER" -o '%.10i %.12P %.22j %.9T %.11M %.10R' 2>&1 | head -20 || true

echo "=== G. OUTBOUND NETWORK (needed to clone a private repo) ==="
getent hosts github.com >/dev/null && echo DNS_OK || echo DNS_FAIL
timeout 45 ssh -o ConnectTimeout=25 -T git@github.com 2>&1 | head -1 || true
timeout 50 curl -sS -o /dev/null -m 45 -w "pypi=%{http_code}\n" https://pypi.org/simple/ 2>&1 | head -1 || true

echo "=== H. DISK AND ROOT STATE (read-only) ==="
df -h /data1/home/sunyiq 2>&1 | tail -2 || true
test -d /data1/home/sunyiq/zhenjiang_stage_direction_r2_20260819 && \
  echo "frozen_r2_root_exists=true (must stay untouched)" || echo "frozen_r2_root_exists=false"
test -e /data1/home/sunyiq/zhenjiang_oyv_qual_20260819 && \
  echo "qual_root_preexists=true (ABORT CONDITION)" || echo "qual_root_preexists=false"

echo "=== END ==="
