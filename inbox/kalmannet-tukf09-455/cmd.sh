#!/bin/bash
# Submit one isolated five-minute feasibility probe that reserves both RTX 3090
# GPUs while allowing unrelated CPU-only jobs to remain on the node.
set -euo pipefail

PROBE_ROOT=/data1/home/sunyiq/kalmannet_tukf09_455_dual_gpu_allocation_probe_v1_20260831
PROBE_SCRIPT="${PROBE_ROOT}/dual_gpu_allocation_probe.slurm"
JOB_RECORD="${PROBE_ROOT}/job_id.txt"

if [[ -e "${PROBE_ROOT}" ]]; then
  echo "REFUSING_TO_OVERWRITE_EXISTING_PROBE_ROOT=${PROBE_ROOT}" >&2
  exit 40
fi
umask 077
mkdir -p "${PROBE_ROOT}/logs"

cat > "${PROBE_SCRIPT}" <<'SLURM'
#!/usr/bin/env bash
#SBATCH -J tukf09-455-dual-gpu-map
#SBATCH -p hgpu2p
#SBATCH -N 1
#SBATCH -n 1
#SBATCH --cpus-per-task=4
#SBATCH --gres=gpu:2
#SBATCH --exclude=ngu002
#SBATCH -t 00:05:00
#SBATCH -o /data1/home/sunyiq/kalmannet_tukf09_455_dual_gpu_allocation_probe_v1_20260831/logs/dual-gpu-probe-%j.out
#SBATCH -e /data1/home/sunyiq/kalmannet_tukf09_455_dual_gpu_allocation_probe_v1_20260831/logs/dual-gpu-probe-%j.err

set -euo pipefail

source "/data1/home/${USER}/miniconda3/etc/profile.d/conda.sh" || \
  source "${HOME}/miniconda3/etc/profile.d/conda.sh"
conda activate nh_final || { echo "CONDA_FAILED" >&2; exit 21; }

export MKL_THREADING_LAYER=GNU
export MKL_SERVICE_FORCE_INTEL=1
export OMP_NUM_THREADS="${SLURM_CPUS_PER_TASK}"
export PYTHONNOUSERSITE=1
export PYTHONDONTWRITEBYTECODE=1
PYTHON="${CONDA_PREFIX}/bin/python"

"${PYTHON}" -B - <<'PY'
import json
import os
import re
import socket
import subprocess

import torch


def run(command):
    return subprocess.run(
        command,
        check=True,
        capture_output=True,
        text=True,
        timeout=20,
    )


pmon = run(["nvidia-smi", "pmon", "-c", "1"])
other_compute_processes = []
for raw_line in pmon.stdout.splitlines():
    line = raw_line.strip()
    if not line or line.startswith("#"):
        continue
    fields = line.split(maxsplit=9)
    if len(fields) != 10:
        raise RuntimeError("nvidia-smi pmon output format changed")
    if fields[1] == "-" and fields[2] == "-":
        continue
    if fields[2] == "C":
        other_compute_processes.append(
            {"gpu_index": fields[0], "pid": fields[1], "process": fields[9]}
        )
if other_compute_processes:
    raise RuntimeError(f"pre-existing GPU compute processes: {other_compute_processes}")

step_gpus = os.environ.get("SLURM_STEP_GPUS", "")
job_gpus = os.environ.get("SLURM_JOB_GPUS", "")
cuda_visible = os.environ.get("CUDA_VISIBLE_DEVICES", "")
selected_text = step_gpus or job_gpus or cuda_visible
selected_ids = [value.strip() for value in selected_text.split(",") if value.strip()]
if len(selected_ids) != 2 or len(set(selected_ids)) != 2:
    raise RuntimeError("Slurm did not expose exactly two distinct allocated GPU identifiers")

if not torch.cuda.is_available() or torch.cuda.device_count() != 2:
    raise RuntimeError("PyTorch did not expose exactly two allocated CUDA devices")
names = [torch.cuda.get_device_name(index) for index in range(2)]
capabilities = [list(torch.cuda.get_device_capability(index)) for index in range(2)]
total_memory = [int(torch.cuda.get_device_properties(index).total_memory) for index in range(2)]
if names != ["NVIDIA GeForce RTX 3090", "NVIDIA GeForce RTX 3090"]:
    raise RuntimeError(f"allocated GPU names changed: {names}")
