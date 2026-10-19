#!/bin/bash
set -euo pipefail
root=/data1/home/sunyiq/hpc_gpu_recheck_20261019_001
payload=/data1/home/sunyiq/hpc_mailbox/inbox/hpc-gpu-recheck-20261019/payload/gpu_recheck_payload_v002.tar.gz
test ! -e "$root"
printf '%s  %s\n' '6ac83ed8e09a903ed969866d3e83509f80b76847bb6c9c6264ea55cfeeaa3cdc' "$payload" | sha256sum -c -
mkdir "$root"
mkdir -p "$root/logs" "$root/tmp" "$root/cache"
tar -xzf "$payload" -C "$root"
bash "$root/ops/submit_gpu_rechecks.sh"
