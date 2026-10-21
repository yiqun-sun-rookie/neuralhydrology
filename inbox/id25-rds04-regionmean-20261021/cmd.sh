#!/bin/bash
set -euo pipefail
root=/data1/home/sunyiq/id25_regional_regionmean_rds04_20261021_001
payload=/data1/home/sunyiq/hpc_mailbox/inbox/id25-rds04-regionmean-20261021/payload/rds04_regionmean_payload_v001.tar.gz
test ! -e "$root"
active=$(timeout 30 squeue -h -u sunyiq -n id25_rds04_261021 -o '%i|%T')
test -z "$active"
printf '%s  %s\n' 'f1dad262fa0e176d4b5a3dfd22665b97b844e27a3d5463677532f0df52c4be4c' "$payload" | sha256sum -c -
mkdir "$root"
mkdir -p "$root/logs" "$root/tmp" "$root/output"
tar -xzf "$payload" -C "$root"
ln -s /data1/home/sunyiq/id25_regional_daily_storage_20261012_001/inputs/inputs.npz "$root/inputs/inputs.npz"
echo DEPLOYED_NO_REPEATED_PREFLIGHT
bash "$root/ops/submit.sh" initial
