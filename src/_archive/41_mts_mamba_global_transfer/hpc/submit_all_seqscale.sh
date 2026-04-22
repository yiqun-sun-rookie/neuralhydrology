#!/usr/bin/env bash
# =============================================================================
# Submit all 10 seq-length scaling jobs (Phase 2v3)
#
# Usage (from project root on HPC):
#   bash src/mts_mamba_global_transfer/hpc/submit_all_seqscale.sh
# =============================================================================
set -eo pipefail

SLURM_SCRIPT="src/mts_mamba_global_transfer/hpc/submit_seqscale.slurm"
LOG_DIR="logs/41_mts_mamba_global_transfer"

mkdir -p "$LOG_DIR"

CONFIGS=(
    seqscale_cudalstm_336h
    seqscale_cudalstm_720h
    seqscale_cudalstm_1440h
    seqscale_cudalstm_2160h
    seqscale_cudalstm_4320h
    seqscale_mamba_336h
    seqscale_mamba_720h
    seqscale_mamba_1440h
    seqscale_mamba_2160h
    seqscale_mamba_4320h
)

echo "=========================================="
echo "Submitting ${#CONFIGS[@]} seq-length scaling jobs"
echo "=========================================="

for cfg in "${CONFIGS[@]}"; do
    echo -n "  ${cfg} ... "
    JOB_ID=$(sbatch --export=CONFIG="${cfg}" --job-name="t41-${cfg}" "${SLURM_SCRIPT}" | awk '{print $4}')
    echo "Job ${JOB_ID}"
done

echo ""
echo "=========================================="
echo "All jobs submitted. Monitor with: squeue -u \$USER"
echo "=========================================="