if capabilities != [[8, 6], [8, 6]]:
    raise RuntimeError(f"allocated GPU compute capability changed: {capabilities}")
if any(value < 25_000_000_000 for value in total_memory):
    raise RuntimeError(f"allocated GPU memory is below the contract: {total_memory}")

for index in range(2):
    torch.zeros(1, device=f"cuda:{index}")
for index in range(2):
    torch.cuda.synchronize(index)

compute_query = run(
    [
        "nvidia-smi",
        "--query-compute-apps=gpu_uuid,pid",
        "--format=csv,noheader,nounits",
    ]
)
process_uuids = set()
for row in compute_query.stdout.splitlines():
    fields = [field.strip() for field in row.split(",")]
    if len(fields) != 2:
        continue
    try:
        pid = int(fields[1])
    except ValueError:
        continue
    if pid == os.getpid() and fields[0].startswith("GPU-"):
        process_uuids.add(fields[0])
if len(process_uuids) != 2:
    raise RuntimeError(f"current process was not mapped to two physical GPU UUIDs: {process_uuids}")

selected_records = []
for selected_id in selected_ids:
    query = run(
        [
            "nvidia-smi",
            "--id",
            selected_id,
            "--query-gpu=index,uuid,name,memory.total,driver_version",
            "--format=csv,noheader,nounits",
        ]
    )
    rows = [row.strip() for row in query.stdout.splitlines() if row.strip()]
    if len(rows) != 1:
        raise RuntimeError(f"allocated GPU identifier is ambiguous: {selected_id}")
    fields = [field.strip() for field in rows[0].split(",")]
    if len(fields) != 5 or not fields[1].startswith("GPU-"):
        raise RuntimeError(f"allocated GPU identity format changed: {rows[0]}")
    selected_records.append(
        {
            "slurm_identifier": selected_id,
            "physical_index": fields[0],
            "uuid": fields[1],
            "name": fields[2],
            "memory_total_mib": int(fields[3]),
            "driver_version": fields[4],
        }
    )
selected_uuids = {record["uuid"] for record in selected_records}
if selected_uuids != process_uuids:
    raise RuntimeError(
        f"PyTorch physical GPUs differ from Slurm allocation: {process_uuids} != {selected_uuids}"
    )

node_query = run(
    [
        "nvidia-smi",
        "--query-gpu=index,uuid,name",
        "--format=csv,noheader,nounits",
    ]
)
node_rows = [row.strip() for row in node_query.stdout.splitlines() if row.strip()]
record = {
    "status": "DUAL_GPU_ALLOCATION_MAPPING_PASS",
    "hostname": socket.gethostname(),
    "slurm_job_id": os.environ.get("SLURM_JOB_ID", ""),
    "slurm_job_gpus": job_gpus,
    "slurm_step_gpus": step_gpus,
    "cuda_visible_devices": cuda_visible,
    "torch_visible_device_count": int(torch.cuda.device_count()),
    "torch_device_names": names,
    "torch_compute_capabilities": capabilities,
    "torch_total_memory_bytes": total_memory,
    "torch_process_gpu_uuids": sorted(process_uuids),
    "slurm_selected_gpus": selected_records,
    "node_nvidia_smi_rows": node_rows,
    "preexisting_compute_processes": other_compute_processes,
}
print(json.dumps(record, sort_keys=True))
PY

echo "TUKF09_455_DUAL_GPU_ALLOCATION_MAPPING_COMPLETED"
SLURM

chmod 500 "${PROBE_SCRIPT}"
JOB_ID="$(sbatch --parsable "${PROBE_SCRIPT}")"
if [[ ! "${JOB_ID}" =~ ^[0-9]+$ ]]; then
  echo "UNEXPECTED_SBATCH_RESULT=${JOB_ID}" >&2
  exit 41
fi
printf '%s\n' "${JOB_ID}" > "${JOB_RECORD}"
echo "DUAL_GPU_PROBE_JOB_ID=${JOB_ID}"
squeue -h -j "${JOB_ID}" -o 'job_id=%A state=%T partition=%P node=%R' || true
echo "TUKF09_455_DUAL_GPU_ALLOCATION_MAPPING_SUBMITTED"
