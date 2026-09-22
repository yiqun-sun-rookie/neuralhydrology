#!/usr/bin/env bash
#SBATCH --job-name=KN-noise-env-0922
#SBATCH --partition=hcpu48y
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --time=00:05:00
#SBATCH --nice=10000
#SBATCH --no-requeue
#SBATCH --output=/data1/home/sunyiq/kalmannet_tukf09_scaled_noise_rehearsal_20260922/logs/environment_probe_%j.out
#SBATCH --error=/data1/home/sunyiq/kalmannet_tukf09_scaled_noise_rehearsal_20260922/logs/environment_probe_%j.err
#SBATCH --open-mode=append
set -eo pipefail
root='/data1/home/sunyiq/kalmannet_tukf09_scaled_noise_rehearsal_20260922'
stage="$root/control/environment_probe_v1"
runtime='/data1/home/sunyiq/kalmannet_tukf09_455_basin_zero_validation_target_variance_revision_v1_a800_exclusive_v2r14_20260909/runtime_v2r14'
python_bin='/data1/home/sunyiq/miniconda3/envs/knet_clean/bin/python'

if [ -z "${SLURM_JOB_ID:-}" ]; then
    [ "$(id -un)" = sunyiq ] || exit 21
    [ "$(hostname -s)" = login4 ] || exit 22
    [ "$(readlink -f "$root")" = "$root" ] || exit 23
    [ -d "$root/control" ] && [ -d "$root/logs" ] || exit 24
    [ -x "$python_bin" ] && [ -d "$runtime/pysite" ] || exit 25
    if [ -e "$stage" ] || [ -L "$stage" ]; then
        printf 'REFUSE_EXISTING_ENVIRONMENT_PROBE_STAGE\n'
        exit 26
    fi
    mkdir -m 750 "$stage"
    cp -n "$0" "$stage/environment_probe_v1.slurm"
    cmp "$0" "$stage/environment_probe_v1.slurm"
    sha256sum "$stage/environment_probe_v1.slurm"
    cd "$stage"
    # One submission only. An ambiguous response is retained, never retried.
    set +e
    sbatch "$stage/environment_probe_v1.slurm" > "$stage/submission_response.txt" 2>&1
    submit_rc=$?
    set -e
    cat "$stage/submission_response.txt"
    [ "$submit_rc" -eq 0 ] || exit "$submit_rc"
    job_count=$(awk '/^Submitted batch job [0-9]+$/ {n++} END {print n+0}' "$stage/submission_response.txt")
    [ "$job_count" -eq 1 ] || { printf 'NO_UNIQUE_CONFIRMED_SUBMISSION_STOP\n'; exit 27; }
    job_id=$(awk '/^Submitted batch job [0-9]+$/ {print $4}' "$stage/submission_response.txt")
    printf 'CONFIRMED_ENVIRONMENT_ONLY_JOB_ID=%s\n' "$job_id"
    squeue -j "$job_id" -h -o '%i|%j|%T|%P|%C|%D|%R|%Z'
    scontrol show job "$job_id"
    printf 'HYDROLOGY_MODEL_CALLS=0 OPTIMIZER_UPDATES=0 EVALUATION_CALLS=0\n'
    exit 0
fi

[ "${SLURM_JOB_NAME:-}" = KN-noise-env-0922 ] || exit 31
[ "${SLURM_JOB_PARTITION:-}" = hcpu48y ] || exit 32
[ "${SLURM_CPUS_PER_TASK:-}" = 1 ] || exit 33
[ "${SLURM_SUBMIT_DIR:-}" = "$stage" ] || exit 34
[ "$(readlink -f "$stage")" = "$stage" ] || exit 35
cd "$stage"
mkdir -m 750 "$stage/cache"
export PYTHONNOUSERSITE=1
export PYTHONDONTWRITEBYTECODE=1
export PYTHONPATH="$runtime/pysite"
export CUDA_VISIBLE_DEVICES=''
export OMP_NUM_THREADS=1
export MKL_NUM_THREADS=1
export OPENBLAS_NUM_THREADS=1
export NUMEXPR_NUM_THREADS=1
export MKL_THREADING_LAYER=GNU
export MKL_SERVICE_FORCE_INTEL=1
export XDG_CACHE_HOME="$stage/cache"
export CUDA_CACHE_DISABLE=1
export KN_NOISE_READONLY_RUNTIME="$runtime"
# For this import-only inspection, cap virtual address space per process at 8 GiB.
# This is not a claim that the scheduler enforces an 8 GiB physical-memory limit.
ulimit -Sv 8388608
ulimit -Hv 8388608
printf 'ENVIRONMENT_ONLY_STARTED\n'
date -u '+%Y-%m-%dT%H:%M:%SZ'
hostname
cat /etc/os-release
scontrol show job "$SLURM_JOB_ID"
sha256sum "$runtime/evidence/private_runtime_manifest.json"
timeout --signal=TERM --kill-after=10s 180s "$python_bin" -B -u -c '
import hashlib
import json
import os
import pathlib
import platform
import resource
import sys

