#!/bin/bash
# Read-only admission check for the new A800-exclusive remote root.
set -o pipefail

NEW_ROOT=/data1/home/sunyiq/kalmannet_tukf09_455_basin_zero_validation_target_variance_revision_v1_a800_exclusive_v2_20260831

echo "=== NEW A800 ROOT ==="
if [[ -e "${NEW_ROOT}" || -L "${NEW_ROOT}" ]]; then
  echo "NEW_A800_ROOT_ALREADY_EXISTS"
  ls -ld "${NEW_ROOT}" || true
  find "${NEW_ROOT}" -mindepth 1 -maxdepth 2 -printf '%y|%p|%s\n' 2>/dev/null | sort | head -n 200 || true
else
  echo "NEW_A800_ROOT_CONFIRMED_ABSENT"
fi
echo "=== PENDING PROBE JOBS ==="
for job_id in 217060 217074; do
  squeue -h -j "${job_id}" -o 'job_id=%A name=%j state=%T elapsed=%M limit=%l partition=%P node=%R' || true
  sacct -j "${job_id}" --format=JobIDRaw,JobName,Partition,State,ExitCode,Elapsed,NodeList -P || true
done
echo "=== A800 PARTITION ==="
sinfo -p hgpu8 -N -o '%N|%t|%G|%C' || true
scontrol show partition hgpu8 -o || true
for node in ngu201 ngu202 ngu203; do
  scontrol show node "${node}" -o || true
done
echo "TUKF09_455_A800_EXCLUSIVE_V2_REMOTE_ADMISSION_CHECK_COMPLETED"
