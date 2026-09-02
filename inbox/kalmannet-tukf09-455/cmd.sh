#!/bin/bash
# TUKF09-455 revision experiment: capture the graphics-process probe output verbatim.
# Scope: diagnosis only.
#   - no training, no training resume, no formal evaluation, no evaluation array read
#   - creates no new technical execution version
#   - never writes inside the v2r4 or v2r5 roots or the read-only training source capsule
#   - submits exactly one short job, guarded by its own one-time lock

set -o pipefail

DIAG_ROOT=/data1/home/sunyiq/kalmannet_tukf09_455_pmon_probe_diagnostics_20260902
V2R4=/data1/home/sunyiq/kalmannet_tukf09_455_basin_zero_validation_target_variance_revision_v1_a800_exclusive_v2r4_20260901
V2R5=/data1/home/sunyiq/kalmannet_tukf09_455_basin_zero_validation_target_variance_revision_v1_a800_exclusive_v2r5_20260901

echo "=== SCOPE GUARD ==="
echo "DIAG_ROOT=$DIAG_ROOT"
case "$DIAG_ROOT" in
  *a800_exclusive_v2r4*|*a800_exclusive_v2r5*|*training_source_capsule*)
    echo "SCOPE_GUARD_FAILED_DIAGNOSTIC_ROOT_OVERLAPS_FROZEN_EVIDENCE"; exit 1;;
esac
echo "SCOPE_GUARD_OK_DIAGNOSTIC_ROOT_IS_DISJOINT"

echo "=== FROZEN FAILURE EVIDENCE, READ ONLY ==="
ls -ld "$V2R4" "$V2R5" 2>&1
ls -l "$V2R5/status/training_job_id.txt" 2>&1
echo "JOB_ID_FILE_CONTENT=$(cat "$V2R5/status/training_job_id.txt" 2>&1)"
sha256sum "$V2R5/logs/training-217939.out" "$V2R5/logs/training-217939.err" 2>&1

echo "=== DIAGNOSTIC ROOT ==="
if [ -e "$DIAG_ROOT" ]; then echo "DIAGNOSTIC_ROOT_ALREADY_EXISTS"; else mkdir -p "$DIAG_ROOT" && echo "DIAGNOSTIC_ROOT_CREATED"; fi
mkdir -p "$DIAG_ROOT/logs" "$DIAG_ROOT/job"

echo "=== SINGLE SUBMISSION LOCK ==="
if mkdir "$DIAG_ROOT/job/submission.lock" 2>/dev/null; then
  echo "SUBMISSION_LOCK_ACQUIRED"
else
  echo "SUBMISSION_LOCK_ALREADY_PRESENT_NOT_RESUBMITTING"
  echo "EXISTING_JOB_ID=$(cat "$DIAG_ROOT/job/job_id.txt" 2>&1)"
  exit 0
fi

echo "=== WRITE PROBE JOB SCRIPT ==="
cat > "$DIAG_ROOT/job/pmon_probe.slurm" <<'PROBE_SCRIPT_EOF'
#!/usr/bin/env bash
#SBATCH -J tukf09-455-pmon-probe
#SBATCH -p hgpu8
#SBATCH -N 1
#SBATCH -n 1
#SBATCH --cpus-per-task=4
#SBATCH --gres=gpu:1
#SBATCH --exclusive
#SBATCH --exclude=ngu203
#SBATCH -t 00:05:00
#SBATCH -o /data1/home/sunyiq/kalmannet_tukf09_455_pmon_probe_diagnostics_20260902/logs/pmon-probe-%j.out
#SBATCH -e /data1/home/sunyiq/kalmannet_tukf09_455_pmon_probe_diagnostics_20260902/logs/pmon-probe-%j.err
# never write --mem

# Diagnosis only. Captures the graphics-process probe output verbatim.
# Runs no training, reads no evaluation array, touches no frozen experiment root.

set -o pipefail

DIAG_ROOT=/data1/home/sunyiq/kalmannet_tukf09_455_pmon_probe_diagnostics_20260902
CAP="$DIAG_ROOT/capture_${SLURM_JOB_ID}"
mkdir -p "$CAP"

echo "=== IDENTITY ==="
date -u +%Y-%m-%dT%H:%M:%SZ
hostname
echo "SLURM_JOB_ID=${SLURM_JOB_ID}"
echo "SLURM_JOB_NODELIST=${SLURM_JOB_NODELIST}"
echo "SLURM_JOB_CPUS_PER_NODE=${SLURM_JOB_CPUS_PER_NODE}"
echo "SLURM_CPUS_ON_NODE=${SLURM_CPUS_ON_NODE}"
echo "SLURM_CPUS_PER_TASK=${SLURM_CPUS_PER_TASK}"
echo "SLURM_JOB_GPUS=${SLURM_JOB_GPUS}"
echo "SLURM_STEP_GPUS=${SLURM_STEP_GPUS}"
echo "CUDA_VISIBLE_DEVICES=${CUDA_VISIBLE_DEVICES}"
echo "--- operating system ---"
cat /etc/os-release 2>/dev/null

echo "=== GPU INVENTORY (no head: SIGPIPE would kill an 8-GPU job) ==="
nvidia-smi --query-gpu=index,name,driver_version,memory.total --format=csv > "$CAP/gpu_inventory.csv" 2> "$CAP/gpu_inventory.err"
echo "gpu_inventory_return_code=$?"
cat "$CAP/gpu_inventory.csv"
cat "$CAP/gpu_inventory.err"

