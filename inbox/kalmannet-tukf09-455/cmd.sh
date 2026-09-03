#!/bin/bash
# TUKF09-455: health-check ngu203 before deciding whether to drop it from the exclude list.
# Diagnosis only. No training, no formal evaluation, no new technical execution version.
# Writes only inside its own diagnostics root; never touches the v2r4, v2r5 or v2r6 roots
# or the read-only training source capsule.

set -o pipefail

DIAG_ROOT=/data1/home/sunyiq/kalmannet_tukf09_455_pmon_probe_diagnostics_20260902/node_health_ngu203
case "$DIAG_ROOT" in
  *a800_exclusive_v2r4*|*a800_exclusive_v2r5*|*a800_exclusive_v2r6*|*training_source_capsule*)
    echo "SCOPE_GUARD_FAILED"; exit 1;;
esac
echo "SCOPE_GUARD_OK DIAG_ROOT=$DIAG_ROOT"

echo "=== CURRENT NODE STATE ==="
sinfo -p hgpu8 -o "%.10P %.6a %.6D %.8t %.24N %.20C" 2>&1
echo "--- our preparation job is untouched ---"
squeue -j 218635 -h -o "218635 %T %R" 2>&1

mkdir -p "$DIAG_ROOT/logs" "$DIAG_ROOT/job"

echo "=== SINGLE SUBMISSION LOCK ==="
if mkdir "$DIAG_ROOT/job/submission.lock" 2>/dev/null; then
  echo "LOCK_ACQUIRED"
else
  echo "LOCK_ALREADY_PRESENT_NOT_RESUBMITTING"
  echo "EXISTING_JOB_ID=$(cat "$DIAG_ROOT/job/job_id.txt" 2>&1)"
  exit 0
fi

echo "=== WRITE CUDA HEALTH SCRIPT ==="
cat > "$DIAG_ROOT/job/cuda_health.py" <<'CUDA_HEALTH_EOF'
import json, os, sys
import torch

report = {
    "torch_version": torch.__version__,
    "cuda_available": bool(torch.cuda.is_available()),
    "cuda_runtime": torch.version.cuda,
    "cudnn_version": torch.backends.cudnn.version(),
    "device_count": int(torch.cuda.device_count()),
    "cuda_visible_devices": os.environ.get("CUDA_VISIBLE_DEVICES"),
}
if not report["cuda_available"] or report["device_count"] < 1:
    report["verdict"] = "CUDA_UNAVAILABLE"
    print(json.dumps(report, sort_keys=True))
    sys.exit(3)

torch.backends.cuda.matmul.allow_tf32 = False
torch.backends.cudnn.allow_tf32 = False
props = torch.cuda.get_device_properties(0)
report["device_name"] = props.name
report["compute_capability"] = [props.major, props.minor]
report["total_memory_bytes"] = int(props.total_memory)
report["multi_processor_count"] = int(props.multi_processor_count)

generator = torch.Generator(device="cuda").manual_seed(20260903)
a = torch.randn(2048, 2048, device="cuda", dtype=torch.float32, generator=generator)
b = torch.randn(2048, 2048, device="cuda", dtype=torch.float32, generator=generator)
c = a @ b
torch.cuda.synchronize()
report["matmul_finite"] = bool(torch.isfinite(c).all().item())
report["matmul_checksum"] = float(c.sum().item())

reference = (a.double().cpu() @ b.double().cpu())
max_error = float((c.double().cpu() - reference).abs().max().item())
report["max_absolute_error_against_double_cpu"] = max_error
report["numerically_sane"] = bool(max_error < 1e-2)

free_bytes, total_bytes = torch.cuda.mem_get_info()
report["free_memory_bytes"] = int(free_bytes)
report["reported_total_memory_bytes"] = int(total_bytes)

del a, b, c
torch.cuda.empty_cache()

report["verdict"] = (
    "HEALTHY"
    if report["matmul_finite"] and report["numerically_sane"]
    and report["device_name"] == "NVIDIA A800-SXM4-80GB"
    and report["total_memory_bytes"] >= 80000000000
    else "SUSPECT"
)
print(json.dumps(report, sort_keys=True))
sys.exit(0 if report["verdict"] == "HEALTHY" else 4)
CUDA_HEALTH_EOF
sha256sum "$DIAG_ROOT/job/cuda_health.py"

echo "=== WRITE JOB SCRIPT ==="
cat > "$DIAG_ROOT/job/ngu203_health.slurm" <<'HEALTH_JOB_EOF'
#!/usr/bin/env bash
#SBATCH -J tukf09-455-ngu203-health
#SBATCH -p hgpu8
#SBATCH -N 1
#SBATCH -n 1
#SBATCH --cpus-per-task=4
#SBATCH --gres=gpu:1
#SBATCH --exclusive
#SBATCH --nodelist=ngu203
#SBATCH -t 00:10:00
#SBATCH -o /data1/home/sunyiq/kalmannet_tukf09_455_pmon_probe_diagnostics_20260902/node_health_ngu203/logs/health-%j.out
#SBATCH -e /data1/home/sunyiq/kalmannet_tukf09_455_pmon_probe_diagnostics_20260902/node_health_ngu203/logs/health-%j.err
# never write --mem

