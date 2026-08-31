#!/bin/bash
# Supersede the incompatible A800-exclusive v2 deployment before any probe or training.
set -o pipefail

ROOT=/data1/home/sunyiq/kalmannet_tukf09_455_basin_zero_validation_target_variance_revision_v1_a800_exclusive_v2_20260831

echo "A800_EXCLUSIVE_V2_SUPERSEDED_BEFORE_PROBE_OR_TRAINING"
if [[ -e "${ROOT}" || -L "${ROOT}" ]]; then
  echo "SUPERSEDED_V2_ROOT_EXISTS_READ_ONLY_REPORT"
  ls -ld "${ROOT}" || true
  find "${ROOT}" -mindepth 1 -maxdepth 2 -printf '%y|%p|%s\n' 2>/dev/null | sort | head -n 200 || true
else
  echo "SUPERSEDED_V2_ROOT_NOT_DEPLOYED"
fi
echo "CURRENT_JOBS_READ_ONLY"
for job_id in 217060 217074; do
  squeue -h -j "${job_id}" -o 'job_id=%A name=%j state=%T elapsed=%M limit=%l partition=%P node=%R' || true
  sacct -j "${job_id}" --format=JobIDRaw,JobName,Partition,State,ExitCode,Elapsed,NodeList -P || true
done
echo "TUKF09_455_A800_EXCLUSIVE_V2_SUPERSEDE_CHECK_COMPLETED"
