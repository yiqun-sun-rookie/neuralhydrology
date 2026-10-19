#!/bin/bash
set -euo pipefail
root=/data1/home/sunyiq/id25_graice_shared_probe_20261019_001
old=/data1/home/sunyiq/id25_graice_author_matched_20261016_001
payload=/data1/home/sunyiq/hpc_mailbox/inbox/id25-c01-gpuprobe-20261019/payload/shared_probe_payload_v002.tar.gz
test ! -e "$root"
test -x "$old/venv/bin/python"
test -e "$old/venv/runtime_ready"
test -r "$old/inputs/inputs.npz"
test -r "$old/runs/lat+026_lon-082/scalers.json"
printf '%s  %s
' 'e68e0eab8a6f5735b6316a7c1ff0d17bb26918ea221fdfbafaf46744c3d025cc' "$payload" | sha256sum -c -
mkdir "$root"
mkdir -p "$root/logs" "$root/tmp" "$root/cache/cuda"
tar -xzf "$payload" -C "$root"
mkdir -p "$root/source_tree/results/25_global_flood_hierarchy/regional_daily_storage_20261012_001/inputs"
mkdir -p "$root/source_tree/results/25_global_flood_hierarchy/regional_graice_author_matched_b04_20261016_001/retrieved_v001"
ln -s "$old/inputs/inputs.npz" "$root/source_tree/results/25_global_flood_hierarchy/regional_daily_storage_20261012_001/inputs/inputs.npz"
ln -s "$old/runs" "$root/source_tree/results/25_global_flood_hierarchy/regional_graice_author_matched_b04_20261016_001/retrieved_v001/runs"
echo C01_PROBE_DEPLOYED_NO_JOB_SUBMITTED_NO_CPU_RECHECK
