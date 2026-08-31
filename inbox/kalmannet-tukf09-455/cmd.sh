#!/bin/bash
# Read-only status and terminal-log collection for allocation probe job 217060.
set -o pipefail

ROOT=/data1/home/sunyiq/kalmannet_tukf09_455_basin_zero_validation_target_variance_revision_v1_20260831
JOB_ID=217060

echo "=== SQUEUE ==="
squeue -h -j "${JOB_ID}" -o 'job_id=%A name=%j state=%T elapsed=%M limit=%l partition=%P node=%R' || true
echo "=== ESTIMATED START ==="
squeue --start -j "${JOB_ID}" -o 'job_id=%A state=%T start=%S node=%R' || true
echo "=== PRIORITY ==="
sprio -j "${JOB_ID}" || true
echo "=== JOB DETAIL ==="
scontrol show job -o "${JOB_ID}" || true
echo "=== PARTITION NODES ==="
sinfo -p hgpu2p -N -o '%N|%t|%G|%C' || true
echo "=== PARTITION DETAIL ==="
scontrol show partition hgpu2p -o || true
echo "=== NODE RESOURCE DETAIL ==="
for node in ngu001 ngu002 ngu004 ngu005 ngu006 ngu007 ngu008 ngu010 ngu011; do
  scontrol show node "${node}" -o || true
done
echo "=== SACCT ==="
sacct -j "${JOB_ID}" --format=JobIDRaw,JobName,Partition,State,ExitCode,Elapsed,NodeList -P || true
echo "=== STDOUT ==="
if [[ -f "${ROOT}/logs/allocation-probe-${JOB_ID}.out" ]]; then
  tail -n 120 "${ROOT}/logs/allocation-probe-${JOB_ID}.out"
else
  echo "STDOUT_NOT_YET_PRESENT"
fi
echo "=== STDERR ==="
if [[ -f "${ROOT}/logs/allocation-probe-${JOB_ID}.err" ]]; then
  tail -n 120 "${ROOT}/logs/allocation-probe-${JOB_ID}.err"
else
  echo "STDERR_NOT_YET_PRESENT"
fi
echo "TUKF09_455_GPU_ALLOCATION_MAPPING_STATUS_COLLECTED"
