#!/usr/bin/env bash
set -eo pipefail

ROOT=/data1/home/sunyiq/id31_hydrologic_dynamic_tokens_20260828/repo
SCRIPT=src/hydrologic_dynamic_tokens/hpc/submit_gpu_resource_probe.slurm
EXPECTED_SHA=2a2df8a54a3c38e5b356024c91188d5db5d64e14b96e899efb4a42928bf2607f

test -d "$ROOT/.git"
cd "$ROOT"
test -f "$SCRIPT"
test "$(sha256sum "$SCRIPT" | awk '{print $1}')" = "$EXPECTED_SHA"
bash -n "$SCRIPT"

source /data1/home/sunyiq/miniconda3/etc/profile.d/conda.sh
conda activate nh_final
python -m src.hydrologic_dynamic_tokens.scripts.audit_configs

echo "=== SUBMISSION COMMAND ==="
type -a sbatch
echo "sbatch $SCRIPT"
SUBMISSION="$(sbatch "$SCRIPT")"
echo "$SUBMISSION"
test "$(printf '%s\n' "$SUBMISSION" | grep -Ec '^Submitted batch job [0-9]+$')" -eq 1
JOB_ID="$(printf '%s\n' "$SUBMISSION" | sed -n 's/^Submitted batch job \([0-9][0-9]*\)$/\1/p')"
test -n "$JOB_ID"
test "$JOB_ID" != "215876"
echo "ID31_GPU_PROBE_JOB_ID=$JOB_ID"
squeue -j "$JOB_ID" -o '%.18i %.12P %.30j %.2t %.10M %.20R' || true
echo "ID31_GPU_PROBE_SUBMISSION_PASS"
