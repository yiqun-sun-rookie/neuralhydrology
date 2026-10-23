#!/bin/bash
set -euo pipefail
root=/data1/home/sunyiq/hpc_gpu_recheck_20261019_001
payload=/data1/home/sunyiq/hpc_mailbox/inbox/hpc-gpu-recheck-20261019/payload/gpu_recheck_import_repair_v003.tar.gz
test -d "$root"
test ! -e "$root/repair_import_v003"
printf '%s  %s\n' '6cf0a2fda4a335960929aaf5da7cace1c45e644ef040211894eee02ca8e17158' "$payload" | sha256sum -c -
tar -xzf "$payload" -C "$root"
bash "$root/repair_import_v003/submit.sh"
