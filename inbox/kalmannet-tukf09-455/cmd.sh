#!/bin/bash
# Read-only login-node network and installed-runtime probe after compute-node DNS failure.
set -o pipefail

ROOT=/data1/home/sunyiq/kalmannet_tukf09_455_basin_zero_validation_target_variance_revision_v1_a800_exclusive_v2r1_20260901
JOB_ID=217163
PENDING="${ROOT}/runtime_v2r1.pending.${JOB_ID}"
TORCH_URL='https://download.pytorch.org/whl/cu121/torch-2.2.2%2Bcu121-cp311-cp311-linux_x86_64.whl'
PYPI_URL='https://pypi.org/simple/numpy/'
PYTORCH_INDEX_URL='https://download.pytorch.org/whl/cu121/'

echo "=== FIXED FAILED PREPARATION EVIDENCE ==="
sacct -j "${JOB_ID}" -n -P --format=JobIDRaw,JobName,State,ExitCode,Elapsed,NodeList 2>&1 || true
for item in \
  "${ROOT}/status/preparation_submission.lock" \
  "${ROOT}/status/preparation.lock" \
  "${ROOT}/status/preparation_job_id.txt" \
  "${ROOT}/status/initial_bundle_verification.json" \
  "${PENDING}/evidence/pip-stdout.log" \
  "${PENDING}/evidence/pip-stderr.log"; do
  if [[ -f "${item}" && ! -L "${item}" ]]; then
    stat -c 'FILE=%n SIZE_BYTES=%s LINKS=%h MODE=%a MTIME=%y' "${item}" 2>&1 || true
    sha256sum "${item}" 2>&1 || true
  elif [[ -d "${item}" && ! -L "${item}" ]]; then
    stat -c 'DIRECTORY=%n LINKS=%h MODE=%a MTIME=%y' "${item}" 2>&1 || true
  else
    echo "MISSING_OR_IRREGULAR=${item}"
  fi
done

echo "=== LOGIN NODE IDENTITY AND STORAGE ==="
hostname 2>&1 || true
uname -a 2>&1 || true
getconf GNU_LIBC_VERSION 2>&1 || true
df -B1 "${ROOT}" 2>&1 || true
command -v curl 2>&1 || true
curl --version 2>&1 || true

echo "=== LOGIN NODE DNS ==="
for host in download.pytorch.org pypi.org files.pythonhosted.org; do
  echo "DNS_HOST=${host}"
  getent hosts "${host}" 2>&1 || true
done

echo "=== LOGIN NODE APPLICATION-LAYER NETWORK ==="
echo "PYTORCH_WHEEL_HEAD=${TORCH_URL}"
timeout 150 curl -sSIL --connect-timeout 30 --max-time 120 \
  -o /dev/null \
  -w 'PYTORCH_WHEEL_HTTP=%{http_code} REMOTE_IP=%{remote_ip} SIZE_DOWNLOAD=%{size_download} TIME_CONNECT=%{time_connect} TIME_TOTAL=%{time_total}\n' \
  "${TORCH_URL}" 2>&1 || true
echo "PYTORCH_INDEX_GET=${PYTORCH_INDEX_URL}"
timeout 150 curl -sSL --connect-timeout 30 --max-time 120 \
  -o /dev/null \
  -w 'PYTORCH_INDEX_HTTP=%{http_code} REMOTE_IP=%{remote_ip} SIZE_DOWNLOAD=%{size_download} TIME_CONNECT=%{time_connect} TIME_TOTAL=%{time_total}\n' \
  "${PYTORCH_INDEX_URL}" 2>&1 || true
echo "PYPI_NUMPY_GET=${PYPI_URL}"
timeout 150 curl -sSL --connect-timeout 30 --max-time 120 \
  -o /dev/null \
  -w 'PYPI_NUMPY_HTTP=%{http_code} REMOTE_IP=%{remote_ip} SIZE_DOWNLOAD=%{size_download} TIME_CONNECT=%{time_connect} TIME_TOTAL=%{time_total}\n' \
  "${PYPI_URL}" 2>&1 || true

echo "=== SHARED NH_FINAL PACKAGE VERSIONS ==="
source "/data1/home/${USER}/miniconda3/etc/profile.d/conda.sh" 2>&1 || \
source "${HOME}/miniconda3/etc/profile.d/conda.sh" 2>&1 || true
conda activate nh_final 2>&1 || true
export PYTHONNOUSERSITE=1
export PYTHONDONTWRITEBYTECODE=1
PYTHON="${CONDA_PREFIX:-/data1/home/${USER}/miniconda3/envs/nh_final}/bin/python"
"${PYTHON}" -B - <<'PY' 2>&1 || true
import importlib.metadata
import json
import platform
import sys

names = [
    "torch",
    "numpy",
    "filelock",
    "typing-extensions",
    "sympy",
    "networkx",
    "jinja2",
    "fsspec",
    "MarkupSafe",
    "mpmath",
    "nvidia-cuda-nvrtc-cu12",
    "nvidia-cuda-runtime-cu12",
    "nvidia-cuda-cupti-cu12",
    "nvidia-cudnn-cu12",
    "nvidia-cublas-cu12",
    "nvidia-cufft-cu12",
    "nvidia-curand-cu12",
    "nvidia-cusolver-cu12",
    "nvidia-cusparse-cu12",
    "nvidia-nccl-cu12",
    "nvidia-nvtx-cu12",
    "nvidia-nvjitlink-cu12",
    "triton",
    "psutil",
]
versions = {}
for name in names:
    try:
        versions[name] = importlib.metadata.version(name)
    except importlib.metadata.PackageNotFoundError:
        versions[name] = None
print(json.dumps({
    "executable": sys.executable,
    "platform": platform.platform(),
    "python": sys.version,
    "versions": versions,
}, sort_keys=True))
PY

echo "=== FORMAL EVALUATION HOLD ==="
RESULTS_ROOT="${ROOT}/bundle/kalmannet/results/tukf09_455_basin_zero_validation_target_variance_revision_v1"
for name in selection evaluation formal_evaluation; do
  if [[ -e "${RESULTS_ROOT}/${name}" || -L "${RESULTS_ROOT}/${name}" ]]; then
    echo "FORBIDDEN_OUTPUT_PRESENT=${name}"
  else
    echo "FORBIDDEN_OUTPUT_ABSENT=${name}"
  fi
done
echo "TUKF09_455_V2R1_LOGIN_NETWORK_AND_RUNTIME_READONLY_PROBE_COMPLETED"
