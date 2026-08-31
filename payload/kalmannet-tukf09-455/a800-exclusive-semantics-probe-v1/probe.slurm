#!/usr/bin/env bash
#SBATCH -J t455a8sem01
#SBATCH -p hgpu8
#SBATCH --nodelist=ngu201
#SBATCH -N 1
#SBATCH -n 1
#SBATCH --cpus-per-task=4
#SBATCH --gres=gpu:1
#SBATCH --exclusive
#SBATCH -t 00:05:00
#SBATCH -o /data1/home/sunyiq/kalmannet_tukf09_455_a800_exclusive_semantics_probe_v1_20260831_01a055e6/logs/probe-%j.out
#SBATCH -e /data1/home/sunyiq/kalmannet_tukf09_455_a800_exclusive_semantics_probe_v1_20260831_01a055e6/logs/probe-%j.err

set -o pipefail
umask 077

ROOT=/data1/home/sunyiq/kalmannet_tukf09_455_a800_exclusive_semantics_probe_v1_20260831_01a055e6
FINAL="${ROOT}/status/allocation_probe.json"
TMP="${ROOT}/status/allocation_probe.json.pending.${SLURM_JOB_ID:-unknown}"

shell_fallback() {
  rc=$?
  trap - EXIT
  if [[ ! -e "${FINAL}" && ! -L "${FINAL}" ]]; then
    [[ "${rc}" -ne 0 ]] || rc=99
    fallback="${ROOT}/status/allocation_probe.shell_failure.pending.${SLURM_JOB_ID:-unknown}"
    if ( set -o noclobber; printf '{"errors":["shell_preflight_or_python_failed_before_json_publication"],"schema_version":"tukf09_455_a800_exclusive_semantics_probe_v1","shell_exit_code":%s,"status":"FAIL"}\n' "${rc}" > "${fallback}" ) 2>/dev/null; then
      ln "${fallback}" "${FINAL}" 2>/dev/null && rm -f "${fallback}" || true
    fi
  fi
  exit "${rc}"
}
trap shell_fallback EXIT

[[ -n "${SLURM_JOB_ID:-}" ]] || exit 20
[[ -d "${ROOT}/logs" && -d "${ROOT}/status" ]] || exit 21
[[ ! -e "${FINAL}" && ! -L "${FINAL}" ]] || exit 22
source "/data1/home/${USER}/miniconda3/etc/profile.d/conda.sh" || \
source "${HOME}/miniconda3/etc/profile.d/conda.sh" || exit 23
conda activate nh_final || exit 24

export MKL_THREADING_LAYER=GNU
export MKL_SERVICE_FORCE_INTEL=1
export OMP_NUM_THREADS="${SLURM_CPUS_PER_TASK:-1}"
export PYTHONNOUSERSITE=1
export PYTHONDONTWRITEBYTECODE=1
unset PYTHONOPTIMIZE
PYTHON="${CONDA_PREFIX}/bin/python"
export TUKF09_PROBE_ROOT="${ROOT}"

"${PYTHON}" -B - <<'PY'
import csv
import io
import json
import os
import re
import socket
import subprocess
import sys
from pathlib import Path

import torch

root = Path(os.environ["TUKF09_PROBE_ROOT"])
final = root / "status" / "allocation_probe.json"
tmp = root / "status" / (
    "allocation_probe.json.pending." + os.environ.get("SLURM_JOB_ID", "unknown")
)
environment_names = [
    "SLURM_JOB_ID",
    "SLURM_JOB_NODELIST",
    "SLURM_JOB_NUM_NODES",
    "SLURM_NNODES",
    "SLURM_NTASKS",
    "SLURM_JOB_CPUS_PER_NODE",
    "SLURM_CPUS_ON_NODE",
    "SLURM_CPUS_PER_TASK",
    "SLURM_JOB_GRES",
    "SLURM_STEP_GRES",
    "SLURM_JOB_GPUS",
    "SLURM_STEP_GPUS",
    "SLURM_GPUS_ON_NODE",
    "CUDA_VISIBLE_DEVICES",
]
environment = {name: os.environ.get(name, "") for name in environment_names}
errors = []


def run(arguments):
    return subprocess.run(
        arguments,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
        check=False,
    )


def positive_integer(value):
    return int(value) if re.fullmatch(r"[1-9][0-9]*", value or "") else None


hostname = socket.gethostname()
if hostname.split(".", 1)[0] != "ngu201":
    errors.append("hostname_not_ngu201")

