#!/bin/bash
#SBATCH -J id25meta
#SBATCH -p hcpu48
#SBATCH -N 1
#SBATCH -n 1
#SBATCH --cpus-per-task=48
#SBATCH -t 00:05:00
#SBATCH -o /data1/home/sunyiq/id25_coarse_label_audit_20260922/slurm-%j.out
set -eo pipefail
echo "JOB_ID=$SLURM_JOB_ID"
echo "NODE=$(hostname)"
date -u +'%Y-%m-%dT%H:%M:%SZ'
PAYLOAD="$HOME/hpc_mailbox/inbox/id25-coarse-label-audit-20260922/payload"
if command -v python3 >/dev/null 2>&1; then
  python3 "$PAYLOAD/audit_metadata.py" "$PAYLOAD/coarse_metadata.tar.gz"
else
  source "/data1/home/$USER/miniconda3/etc/profile.d/conda.sh"
  conda activate nh_final
  python "$PAYLOAD/audit_metadata.py" "$PAYLOAD/coarse_metadata.tar.gz"
fi
date -u +'%Y-%m-%dT%H:%M:%SZ'
