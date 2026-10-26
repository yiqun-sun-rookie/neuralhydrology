#!/bin/bash
set -euo pipefail
root=/data1/home/sunyiq/id25_regional_transport_rds07_20261026_001
payload=/data1/home/sunyiq/hpc_mailbox/inbox/id25-rds07-transport-20261026/payload/rds07_transport_payload_v001.tar.gz
test ! -e "$root"
active=$(timeout 30 squeue -h -u sunyiq -n id25_rds07_261026 -o '%i|%T')
test -z "$active"
printf '%s  %s\n' 'f42f9e562e2c6ddfe2a35d00138ce075c3f7f0e3208345fb2305c3f12a0ce5ee' "$payload" | sha256sum -c -
mkdir "$root"
mkdir -p "$root/logs" "$root/tmp" "$root/cache" "$root/output"
tar -xzf "$payload" -C "$root"
ln -s /data1/home/sunyiq/id25_regional_daily_storage_20261012_001/inputs/inputs.npz "$root/inputs/inputs.npz"
echo DEPLOYED_NO_SCIENTIFIC_PREFLIGHT
bash "$root/ops/submit.sh"