raw_cpu = environment["SLURM_JOB_CPUS_PER_NODE"]
cpu_match = re.fullmatch(r"([1-9][0-9]*)(?:\(x([1-9][0-9]*)\))?", raw_cpu)
cpus_per_node = int(cpu_match.group(1)) if cpu_match else None
cpu_repeat = int(cpu_match.group(2) or "1") if cpu_match else None
node_values = [
    positive_integer(environment[name])
    for name in ("SLURM_JOB_NUM_NODES", "SLURM_NNODES")
    if environment[name]
]
node_count = node_values[0] if node_values else None
if raw_cpu not in {"64", "64(x1)"} or cpus_per_node != 64 or cpu_repeat != 1:
    errors.append("exclusive_job_cpus_per_node_not_64x1")
if node_count != 1 or any(value != 1 for value in node_values):
    errors.append("node_count_not_1")
if positive_integer(environment["SLURM_CPUS_ON_NODE"]) != 64:
    errors.append("slurm_cpus_on_node_not_64")
if positive_integer(environment["SLURM_CPUS_PER_TASK"]) != 4:
    errors.append("slurm_cpus_per_task_not_4")
if positive_integer(environment["SLURM_NTASKS"]) != 1:
    errors.append("slurm_ntasks_not_1")


def gpu_tokens(raw):
    return [value.strip() for value in raw.split(",") if value.strip()]


job_tokens = gpu_tokens(environment["SLURM_JOB_GPUS"])
step_tokens = gpu_tokens(environment["SLURM_STEP_GPUS"])
if not job_tokens and not step_tokens:
    errors.append("no_slurm_gpu_allocation_variable")
if job_tokens and len(job_tokens) != 1:
    errors.append("slurm_job_gpus_not_one_identifier")
if step_tokens and len(step_tokens) != 1:
    errors.append("slurm_step_gpus_not_one_identifier")
if job_tokens and step_tokens and job_tokens != step_tokens:
    errors.append("slurm_job_step_gpu_identifier_mismatch")
selected_tokens = step_tokens or job_tokens
selected_identifier = selected_tokens[0] if len(selected_tokens) == 1 else ""

physical_query = run(
    [
        "nvidia-smi",
        "--query-gpu=index,uuid,name,memory.total,driver_version",
        "--format=csv,noheader,nounits",
    ]
)
physical = []
if physical_query.returncode == 0:
    for row in csv.reader(io.StringIO(physical_query.stdout)):
        if len(row) != 5:
            continue
        try:
            index = int(row[0].strip())
            memory_mib = int(row[3].strip())
        except ValueError:
            continue
        physical.append(
            {
                "index": index,
                "uuid": row[1].strip(),
                "name": row[2].strip(),
                "memory_total_mib": memory_mib,
                "driver_version": row[4].strip(),
            }
        )
else:
    errors.append("nvidia_smi_inventory_failed")
if len(physical) != 8:
    errors.append("physical_gpu_count_not_8")
if sorted(record["index"] for record in physical) != list(range(8)):
    errors.append("physical_gpu_indices_not_0_through_7")
if len({record["uuid"] for record in physical}) != len(physical):
    errors.append("physical_gpu_uuids_not_unique")
if any(record["name"] != "NVIDIA A800-SXM4-80GB" for record in physical):
    errors.append("physical_gpu_name_mismatch")
if any(record["memory_total_mib"] < 80000 for record in physical):
    errors.append("physical_gpu_memory_below_80000_mib")

preexisting_query = run(
    [
        "nvidia-smi",
        "--query-compute-apps=gpu_uuid,pid,process_name",
        "--format=csv,noheader,nounits",
    ]
)
preexisting_compute_processes = [
    row.strip() for row in preexisting_query.stdout.splitlines() if row.strip()
]
if preexisting_query.returncode != 0:
    errors.append("preexisting_compute_process_query_failed")
elif preexisting_compute_processes:
    errors.append("preexisting_compute_processes_present")

selected_query = None
selected_uuid = None
if selected_identifier:
    completed = run(
        [
            "nvidia-smi",
            "--id",
            selected_identifier,
            "--query-gpu=uuid,name,memory.total",
            "--format=csv,noheader,nounits",
        ]
    )
    rows = list(csv.reader(io.StringIO(completed.stdout))) if completed.returncode == 0 else []
    if len(rows) == 1 and len(rows[0]) == 3:
        selected_query = {
            "uuid": rows[0][0].strip(),
            "name": rows[0][1].strip(),
            "memory_total_mib": rows[0][2].strip(),
        }
        selected_uuid = selected_query["uuid"]
    else:
        errors.append("slurm_selected_gpu_identifier_not_resolvable")