echo "=== VERBATIM PROBE CAPTURE: the exact command the frozen controller runs ==="
LC_ALL=C nvidia-smi pmon -c 1 > "$CAP/pmon_stdout.txt" 2> "$CAP/pmon_stderr.txt"
PMON_RC=$?
echo "PMON_COMMAND=nvidia-smi pmon -c 1"
echo "PMON_RETURN_CODE=${PMON_RC}"
echo "PMON_STDOUT_BYTES=$(wc -c < "$CAP/pmon_stdout.txt")"
echo "PMON_STDOUT_SHA256=$(sha256sum "$CAP/pmon_stdout.txt" | cut -d' ' -f1)"
echo "PMON_STDERR_BYTES=$(wc -c < "$CAP/pmon_stderr.txt")"
echo "PMON_STDERR_SHA256=$(sha256sum "$CAP/pmon_stderr.txt" | cut -d' ' -f1)"

echo "--- PROBE STANDARD OUTPUT, EVERY BYTE VISIBLE ---"
cat -A "$CAP/pmon_stdout.txt"
echo "--- PROBE STANDARD ERROR, EVERY BYTE VISIBLE ---"
cat -A "$CAP/pmon_stderr.txt"

echo "=== FROZEN PARSER SIMULATION ==="
echo "frozen rule: skip blank and hash-leading lines, then python split(maxsplit=9), require exactly 10 fields"
awk '
{
  line = $0
  sub(/^[ \t\r]+/, "", line)
  sub(/[ \t\r]+$/, "", line)
  if (line == "") next
  if (substr(line, 1, 1) == "#") next
  n = split(line, a, /[ \t\r]+/)
  plen = (n > 10 ? 10 : n)
  verdict = (plen == 10 ? "PASS" : "RAISE_graphics_process_probe_output_changed")
  printf "DATA_LINE raw_tokens=%d python_field_count=%d verdict=%s content=|%s|\n", n, plen, verdict, line
  hist[n]++
  total++
  if (plen != 10) bad++
}
END {
  printf "PARSER_SUMMARY data_lines=%d failing_lines=%d\n", total+0, bad+0
  for (k in hist) printf "TOKEN_HISTOGRAM tokens=%s lines=%s\n", k, hist[k]
}' "$CAP/pmon_stdout.txt"

echo "=== OUTER WRAPPER GATES (the ones job 217939 already passed) ==="
if grep -Eq '^# gpu[[:space:]]+pid[[:space:]]+type([[:space:]]|$)' "$CAP/pmon_stdout.txt"; then
  echo "OUTER_HEADER_GATE=PASS"
else
  echo "OUTER_HEADER_GATE=FAIL"
fi
if awk 'NF >= 3 && $1 ~ /^[0-9]+$/ && $2 ~ /^[0-9]+$/ && $3 ~ /C/ {found=1} END {exit(found ? 0 : 1)}' "$CAP/pmon_stdout.txt"; then
  echo "OUTER_COMPUTE_PROCESS_GATE=OTHER_COMPUTE_PROCESS_PRESENT"
else
  echo "OUTER_COMPUTE_PROCESS_GATE=NODE_IDLE"
fi

echo "=== COMPUTE APPLICATION CROSS CHECK ==="
nvidia-smi --query-compute-apps=pid,process_name,used_gpu_memory --format=csv 2>&1

echo "=== PROBE HELP: the column set this driver supports ==="
nvidia-smi pmon -h 2>&1

echo "=== CAPTURE MANIFEST ==="
cd "$CAP" || exit 1
sha256sum pmon_stdout.txt pmon_stderr.txt gpu_inventory.csv gpu_inventory.err 2>&1

echo "TUKF09_455_PMON_PROBE_CAPTURE_COMPLETED"
PROBE_SCRIPT_EOF
chmod 0644 "$DIAG_ROOT/job/pmon_probe.slurm"
wc -c "$DIAG_ROOT/job/pmon_probe.slurm"
sha256sum "$DIAG_ROOT/job/pmon_probe.slurm"

echo "=== SUBMIT EXACTLY ONE JOB ==="
out=$(sbatch "$DIAG_ROOT/job/pmon_probe.slurm" 2>&1)
echo "$out"
JID=$(echo "$out" | grep -oE 'Submitted batch job [0-9]+' | grep -oE '[0-9]+')
if [ -z "$JID" ]; then
  echo "SUBMIT_FAILED_NO_JOB_NUMBER_RETURNED"
  rmdir "$DIAG_ROOT/job/submission.lock" 2>/dev/null
  exit 1
fi
printf '%s' "$JID" > "$DIAG_ROOT/job/job_id.txt"
echo "PMON_PROBE_JOB_ID=$JID"

echo "=== IMMEDIATE STATE ==="
squeue -j "$JID" -o "%.10i %.26j %.8P %.10T %.24R %.8M" 2>&1
echo "--- estimated start time ---"
squeue -j "$JID" -h --start -o '%S' 2>&1
echo "--- partition occupancy ---"
sinfo -p hgpu8 -o "%.10P %.6a %.6D %.6t %.30N" 2>&1

echo "TUKF09_455_PMON_PROBE_SUBMITTED_ONCE_NO_TRAINING_NO_FORMAL_EVALUATION"
