#!/usr/bin/env bash
#SBATCH -J daily-knet-a38
#SBATCH -p hgpu8
#SBATCH -N 1
#SBATCH -n 1
#SBATCH --cpus-per-task=4
#SBATCH --gres=gpu:1
#SBATCH --nodelist=ngu202
#SBATCH -t 04:00:00
#SBATCH -o /data1/home/sunyiq/kalmannet_daily_camels_knet_a38_a800_train1_20260828/logs/train1-%j.out
#SBATCH -e /data1/home/sunyiq/kalmannet_daily_camels_knet_a38_a800_train1_20260828/logs/train1-%j.err

set -euo pipefail

if [[ -z "${SLURM_JOB_ID:-}" ]]; then
  echo "A38 A800 continuation must run inside Slurm" >&2
  exit 70
fi
ALLOCATED_HOST="$(hostname)"
if [[ "${SLURM_JOB_PARTITION:-}" != "hgpu8" ]]; then
  echo "A38 A800 continuation allocated outside hgpu8" >&2
  exit 71
fi
if [[ "$ALLOCATED_HOST" != "ngu202" ]]; then
  echo "A38 A800 continuation allocated outside the frozen node ngu202: $ALLOCATED_HOST" >&2
  exit 72
fi

VISIBLE_DEVICE="${CUDA_VISIBLE_DEVICES:-}"
if [[ -z "$VISIBLE_DEVICE" || "$VISIBLE_DEVICE" = *","* || "$VISIBLE_DEVICE" = "-1" || "$VISIBLE_DEVICE" = "NoDevFiles" ]]; then
  echo "A38 A800 continuation requires exactly one visible GPU" >&2
  exit 73
fi
GPU_IDENTITY="$(timeout --kill-after=5s 20s nvidia-smi --id "$VISIBLE_DEVICE" --query-gpu=index,uuid,name,memory.total,memory.free,driver_version --format=csv,noheader,nounits)" || {
  echo "A38 A800 continuation GPU query failed" >&2
  exit 74
}
if [[ -z "$GPU_IDENTITY" || "$GPU_IDENTITY" = *$'\n'* || "$GPU_IDENTITY" != *"NVIDIA A800-SXM4-80GB"* ]]; then
  echo "A38 A800 continuation did not receive the frozen A800 model: $GPU_IDENTITY" >&2
  exit 75
fi
printf 'A38_A800_CONTINUATION_ALLOCATED job_id=%s hostname=%s partition=%s gpu=%s\n' \
  "$SLURM_JOB_ID" "$ALLOCATED_HOST" "$SLURM_JOB_PARTITION" "$GPU_IDENTITY"

export PARITY_REMOTE_ROOT="/data1/home/sunyiq/kalmannet_daily_camels_knet_a38_a800_train1_20260828"
export PARITY_EXACT_REPLAY_GATE="/data1/home/sunyiq/kalmannet_daily_camels_parity_20260824/status/replay_gate_DAILY_CAMELS_UKF_PARITY_KNET_FULL_STATE_EXACT_REPLAY_DTYPE_REPAIR_V3_20260825_A05.json"
export PARITY_CAUSAL_REPLAY_GATE="/data1/home/sunyiq/kalmannet_daily_camels_parity_20260824/status/replay_gate_DAILY_CAMELS_UKF_PARITY_KNET_FULL_STATE_CAUSAL_REPLAY_DTYPE_REPAIR_V3_20260825_A06.json"
export PARITY_HOST_ADMISSION_MIN_BYTES="2800353280"
export PARITY_GPU_ADMISSION_MIN_FREE_MIB="822"
export PARITY_PORTABILITY_DIAGNOSTIC_ONLY="0"
export PYTHONPATH="${SLURM_SUBMIT_DIR}/src:${SLURM_SUBMIT_DIR}"

exec bash "${SLURM_SUBMIT_DIR}/hpc/daily_camels_ukf_knet_parity/submit_train_gpu.slurm"
