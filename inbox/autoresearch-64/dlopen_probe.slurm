#!/usr/bin/env bash
#SBATCH -J a64-dlopen-probe
#SBATCH -p hcpu48
#SBATCH -N 1
#SBATCH -n 1
#SBATCH --cpus-per-task=1
#SBATCH -t 00:10:00
#SBATCH -o /data1/home/sunyiq/hpc_mailbox/outbox/slurm_%j.out
#SBATCH -e /data1/home/sunyiq/hpc_mailbox/outbox/slurm_%j.err

set -eo pipefail
source /data1/home/${USER}/miniconda3/etc/profile.d/conda.sh
conda activate nh_final || { echo "CONDA_FAILED"; exit 1; }

VENV=/data1/home/sunyiq/autoresearch64/.venv
[ -x "$VENV/bin/python" ] || { echo "VENV_PYTHON_MISSING"; exit 1; }
export PATH="$VENV/bin:$PATH"
hash -r

ROOT=/data1/home/sunyiq/autoresearch64
cd "$ROOT" || exit 1
export PYTHONPATH="$ROOT/src"

DRIVER=/data1/home/sunyiq/hpc_mailbox/inbox/autoresearch-64/dlopen_probe.py
EVIDENCE="$ROOT/runs/unified_autoresearch/dlopen_dependency_probe_20260809_seq19"

echo "=== ENVIRONMENT ==="
python -c "import sys; print(sys.executable); print(sys.version)"
sha256sum "$DRIVER"

echo "=== THREE ISOLATED SANDBOX PROBES ==="
python -u "$DRIVER"

echo "=== SUMMARY ==="
cat "$EVIDENCE/SUMMARY.json"
echo "=== MANIFEST ==="
cat "$EVIDENCE/MANIFEST.sha256"
