#!/usr/bin/env bash
set -euo pipefail

REMOTE_ROOT="/data1/home/sunyiq/kalmannet_daily_camels_per_basin_pilots_20260901"
PROBE_EXECUTION_ID="DAILY_CAMELS_KNET_PER_BASIN_PILOT_A800_PROBE1_SEQ2"
PROBE_DIRECTORY="${REMOTE_ROOT}/probes/${PROBE_EXECUTION_ID}"
PROBE_WRAPPER="${PROBE_DIRECTORY}/submit_a800_probe.slurm"
PROBE_REPORT="${PROBE_DIRECTORY}/probe_receipt.json"
JOB_NAME="kdpp-a800-probe-s2"

echo '=== SUBMISSION IDENTITY ==='
date --iso-8601=seconds
hostname
echo 'channel=kalmannet-daily-perbasin sequence=2 purpose=single-A800-probe-only'

if [[ -e "${REMOTE_ROOT}" ]]; then
  echo "refusing unexpected pre-existing remote root: ${REMOTE_ROOT}" >&2
  find "${REMOTE_ROOT}" -maxdepth 2 -mindepth 1 -printf '%y|%p\n' | sort || true
  exit 30
fi

ACTIVE_BEFORE="$(squeue -h -u sunyiq -o '%i|%j|%T|%N' | awk -F'|' -v name="${JOB_NAME}" '$2 == name {count++} END {print count+0}')"
HISTORICAL_BEFORE="$(sacct -u sunyiq -S 2026-09-01T00:00:00 -X --format=JobIDRaw,JobName,State -n -P | awk -F'|' -v name="${JOB_NAME}" '$2 == name {count++} END {print count+0}')"
echo "exact_job_name_active_before=${ACTIVE_BEFORE}"
echo "exact_job_name_historical_before=${HISTORICAL_BEFORE}"
if [[ "${ACTIVE_BEFORE}" != "0" || "${HISTORICAL_BEFORE}" != "0" ]]; then
  echo 'duplicate probe identity detected before submission' >&2
  exit 31
fi

mkdir -p "${PROBE_DIRECTORY}"
cat > "${PROBE_WRAPPER}" <<'SLURM'
#!/usr/bin/env bash
#SBATCH --job-name=kdpp-a800-probe
#SBATCH --partition=hgpu8
#SBATCH --nodelist=ngu202
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=2
#SBATCH --gres=gpu:1
#SBATCH --mem=8G
#SBATCH --time=00:05:00

set -euo pipefail

if [[ -z "${SLURM_JOB_ID:-}" ]]; then
  echo "A800 probe must run inside Slurm" >&2
  exit 20
fi
if [[ -z "${PROBE_REPORT:-}" ]]; then
  echo "PROBE_REPORT must name a new receipt path" >&2
  exit 21
fi
if [[ -e "${PROBE_REPORT}" ]]; then
  echo "refusing to replace an existing probe receipt" >&2
  exit 22
fi

set +u
source "/data1/home/${USER}/miniconda3/etc/profile.d/conda.sh"
conda activate nh_final
set -u

export PYTHONDONTWRITEBYTECODE=1
export OMP_NUM_THREADS=2
export MKL_NUM_THREADS=2
export OPENBLAS_NUM_THREADS=2
export NUMEXPR_NUM_THREADS=2

mkdir -p "$(dirname "${PROBE_REPORT}")"
nvidia-smi --query-gpu=index,uuid,name,memory.total,memory.free,utilization.gpu --format=csv,noheader,nounits

PROBE_REPORT_PENDING="${PROBE_REPORT}.pending.${SLURM_JOB_ID}"
if [[ -e "${PROBE_REPORT_PENDING}" ]]; then
  echo "refusing to replace an existing pending probe receipt" >&2
  exit 23
fi

python - "${PROBE_REPORT_PENDING}" <<'PY'
from __future__ import annotations

from datetime import datetime, timezone
import json
import os
from pathlib import Path
import platform
import socket
import sys

import numpy as np
import torch

target = Path(sys.argv[1])
required_name = "NVIDIA A800-SXM4-80GB"
if not torch.cuda.is_available():
    raise RuntimeError("CUDA is unavailable")
if torch.cuda.device_count() != 1:
    raise RuntimeError("probe requires exactly one visible CUDA device")
