#!/bin/bash
set -eo pipefail
sequence=3

ROOT=/data1/home/sunyiq/regge_record_length_20260929_001
PROBE="$ROOT/runtime_probe_001"
SCRIPT="$PROBE/create_exact_runtime.slurm"

if test -e "$ROOT"; then
  echo "REFUSE_EXISTING_ROOT $ROOT"
  exit 1
fi
mkdir -p "$PROBE/logs"

cat > "$SCRIPT" <<'SLURM'
#!/usr/bin/env bash
#SBATCH -J regge-env-v1
#SBATCH -p hgpu2p
#SBATCH -N 1
#SBATCH -n 1
#SBATCH --cpus-per-task=4
#SBATCH --exclude=ngu002
#SBATCH -t 01:00:00
#SBATCH -o /data1/home/sunyiq/regge_record_length_20260929_001/runtime_probe_001/logs/runtime-%j.out
#SBATCH -e /data1/home/sunyiq/regge_record_length_20260929_001/runtime_probe_001/logs/runtime-%j.err

set -eo pipefail
umask 027

ROOT=/data1/home/sunyiq/regge_record_length_20260929_001
PROBE="$ROOT/runtime_probe_001"
ENV_DIR="$PROBE/env"
FAILED="$PROBE/runtime_failed.txt"
SUCCESS="$PROBE/runtime_success.txt"

on_error() {
  rc=$?
  printf 'status=failed\nexit_code=%s\nhost=%s\nfinished=%s\n' "$rc" "$(hostname)" "$(date -Is)" > "$FAILED"
  exit "$rc"
}
trap on_error ERR

if test -e "$ENV_DIR" || test -e "$FAILED" || test -e "$SUCCESS"; then
  echo "REFUSE_EXISTING_RUNTIME_ATTEMPT $PROBE"
  exit 1
fi

source /data1/home/${USER}/miniconda3/etc/profile.d/conda.sh || source "$HOME/miniconda3/etc/profile.d/conda.sh"
export MKL_THREADING_LAYER=GNU
export MKL_SERVICE_FORCE_INTEL=1
export OMP_NUM_THREADS=1
export MKL_NUM_THREADS=1
export OPENBLAS_NUM_THREADS=1
export NUMEXPR_NUM_THREADS=1
export CONDA_PKGS_DIRS="$PROBE/conda_pkgs:/data1/home/${USER}/miniconda3/pkgs"

echo "START $(date -Is) host=$(hostname) job=${SLURM_JOB_ID}"
conda create -y -p "$ENV_DIR" --override-channels -c pytorch -c defaults \
  python=3.11.5 numpy=1.26.4 pytorch=2.2.2 cpuonly pandas psutil matplotlib pytest scipy

"$ENV_DIR/bin/python" - <<'PY'
import json
import os
import platform
import numpy
import torch

actual = {
    "python": platform.python_version(),
    "numpy": numpy.__version__,
    "torch": torch.__version__,
    "torch_cuda_available": torch.cuda.is_available(),
    "omp_num_threads": os.environ.get("OMP_NUM_THREADS"),
    "mkl_num_threads": os.environ.get("MKL_NUM_THREADS"),
}
print(json.dumps(actual, sort_keys=True))
required = {"python": "3.11.5", "numpy": "1.26.4", "torch": "2.2.2"}
for key, value in required.items():
    if actual[key] != value:
        raise RuntimeError(f"version mismatch for {key}: {actual[key]} != {value}")
if torch.cuda.is_available():
    raise RuntimeError("CPU-only runtime unexpectedly exposes CUDA")
PY

conda list -p "$ENV_DIR" --explicit > "$PROBE/conda-explicit.txt"
sha256sum "$PROBE/conda-explicit.txt" > "$PROBE/conda-explicit.sha256"
printf 'status=complete\nhost=%s\njob_id=%s\nfinished=%s\n' "$(hostname)" "$SLURM_JOB_ID" "$(date -Is)" > "$SUCCESS"
echo "COMPLETE $(date -Is)"
SLURM

sed -i 's/\r$//' "$SCRIPT"
chmod 750 "$SCRIPT"
submit_output=$(sbatch "$SCRIPT" 2>&1)
printf '%s\n' "$submit_output"
job_id=$(printf '%s\n' "$submit_output" | sed -n 's/^Submitted batch job \([0-9][0-9]*\)$/\1/p')
if test -z "$job_id"; then
  echo "SUBMIT_FAILED"
  exit 1
fi
printf 'job_id=%s\nscript=%s\nsubmitted=%s\n' "$job_id" "$SCRIPT" "$(date -Is)" > "$PROBE/submission_receipt.txt"
echo "SUBMITTED_JOB_ID=$job_id"
