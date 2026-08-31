#!/bin/bash
# Read-only status and log collection for the dual-GPU feasibility probe.
set -o pipefail

PROBE_ROOT=/data1/home/sunyiq/kalmannet_tukf09_455_dual_gpu_allocation_probe_v1_20260831
PROBE_JOB_ID=217074
OLD_JOB_ID=217060

echo "=== DUAL GPU PROBE SQUEUE ==="
squeue -h -j "${PROBE_JOB_ID}" -o 'job_id=%A name=%j state=%T elapsed=%M limit=%l partition=%P node=%R' || true
echo "=== DUAL GPU PROBE ESTIMATED START ==="
squeue --start -j "${PROBE_JOB_ID}" -o 'job_id=%A state=%T start=%S node=%R' || true
echo "=== DUAL GPU PROBE DETAIL ==="
scontrol show job -o "${PROBE_JOB_ID}" || true
echo "=== DUAL GPU PROBE ACCOUNTING ==="
sacct -j "${PROBE_JOB_ID}" --format=JobIDRaw,JobName,Partition,State,ExitCode,Elapsed,NodeList -P || true
echo "=== DUAL GPU PROBE STDOUT ==="
if [[ -f "${PROBE_ROOT}/logs/dual-gpu-probe-${PROBE_JOB_ID}.out" ]]; then
  cat "${PROBE_ROOT}/logs/dual-gpu-probe-${PROBE_JOB_ID}.out"
else
  echo "STDOUT_NOT_YET_PRESENT"
fi
echo "=== DUAL GPU PROBE STDERR ==="
if [[ -f "${PROBE_ROOT}/logs/dual-gpu-probe-${PROBE_JOB_ID}.err" ]]; then
  cat "${PROBE_ROOT}/logs/dual-gpu-probe-${PROBE_JOB_ID}.err"
else
  echo "STDERR_NOT_YET_PRESENT"
fi
echo "=== OLD EXCLUSIVE PROBE STATUS ==="
squeue -h -j "${OLD_JOB_ID}" -o 'job_id=%A name=%j state=%T elapsed=%M limit=%l partition=%P node=%R' || true
sacct -j "${OLD_JOB_ID}" --format=JobIDRaw,JobName,Partition,State,ExitCode,Elapsed,NodeList -P || true
echo "=== CURRENT HGPU2P NODES ==="
sinfo -p hgpu2p -N -o '%N|%t|%G|%C' || true
for node in ngu001 ngu004 ngu005 ngu006 ngu007 ngu008 ngu010 ngu011; do
  scontrol show node "${node}" -o || true
done
echo "TUKF09_455_DUAL_GPU_ALLOCATION_MAPPING_STATUS_COLLECTED"
