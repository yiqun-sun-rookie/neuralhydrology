#!/bin/bash
set -eo pipefail

REMOTE_ROOT="/data1/home/sunyiq/zhenjiang_d32_differentiable_ukf_20260828"
REFERENCE_PATHS="/data1/home/sunyiq/zhenjiang_latent_da_20260827/hpc_paths.env"

echo "remote_root=${REMOTE_ROOT}"
if [ -e "${REMOTE_ROOT}" ]; then
  echo "remote_root_state=EXISTS"
else
  echo "remote_root_state=ABSENT"
fi

echo "reference_paths_file=${REFERENCE_PATHS}"
if [ -f "${REFERENCE_PATHS}" ]; then
  echo "reference_paths_state=PRESENT"
  source "${REFERENCE_PATHS}"
  if [ -n "${INPUT_DIR:-}" ] && [ -d "${INPUT_DIR}" ]; then
    echo "input_dir_state=PRESENT"
    echo "input_dir=${INPUT_DIR}"
  else
    echo "input_dir_state=MISSING"
  fi
else
  echo "reference_paths_state=MISSING"
fi

echo "--- partitions ---"
sinfo -h -o '%P|%a|%l|%D|%G' | grep -E 'hgpu2p|hgpu4|hgpu8' || true
echo "--- own jobs ---"
squeue -u "${USER}" -h -o '%i|%P|%j|%T|%M|%l|%R' || true
echo "--- remote parent capacity ---"
df -h /data1/home/sunyiq
