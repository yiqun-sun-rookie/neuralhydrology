#!/bin/bash
set -euo pipefail
root=/data1/home/sunyiq/id25_graice_shared_c01_20261019_001
old=/data1/home/sunyiq/id25_graice_author_matched_20261016_001
payload=/data1/home/sunyiq/hpc_mailbox/inbox/id25-c01-shared-20261019/payload/resource_compatibility_v002.tar.gz
printf '%s  %s\n' '68ea0ec9658cf3e2148f98161cc80ed8f96202f79696d1ffdd928ddff9bd8111' "$payload" | sha256sum -c -
test ! -e "$root/resource_adaptation_v002"
mkdir "$root/resource_adaptation_v002"
tar -xzf "$payload" -C "$root/resource_adaptation_v002"
PYTHONNOUSERSITE=1 PYTHONDONTWRITEBYTECODE=1 "$old/venv/bin/python" "$root/resource_adaptation_v002/id25_apply_resource_adaptation.py"
timeout 30 squeue -j 245242 --start -o '%i|%P|%T|%r|%S|%R'
timeout 30 sinfo -p hgpu2p,hgpu2 -N -O 'partition:12,nodelist:16,gres:18,gresused:30,cpusstate:24'
echo ORIGINAL_JOB_ONLY_NO_SBATCH_NO_CANCELLATION_NO_PREFLIGHT
