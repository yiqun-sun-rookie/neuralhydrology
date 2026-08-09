#!/usr/bin/env bash
#SBATCH -J a64-tz-validate
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

DRIVER=/data1/home/sunyiq/hpc_mailbox/inbox/autoresearch-64/dlopen_probe.py
PATCH_FILE=/data1/home/sunyiq/hpc_mailbox/inbox/autoresearch-64/runtime_dlopen_timezone.patch
WORK_ROOT="$ROOT/runs/unified_autoresearch/dlopen_timezone_fix_validation_20260809_seq23"
EVIDENCE="$WORK_ROOT/evidence"
EXPECTED_BOOTSTRAP_SHA256=cfa856be50c0549694a7a7c226a1f84b3b6d47dbcd1fc15587bfaa5c87a9cb18
EXPECTED_RUNNER_SHA256=202b67d56e9a0f1535de225f6085ba8f7f199e591b46f13473d85b27b7551227

echo "=== ENVIRONMENT ==="
python -c "import sys; print(sys.executable); print(sys.version)"
python -c "import sysconfig; print('compiled_tzpath=' + str(sysconfig.get_config_var('TZPATH')))"
sha256sum "$DRIVER"
sha256sum "$PATCH_FILE"

echo "=== CREATE ISOLATED SOURCE SNAPSHOT ==="
[ ! -e "$WORK_ROOT" ] || { echo "WORK_ROOT_ALREADY_EXISTS"; exit 2; }
mkdir -p "$WORK_ROOT/src"
cp -a "$ROOT/src/unified_autoresearch" "$WORK_ROOT/src/"
patch --batch -p1 -d "$WORK_ROOT" < "$PATCH_FILE"
ACTUAL_BOOTSTRAP_SHA256=$(sha256sum "$WORK_ROOT/src/unified_autoresearch/runtime/bootstrap.py" | cut -d' ' -f1)
ACTUAL_RUNNER_SHA256=$(sha256sum "$WORK_ROOT/src/unified_autoresearch/runtime/runner.py" | cut -d' ' -f1)
echo "expected_bootstrap_sha256=$EXPECTED_BOOTSTRAP_SHA256"
echo "actual_bootstrap_sha256=$ACTUAL_BOOTSTRAP_SHA256"
echo "expected_runner_sha256=$EXPECTED_RUNNER_SHA256"
echo "actual_runner_sha256=$ACTUAL_RUNNER_SHA256"
[ "$ACTUAL_BOOTSTRAP_SHA256" = "$EXPECTED_BOOTSTRAP_SHA256" ] || exit 3
[ "$ACTUAL_RUNNER_SHA256" = "$EXPECTED_RUNNER_SHA256" ] || exit 3

export PYTHONPATH="$WORK_ROOT/src"
export DLOPEN_PROBE_PROJECT_ROOT="$WORK_ROOT"
export DLOPEN_PROBE_EVIDENCE_ROOT="$EVIDENCE"
export DLOPEN_PROBE_EXPECT_SANDBOX_SUCCESS=1

echo "=== THREE ISOLATED SANDBOX PROBES AFTER NARROW DLOPEN AND TIMEZONE FIXES ==="
python -u "$DRIVER"

echo "=== RESULT SUMMARY ==="
grep -E '"diagnostic_complete"|"package"|"process_exit_code"|"status"|"ctypes_dlopen_denied"|"required_outputs_complete"' \
  "$EVIDENCE/SUMMARY.json" | head -80
echo "=== SANDBOX DYNAMIC-LOADING EVENTS ==="
for PACKAGE in numpy pandas pyarrow; do
  echo "--- $PACKAGE ---"
  grep '"event":"ctypes.dlopen"' "$EVIDENCE/runs/$PACKAGE/logs/access.jsonl"
done
echo "=== PHASE-SCOPED SYSTEM TIMEZONE READS ==="
for PACKAGE in numpy pandas pyarrow; do
  echo "--- $PACKAGE policy ---"
  grep 'dependency_initialization_system_read_roots' "$EVIDENCE/runs/$PACKAGE/logs/runtime-policy.json"
  echo "--- $PACKAGE timezone reads ---"
  grep '/zoneinfo/' "$EVIDENCE/runs/$PACKAGE/logs/access.jsonl" || true
done
echo "summary=$EVIDENCE/SUMMARY.json"
echo "manifest=$EVIDENCE/MANIFEST.sha256"