actual_name = torch.cuda.get_device_name(0)
if actual_name != required_name:
    raise RuntimeError(f"required {required_name!r}, found {actual_name!r}")
device = torch.device("cuda")
left = torch.arange(4096, dtype=torch.float32, device=device).reshape(64, 64)
right = torch.eye(64, dtype=torch.float32, device=device)
product = left @ right
torch.cuda.synchronize(device)
if not torch.equal(product, left):
    raise RuntimeError("CUDA matrix identity probe differs")
free_bytes, total_bytes = torch.cuda.mem_get_info(device)
receipt = {
    "schema_version": "daily_camels_knet_per_basin_a800_probe_v1",
    "status": "PASS",
    "purpose": "resource_and_environment_probe_only_no_training",
    "recorded_at_utc": datetime.now(timezone.utc).isoformat(),
    "slurm_job_id": os.environ["SLURM_JOB_ID"],
    "hostname": socket.gethostname(),
    "platform": platform.platform(),
    "python_executable": sys.executable,
    "python_version": platform.python_version(),
    "numpy_version": np.__version__,
    "torch_version": torch.__version__,
    "cuda_runtime_version": torch.version.cuda,
    "visible_gpu_count": torch.cuda.device_count(),
    "gpu_name": actual_name,
    "gpu_total_bytes": int(total_bytes),
    "gpu_free_bytes": int(free_bytes),
    "cuda_matrix_identity_exact": True,
    "optimizer_steps": 0,
    "training_forecast_error_events": 0,
    "formal_evaluation_access_count": 0,
}
target.write_text(
    json.dumps(receipt, sort_keys=True, separators=(",", ":"), allow_nan=False)
    + "\n",
    encoding="utf-8",
)
print(json.dumps(receipt, sort_keys=True))
PY

mv "${PROBE_REPORT_PENDING}" "${PROBE_REPORT}"
SLURM
chmod 700 "${PROBE_WRAPPER}"

JOB_ID="$(sbatch \
  --parsable \
  --job-name="${JOB_NAME}" \
  --output="${PROBE_DIRECTORY}/slurm-%j.out" \
  --error="${PROBE_DIRECTORY}/slurm-%j.err" \
  --export="ALL,PROBE_REPORT=${PROBE_REPORT}" \
  "${PROBE_WRAPPER}")"
case "${JOB_ID}" in
  ''|*[!0-9]*) echo "invalid Slurm job identifier: ${JOB_ID}" >&2; exit 32 ;;
esac

ACTIVE_AFTER="$(squeue -h -j "${JOB_ID}" -o '%i|%j|%T|%N' | wc -l | tr -d ' ')"
EXACT_NAME_AFTER="$(squeue -h -u sunyiq -o '%i|%j|%T|%N' | awk -F'|' -v name="${JOB_NAME}" '$2 == name {count++} END {print count+0}')"
if [[ "${ACTIVE_AFTER}" != "1" || "${EXACT_NAME_AFTER}" != "1" ]]; then
  echo 'post-submission uniqueness proof failed' >&2
  exit 33
fi

RECEIPT="${PROBE_DIRECTORY}/submission_receipt.txt"
if [[ -e "${RECEIPT}" ]]; then
  echo 'refusing to replace probe submission receipt' >&2
  exit 34
fi
{
  printf 'channel=kalmannet-daily-perbasin\n'
  printf 'sequence=2\n'
  printf 'execution_id=%s\n' "${PROBE_EXECUTION_ID}"
  printf 'job_name=%s\n' "${JOB_NAME}"
  printf 'job_id=%s\n' "${JOB_ID}"
  printf 'active_before=%s\n' "${ACTIVE_BEFORE}"
  printf 'historical_before=%s\n' "${HISTORICAL_BEFORE}"
  printf 'active_after=%s\n' "${ACTIVE_AFTER}"
  printf 'exact_name_after=%s\n' "${EXACT_NAME_AFTER}"
  printf 'submission_count=1\n'
  printf 'signals_sent=0\n'
} > "${RECEIPT}"

echo '=== SUBMISSION RECEIPT ==='
cat "${RECEIPT}"
echo '=== CURRENT JOB ==='
squeue -j "${JOB_ID}" -o '%i|%j|%P|%T|%R|%M|%S|%N'
echo '=== SUBMISSION COMPLETE: EXACTLY ONE PROBE, NO TRAINING OR SIGNAL ==='
