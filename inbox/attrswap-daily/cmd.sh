#!/bin/bash
# Read-only readiness probe for China 2023 inference. No submissions or writes.
set -o pipefail
echo '=== TIME ==='
date -Is
echo '=== EXISTING USER JOBS ==='
squeue -u sunyiq -h -o '%i|%j|%T|%P|%C|%R'
echo '=== GPU RESOURCES ==='
sinfo -p hgpu2p,hgpu2,hgpu4,hgpu8 -N -O nodelist,partition:12,statecompact:10,gres:14,gresused:24,cpusstate
echo '=== ERA5LAND 23 ATTRIBUTE MODELS ==='
for seed in 100 200 300; do
  p="/data1/home/sunyiq/forcing_swap_daily_2026_09/runs/fswap_armE23_s${seed}_2026_0908_1745_ep30"
  for f in config.yml model_epoch030.pt train_data/train_data_scaler.yml; do
    if [ -f "$p/$f" ]; then stat -c '%n|%s bytes' "$p/$f"; else echo "MISSING: $p/$f"; fi
  done
done
echo '=== TOP LEVEL DATA LOCATIONS ==='
find /data1/home/sunyiq -maxdepth 1 -type d -printf '%f\n'
find /data1/home/sunyiq/neuralhydrology/data -maxdepth 1 -type d -printf '%f\n'
echo '=== NEW ROOT COLLISION CHECK ==='
p=/data1/home/sunyiq/china_runoff_2023_inference_20260930_001
if [ -e "$p" ]; then echo "ROOT_EXISTS: $p"; else echo "ROOT_AVAILABLE: $p"; fi
echo '=== SPACE ==='
df -h /data1/home/sunyiq