expected_limit = 8 * 2**30
assert resource.getrlimit(resource.RLIMIT_AS) == (expected_limit, expected_limit)
runtime = pathlib.Path(os.environ["KN_NOISE_READONLY_RUNTIME"]).resolve()
report = {
    "purpose": "environment_import_inspection_only",
    "python": sys.version,
    "python_executable": sys.executable,
    "platform": platform.platform(),
    "libc": platform.libc_ver(),
    "address_space_limits_bytes": resource.getrlimit(resource.RLIMIT_AS),
    "hydrology_model_calls": 0,
    "optimizer_updates": 0,
    "evaluation_calls": 0,
}
print(json.dumps(report, indent=2), flush=True)
print("PROC_CGROUP", pathlib.Path("/proc/self/cgroup").read_text(), flush=True)
for line in pathlib.Path("/proc/self/cgroup").read_text().splitlines():
    _, controllers, relative = line.split(":", 2)
    if "memory" in controllers.split(","):
        directory = pathlib.Path("/sys/fs/cgroup/memory") / relative.lstrip("/")
        for name in ("memory.limit_in_bytes", "memory.memsw.limit_in_bytes", "memory.usage_in_bytes"):
            target = directory / name
            try:
                print("CGROUP", str(target), target.read_text().strip(), flush=True)
            except OSError as exc:
                print("CGROUP_UNREADABLE", str(target), type(exc).__name__, flush=True)
    elif not controllers:
        directory = pathlib.Path("/sys/fs/cgroup") / relative.lstrip("/")
        for name in ("memory.max", "memory.swap.max", "memory.current"):
            target = directory / name
            try:
                print("CGROUP", str(target), target.read_text().strip(), flush=True)
            except OSError as exc:
                print("CGROUP_UNREADABLE", str(target), type(exc).__name__, flush=True)
import numpy
import torch
import psutil
expected_versions = {"numpy": "1.26.4", "torch": "2.2.2+cu121", "psutil": "5.9.0"}
for module in (numpy, torch, psutil):
    loaded = pathlib.Path(module.__file__).resolve()
    print("PACKAGE", module.__name__, module.__version__, str(loaded), flush=True)
    assert module.__version__ == expected_versions[module.__name__]
    assert loaded.is_relative_to(runtime / "pysite"), str(loaded)
torch.set_num_threads(1)
torch.set_num_interop_threads(1)
assert torch.get_num_threads() == 1 and torch.get_num_interop_threads() == 1
print("PROCESS", json.dumps({"rss_bytes": psutil.Process().memory_info().rss,
                             "vms_bytes": psutil.Process().memory_info().vms,
                             "peak_rss_kib": resource.getrusage(resource.RUSAGE_SELF).ru_maxrss}), flush=True)
print("TORCH_CONFIGURATION", torch.__config__.show(), flush=True)
print("NUMPY_CONFIGURATION", flush=True)
numpy.show_config()
print("ENVIRONMENT_IMPORT_INSPECTION_PASS_NOT_MODEL_ADMISSION", flush=True)
'
sha256sum "$runtime/evidence/private_runtime_manifest.json"
printf 'ENVIRONMENT_ONLY_FINISHED_MODEL_CALLS_ZERO\n'
date -u '+%Y-%m-%dT%H:%M:%SZ'