# Diagnosis only: is ngu203 a healthy exclusive A800 node?
# Runs no training, touches no experiment root, reads no evaluation array.

set -o pipefail

DIAG_ROOT=/data1/home/sunyiq/kalmannet_tukf09_455_pmon_probe_diagnostics_20260902/node_health_ngu203
CAP="$DIAG_ROOT/capture_${SLURM_JOB_ID}"
mkdir -p "$CAP"

echo "=== ALLOCATION ==="
date -u +%Y-%m-%dT%H:%M:%SZ
hostname
echo "SLURM_JOB_ID=${SLURM_JOB_ID}"
echo "SLURM_JOB_NODELIST=${SLURM_JOB_NODELIST}"
echo "SLURM_JOB_CPUS_PER_NODE=${SLURM_JOB_CPUS_PER_NODE}"
echo "SLURM_CPUS_ON_NODE=${SLURM_CPUS_ON_NODE}"
echo "SLURM_CPUS_PER_TASK=${SLURM_CPUS_PER_TASK}"
echo "SLURM_JOB_GPUS=${SLURM_JOB_GPUS}"
echo "CUDA_VISIBLE_DEVICES=${CUDA_VISIBLE_DEVICES}"
cat /etc/os-release 2>/dev/null

echo "=== GPU INVENTORY (no head: SIGPIPE would kill an 8-GPU job) ==="
nvidia-smi --query-gpu=index,name,driver_version,memory.total,uuid --format=csv > "$CAP/inventory.csv" 2> "$CAP/inventory.err"
echo "inventory_return_code=$?"
cat "$CAP/inventory.csv"
cat "$CAP/inventory.err"
echo "GPU_COUNT=$(($(wc -l < "$CAP/inventory.csv") - 1))"

echo "=== PROBE TABLE FORMAT ON THIS NODE ==="
LC_ALL=C nvidia-smi pmon -c 1 > "$CAP/pmon_stdout.txt" 2> "$CAP/pmon_stderr.txt"
echo "PMON_RETURN_CODE=$?"
echo "PMON_STDOUT_SHA256=$(sha256sum "$CAP/pmon_stdout.txt" | cut -d' ' -f1)"
cat -A "$CAP/pmon_stdout.txt"
awk '
{
  line = $0
  sub(/^[ \t\r]+/, "", line)
  sub(/[ \t\r]+$/, "", line)
  if (line == "") next
  if (substr(line, 1, 1) == "#") next
  n = split(line, a, /[ \t\r]+/)
  hist[n]++
  total++
}
END {
  printf "PARSER_DATA_LINES=%d\n", total+0
  for (k in hist) printf "TOKEN_HISTOGRAM tokens=%s lines=%s\n", k, hist[k]
}' "$CAP/pmon_stdout.txt"

echo "=== OTHER COMPUTE PROCESSES ==="
nvidia-smi --query-compute-apps=pid,process_name,used_gpu_memory --format=csv 2>&1

echo "=== REAL CUDA WORK (the only trustworthy health check) ==="
export PYTHONNOUSERSITE=1
export PYTHONDONTWRITEBYTECODE=1
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -B "$DIAG_ROOT/job/cuda_health.py" > "$CAP/cuda_health.json" 2> "$CAP/cuda_health.err"
CUDA_RC=$?
echo "CUDA_HEALTH_RETURN_CODE=$CUDA_RC"
cat "$CAP/cuda_health.json"
cat "$CAP/cuda_health.err"

echo "=== CAPTURE MANIFEST ==="
cd "$CAP" || exit 1
sha256sum ./* 2>&1

if [ "$CUDA_RC" -eq 0 ]; then
  echo "TUKF09_455_NGU203_HEALTH_PASS"
else
  echo "TUKF09_455_NGU203_HEALTH_NONPASS rc=$CUDA_RC"
fi
HEALTH_JOB_EOF
wc -c "$DIAG_ROOT/job/ngu203_health.slurm"
sha256sum "$DIAG_ROOT/job/ngu203_health.slurm"

echo "=== SUBMIT EXACTLY ONE JOB ==="
out=$(sbatch "$DIAG_ROOT/job/ngu203_health.slurm" 2>&1)
echo "$out"
JID=$(echo "$out" | grep -oE 'Submitted batch job [0-9]+' | grep -oE '[0-9]+')
if [ -z "$JID" ]; then
  echo "SUBMIT_FAILED_NO_JOB_NUMBER_RETURNED"
  rmdir "$DIAG_ROOT/job/submission.lock" 2>/dev/null
  exit 1
fi
printf '%s' "$JID" > "$DIAG_ROOT/job/job_id.txt"
echo "NGU203_HEALTH_JOB_ID=$JID"

echo "=== IMMEDIATE STATE ==="
squeue -j "$JID" -o "%.10i %.28j %.8P %.10T %.24R %.8M" 2>&1
squeue -j "$JID" -h --start -o '%S' 2>&1

echo "TUKF09_455_NGU203_HEALTH_SUBMITTED_ONCE_NO_TRAINING_NO_FORMAL_EVALUATION"