cuda_available = bool(torch.cuda.is_available())
visible_count = int(torch.cuda.device_count()) if cuda_available else 0
visible_info = []
process_uuid = None
process_query_returncode = None
process_query_stderr = ""
if visible_count == 1:
    properties = torch.cuda.get_device_properties(0)
    visible_info = [
        {
            "index": 0,
            "name": properties.name,
            "capability": [properties.major, properties.minor],
            "total_memory_bytes": int(properties.total_memory),
        }
    ]
    tensor = torch.empty(1, device="cuda:0")
    tensor.add_(1)
    torch.cuda.synchronize(0)
    process_query = run(
        [
            "nvidia-smi",
            "--query-compute-apps=gpu_uuid,pid",
            "--format=csv,noheader,nounits",
        ]
    )
    process_query_returncode = process_query.returncode
    process_query_stderr = process_query.stderr
    process_uuids = set()
    if process_query.returncode == 0:
        for row in csv.reader(io.StringIO(process_query.stdout)):
            if len(row) != 2:
                continue
            try:
                pid = int(row[1].strip())
            except ValueError:
                continue
            if pid == os.getpid() and row[0].strip().startswith("GPU-"):
                process_uuids.add(row[0].strip())
    if len(process_uuids) == 1:
        process_uuid = next(iter(process_uuids))
    else:
        errors.append("current_python_cuda_process_uuid_not_unique")
else:
    errors.append("pytorch_visible_gpu_count_not_1")
if visible_info:
    record = visible_info[0]
    if record["name"] != "NVIDIA A800-SXM4-80GB":
        errors.append("pytorch_gpu_name_mismatch")
    if record["capability"] != [8, 0]:
        errors.append("pytorch_compute_capability_not_8_0")
    if record["total_memory_bytes"] < 80000000000:
        errors.append("pytorch_memory_below_80000000000_bytes")
if not selected_uuid or not process_uuid or selected_uuid != process_uuid:
    errors.append("pytorch_process_uuid_not_equal_slurm_selected_uuid")

exclusive_pass = (
    raw_cpu in {"64", "64(x1)"}
    and cpus_per_node == 64
    and cpu_repeat == 1
    and node_count == 1
    and all(value == 1 for value in node_values)
    and positive_integer(environment["SLURM_CPUS_ON_NODE"]) == 64
    and positive_integer(environment["SLURM_CPUS_PER_TASK"]) == 4
)
payload_record = {
    "schema_version": "tukf09_455_a800_exclusive_semantics_probe_v1",
    "status": "PASS" if not errors else "FAIL",
    "errors": errors,
    "hostname": hostname,
    "pid": os.getpid(),
    "slurm_environment": environment,
    "normalized_allocation": {
        "job_cpus_per_node": cpus_per_node,
        "cpu_repeat": cpu_repeat,
        "node_count": node_count,
        "exclusive_node_runtime_evidence_passed": exclusive_pass,
        "slurm_gpu_identifier_source": (
            "SLURM_STEP_GPUS"
            if step_tokens
            else ("SLURM_JOB_GPUS" if job_tokens else "")
        ),
        "slurm_selected_gpu_identifier": selected_identifier,
    },
    "nvidia_smi_inventory": physical,
    "nvidia_smi_inventory_returncode": physical_query.returncode,
    "nvidia_smi_inventory_stderr": physical_query.stderr,
    "preexisting_compute_processes": preexisting_compute_processes,
    "preexisting_compute_process_query_returncode": preexisting_query.returncode,
    "preexisting_compute_process_query_stderr": preexisting_query.stderr,
    "nvidia_slurm_selected_gpu": selected_query,
    "pytorch": {
        "version": str(torch.__version__),
        "cuda_available": cuda_available,
        "visible_device_count": visible_count,
        "visible_devices": visible_info,
        "current_process_gpu_uuid": process_uuid,
        "compute_apps_query_returncode": process_query_returncode,
        "compute_apps_query_stderr": process_query_stderr,
    },
}
payload = (json.dumps(payload_record, sort_keys=True, separators=(",", ":")) + "\n").encode()
descriptor = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
with os.fdopen(descriptor, "wb") as handle:
    handle.write(payload)
    handle.flush()
    os.fsync(handle.fileno())
os.link(tmp, final)
os.unlink(tmp)
print(payload.decode(), end="")
sys.exit(0 if not errors else 40)
PY
rc=$?
if [[ "${rc}" -eq 0 ]]; then
  echo "TUKF09_455_A800_EXCLUSIVE_SEMANTICS_PROBE_PASS"
else
  echo "TUKF09_455_A800_EXCLUSIVE_SEMANTICS_PROBE_FAIL rc=${rc}" >&2
fi
exit "${rc}"
