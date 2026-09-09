#!/bin/bash
# TUKF09-455: retire the hgpu8 preparation job and probe an hgpu4 node for its real specs.
# The probe writes only under its own directory. No experiment root is touched.
set -o pipefail
PROBE=/data1/home/sunyiq/tukf09_455_hgpu4_probe_20260909
echo "TIME=$(date -Is)"
echo "=== RETIRE THE hgpu8 PREPARATION JOB ==="
JID=223992
ST=$(squeue -j "$JID" -h -o "%T" 2>/dev/null)
echo "STATE_BEFORE=${ST:-<not-in-queue>}"
if [ "$ST" = "PENDING" ] || [ "$ST" = "RUNNING" ]; then scancel "$JID" && echo SCANCEL_ISSUED; sleep 8; fi
sacct -j "$JID" -X --format=JobID%10,State%14,Elapsed%10 2>&1
echo "=== SUBMIT THE hgpu4 PROBE ==="
mkdir -p "$PROBE"
cat > "$PROBE/probe.slurm" <<'SLURM_EOF'
#!/usr/bin/env bash
#SBATCH -J tukf09-455-hgpu4-probe
#SBATCH -p hgpu4
#SBATCH -N 1
#SBATCH -n 1
#SBATCH --cpus-per-task=16
#SBATCH --gres=gpu:4
#SBATCH -t 00:05:00
#SBATCH -o /data1/home/sunyiq/tukf09_455_hgpu4_probe_20260909/probe-%j.out
#SBATCH -e /data1/home/sunyiq/tukf09_455_hgpu4_probe_20260909/probe-%j.err
set -o pipefail
echo "HOST=$(hostname)  JOB=$SLURM_JOB_ID  START=$(date -Is)"
echo "SLURM_JOB_GPUS=${SLURM_JOB_GPUS:-} SLURM_STEP_GPUS=${SLURM_STEP_GPUS:-} CUDA_VISIBLE_DEVICES=${CUDA_VISIBLE_DEVICES:-}"
echo "SLURM_CPUS_ON_NODE=${SLURM_CPUS_ON_NODE:-} SLURM_CPUS_PER_TASK=${SLURM_CPUS_PER_TASK:-} SLURM_JOB_CPUS_PER_NODE=${SLURM_JOB_CPUS_PER_NODE:-}"
echo "nproc=$(nproc)"
nvidia-smi -L 2>&1
nvidia-smi --query-gpu=index,name,uuid,driver_version,memory.total,compute_cap --format=csv 2>&1
echo "=== pmon (what the whole-node gate would read here) ==="
LC_ALL=C nvidia-smi pmon -c 1 2>&1
echo "FOREIGN_COMPUTE=$(nvidia-smi --query-compute-apps=pid --format=csv,noheader 2>/dev/null | grep -c .)"
echo "=== other jobs on this node ==="
squeue -w "$(hostname -s)" -o "%.10i %.9u %.8T %.10b" 2>&1
source "/data1/home/${USER}/miniconda3/etc/profile.d/conda.sh" || source "${HOME}/miniconda3/etc/profile.d/conda.sh"
conda activate nh_final || { echo CONDA_FAILED; exit 42; }
python -X utf8 -c "
import json, platform, torch, numpy, psutil
d={\"python\":platform.python_version(),\"numpy\":numpy.__version__,\"psutil\":psutil.__version__,
   \"torch\":str(torch.__version__),\"torch_cuda\":str(torch.version.cuda),
   \"cudnn\":int(torch.backends.cudnn.version() or 0),\"count\":int(torch.cuda.device_count()),
   \"names\":[torch.cuda.get_device_name(i) for i in range(torch.cuda.device_count())],
   \"caps\":[list(torch.cuda.get_device_capability(i)) for i in range(torch.cuda.device_count())],
   \"total_bytes\":[int(torch.cuda.get_device_properties(i).total_memory) for i in range(torch.cuda.device_count())]}
print(json.dumps(d, indent=1))
" 2>&1
free -g | head -2
echo "END=$(date -Is)"
echo TUKF09_455_HGPU4_PROBE_DONE
SLURM_EOF
sed -i "s/\r$//" "$PROBE/probe.slurm"
echo "PROBE_SHA256=$(sha256sum "$PROBE/probe.slurm" | cut -d\" \" -f1)"
PJ=$(sbatch --parsable "$PROBE/probe.slurm" 2>&1); PJ=${PJ%%;*}
echo "PROBE_JOB_ID=$PJ"
echo "$PJ" > "$PROBE/job_id.txt"
sleep 50
sacct -j "$PJ" -X --format=JobID%10,State%12,Elapsed%10,NodeList%9 2>&1
cat "$PROBE"/probe-*.out 2>/dev/null || echo "not finished yet"
echo TUKF09_455_HGPU4_PROBE_SUBMITTED
