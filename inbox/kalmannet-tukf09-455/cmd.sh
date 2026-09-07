#!/bin/bash
# TUKF09-455: submit a three-minute NON-exclusive one-card probe on hgpu8.
# Its own directory under the home root; touches no experiment root, capsule or archive.
set -eo pipefail
PROBE=/data1/home/sunyiq/tukf09_455_shared_node_probe_20260907
mkdir -p "$PROBE"
cat > "$PROBE/probe.slurm" <<'SLURM_EOF'
#!/usr/bin/env bash
#SBATCH -J tukf09-455-shared-probe
#SBATCH -p hgpu8
#SBATCH -N 1
#SBATCH -n 1
#SBATCH --cpus-per-task=4
#SBATCH --gres=gpu:1
#SBATCH -t 00:03:00
#SBATCH -o /data1/home/sunyiq/tukf09_455_shared_node_probe_20260907/probe-%j.out
#SBATCH -e /data1/home/sunyiq/tukf09_455_shared_node_probe_20260907/probe-%j.err
set -o pipefail
echo "HOST=$(hostname)  JOB=$SLURM_JOB_ID  START=$(date -Is)"
echo "SLURM_JOB_GPUS=${SLURM_JOB_GPUS:-}  SLURM_STEP_GPUS=${SLURM_STEP_GPUS:-}  CUDA_VISIBLE_DEVICES=${CUDA_VISIBLE_DEVICES:-}"
echo "SLURM_CPUS_ON_NODE=${SLURM_CPUS_ON_NODE:-}  SLURM_CPUS_PER_TASK=${SLURM_CPUS_PER_TASK:-}  SLURM_JOB_CPUS_PER_NODE=${SLURM_JOB_CPUS_PER_NODE:-}  SLURM_MEM_PER_NODE=${SLURM_MEM_PER_NODE:-}"
echo "nproc=$(nproc)  taskset=$(taskset -pc $$ 2>/dev/null | sed 's/.*: //')"
echo "=== nvidia-smi -L (cards this job can see) ==="
nvidia-smi -L 2>&1
echo "VISIBLE_GPU_COUNT=$(nvidia-smi -L 2>/dev/null | grep -c '^GPU ')"
echo "=== nvidia-smi pmon -c 1 (the exact table the whole-node gate reads) ==="
LC_ALL=C nvidia-smi pmon -c 1 2>&1
echo "=== compute apps by gpu ==="
nvidia-smi --query-compute-apps=gpu_uuid,pid,process_name,used_memory --format=csv 2>&1
echo "FOREIGN_COMPUTE_PROCESS_COUNT=$(nvidia-smi --query-compute-apps=pid --format=csv,noheader 2>/dev/null | grep -c .)"
echo "=== other jobs on this node right now ==="
squeue -w "$(hostname)" -o "%.10i %.10u %.12P %.20j %.8T %.6D %.10b" 2>&1
echo "=== cgroup device view ==="
ls -la /dev/nvidia* 2>&1 | head -12
cat /proc/self/cgroup 2>/dev/null | head -5
echo "=== memory this job may use ==="
cat /sys/fs/cgroup/memory.max 2>/dev/null || cat /sys/fs/cgroup/memory/memory.limit_in_bytes 2>/dev/null || echo "cgroup memory limit not readable"
free -g | head -2
echo "END=$(date -Is)"
echo TUKF09_455_SHARED_NODE_PROBE_DONE
SLURM_EOF
sed -i "s/\r$//" "$PROBE/probe.slurm"
echo "PROBE_SLURM_SHA256=$(sha256sum "$PROBE/probe.slurm" | cut -d" " -f1)"
JID=$(sbatch --parsable "$PROBE/probe.slurm" 2>&1)
echo "SUBMITTED_JOB_ID=$JID"
echo "$JID" > "$PROBE/job_id.txt"
sleep 45
squeue -j "${JID%%;*}" -o "%.10i %.10T %.11M %.11l %.9N %.20r" 2>&1
sleep 60
sacct -j "${JID%%;*}" -X --format=JobID%10,State%12,Elapsed%10,NodeList%9 2>&1
echo "=== probe output (if finished) ==="
cat "$PROBE"/probe-*.out 2>/dev/null || echo "(not finished yet; read it with the next command)"
cat "$PROBE"/probe-*.err 2>/dev/null | tail -5
echo TUKF09_455_SHARED_NODE_PROBE_SUBMITTED
