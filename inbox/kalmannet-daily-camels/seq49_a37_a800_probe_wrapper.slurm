#!/usr/bin/env bash
#SBATCH -J daily-knet-a37-a800-probe
#SBATCH -p hgpu8
#SBATCH -N 1
#SBATCH -n 1
#SBATCH --cpus-per-task=2
#SBATCH --gres=gpu:1
#SBATCH -t 00:05:00
#SBATCH --exclude=ngu201
#SBATCH -o /data1/home/sunyiq/kalmannet_daily_camels_knet_a37_a800_probe1_20260827/logs/probe-%j.out
#SBATCH -e /data1/home/sunyiq/kalmannet_daily_camels_knet_a37_a800_probe1_20260827/logs/probe-%j.err

set -euo pipefail

if [[ -z "${SLURM_JOB_ID:-}" ]]; then
  echo "A37 A800 probe wrapper must run inside Slurm" >&2
  exit 70
fi
ALLOCATED_HOST="$(hostname)"
if [[ "${SLURM_JOB_PARTITION:-}" != "hgpu8" ]]; then
  echo "A37 A800 probe was allocated outside hgpu8: ${SLURM_JOB_PARTITION:-UNSET}" >&2
  exit 71
fi
case "$ALLOCATED_HOST" in
  ngu202|ngu203) ;;
  *)
    echo "A37 A800 probe was allocated outside the approved healthy candidates: $ALLOCATED_HOST" >&2
    exit 72
    ;;
esac

VISIBLE_DEVICE="${CUDA_VISIBLE_DEVICES:-}"
if [[ -z "$VISIBLE_DEVICE" || "$VISIBLE_DEVICE" = *","* || "$VISIBLE_DEVICE" = "-1" || "$VISIBLE_DEVICE" = "NoDevFiles" ]]; then
  echo "A37 A800 probe requires exactly one CUDA_VISIBLE_DEVICES assignment: ${VISIBLE_DEVICE:-UNSET}" >&2
  exit 73
fi
GPU_IDENTITY="$(timeout 20s nvidia-smi --id "$VISIBLE_DEVICE" --query-gpu=index,uuid,name,memory.total,memory.free,driver_version --format=csv,noheader,nounits)" || {
  echo "A37 A800 nvidia-smi identity query failed or timed out" >&2
  exit 74
}
if [[ -z "$GPU_IDENTITY" || "$GPU_IDENTITY" = *$'\n'* ]]; then
  echo "A37 A800 probe expected exactly one GPU identity row" >&2
  exit 75
fi
IFS=',' read -r GPU_INDEX GPU_UUID GPU_NAME GPU_TOTAL_MIB GPU_FREE_MIB GPU_DRIVER <<< "$GPU_IDENTITY"
if [[ "$GPU_NAME" != *A800* ]]; then
  echo "A37 A800 probe received a non-A800 device: $GPU_NAME" >&2
  exit 76
fi

printf 'A37_A800_WRAPPER_STAGE timestamp_utc=%s stage=allocated job_id=%s hostname=%s partition=%s gpu_index=%s gpu_uuid=%s gpu_name=%s gpu_total_mib=%s gpu_free_mib=%s driver=%s\n' \
  "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$SLURM_JOB_ID" "$ALLOCATED_HOST" "$SLURM_JOB_PARTITION" \
  "$GPU_INDEX" "$GPU_UUID" "$GPU_NAME" "$GPU_TOTAL_MIB" "$GPU_FREE_MIB" "$GPU_DRIVER"

export PARITY_REMOTE_ROOT="/data1/home/sunyiq/kalmannet_daily_camels_knet_a37_a800_probe1_20260827"
exec bash "${SLURM_SUBMIT_DIR}/hpc/daily_camels_ukf_knet_parity/submit_probe_gpu.slurm"
