#!/usr/bin/env bash
set -eo pipefail

ROOT=/data1/home/sunyiq/id31_hydrologic_dynamic_tokens_20260828/repo
SCRIPT=src/hydrologic_dynamic_tokens/hpc/submit_gpu_resource_probe.slurm

test -d "$ROOT/.git"
cd "$ROOT"
test -f "$SCRIPT"
mkdir -p logs/31_hydrologic_dynamic_tokens
mkdir -p results/31_hydrologic_dynamic_tokens/_gpu_resource_probes

echo "=== SUBMISSION COMMAND ==="
type sbatch
echo "sbatch $SCRIPT"
submission_output=$(sbatch "$SCRIPT" 2>&1)
printf '%s\n' "$submission_output"
echo "$submission_output" | grep -qE '^Submitted batch job [0-9]+$'
job_id=$(echo "$submission_output" | grep -oE '[0-9]+')
test -n "$job_id"

echo "ID31_GPU_PROBE_JOB_ID=$job_id"
squeue -j "$job_id" -o '%.18i %.12P %.30j %.2t %.10M %.20R' || true
echo "ID31_GPU_PROBE_SUBMISSION_PASS"
