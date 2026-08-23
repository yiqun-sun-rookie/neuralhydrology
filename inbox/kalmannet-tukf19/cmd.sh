#!/usr/bin/env bash
set -o pipefail

echo '=== TUKF19 READ-ONLY HPC LIVE PROBE ==='
date -Is 2>&1 || true
hostname -f 2>&1 || hostname 2>&1 || true
uname -a 2>&1 || true

echo '=== RUNNER ==='
pgrep -af hpc_runner_active 2>&1 || true

echo '=== SLURM COMMANDS ==='
command -v sinfo 2>&1 || true
command -v sbatch 2>&1 || true
type sbatch 2>&1 || true
sbatch --version 2>&1 || true

echo '=== PARTITION SUMMARY ==='
sinfo -h -o '%P|%a|%l|%D|%C|%m|%G' 2>&1 || true

echo '=== RELEVANT PARTITIONS ==='
for partition in hcpu48 hcpu48y hcpu64 hcpu128 hgpu2p; do
  echo "--- $partition ---"
  scontrol show partition "$partition" 2>&1 || true
done

echo '=== USER JOBS ==='
squeue -u "${USER:-sunyiq}" -o '%.18i|%.12P|%.30j|%.10T|%.10M|%.10l|%.6D|%R' 2>&1 || true

echo '=== RECENT ACCOUNTING ==='
sacct -S 2026-08-20 -X --format=JobID%12,JobName%24,Partition%12,State%14,ExitCode%10,AllocCPUS%10,Elapsed%12,ReqMem%12,AllocTRES%40 2>&1 || true

echo '=== STORAGE ==='
df -BG /data1/home/sunyiq 2>&1 || true
quota -s 2>&1 || true
TARGET=/data1/home/sunyiq/kalmannet_tukf19_20260823
if [[ -e "$TARGET" ]]; then
  echo "TARGET_EXISTS=$TARGET"
  ls -la "$TARGET" 2>&1 || true
else
  echo "TARGET_ABSENT=$TARGET"
fi

echo '=== NH_FINAL ENVIRONMENT ==='
CONDA_SH=/data1/home/sunyiq/miniconda3/etc/profile.d/conda.sh
if [[ ! -f "$CONDA_SH" ]]; then
  CONDA_SH="$HOME/miniconda3/etc/profile.d/conda.sh"
fi
if [[ -f "$CONDA_SH" ]]; then
  source "$CONDA_SH"
  conda activate nh_final 2>&1 || true
  command -v python 2>&1 || true
  python - <<'PY' 2>&1 || true
import json
import os
import platform
import sys

report = {
    "executable": sys.executable,
    "python": sys.version,
    "platform": platform.platform(),
    "cwd": os.getcwd(),
}
for name in ("numpy", "psutil", "torch"):
    try:
        module = __import__(name)
        report[name] = getattr(module, "__version__", "UNKNOWN")
    except BaseException as error:
        report[name] = f"IMPORT_ERROR:{type(error).__name__}:{error}"
try:
    import torch
    report["torch_threads"] = torch.get_num_threads()
    report["torch_interop_threads"] = torch.get_num_interop_threads()
except BaseException as error:
    report["torch_runtime_error"] = f"{type(error).__name__}:{error}"
print(json.dumps(report, sort_keys=True))
PY
else
  echo "CONDA_SH_MISSING=$CONDA_SH"
fi

echo '=== TUKF19_READ_ONLY_PROBE_COMPLETE ==='
exit 0
