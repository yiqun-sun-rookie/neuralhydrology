#!/usr/bin/env bash
set -eo pipefail
echo '=== READONLY SNAPSHOT ==='
date -u '+%Y-%m-%dT%H:%M:%SZ'
squeue -u sunyiq -h -o '%i|%j|%T|%P|%R'
sinfo -p hgpu2p,hgpu2,hgpu4 -N -O nodelist,partition,gres:14,gresused:24,cpusstate
df -h /data1/home/sunyiq
candidate=/data1/home/sunyiq/kalmannet_wrr_closeout_20260928_v1
if [ -e "$candidate" ]; then
  echo 'CANDIDATE_ALREADY_EXISTS'
  ls -ld "$candidate"
else
  echo "CANDIDATE_AVAILABLE=$candidate"
fi
echo '=== SAVED COUNTER ARRAYS AND VALIDATION MAPPING ==='
old=/data1/home/sunyiq/kalmannet_wrr_counter_diagnosis_20260928_v1
cat "$old/runs/plain_a/completion.json"
cat "$old/runs/plain_a/validation_time_mapping.json"
cat "$old/runs/counted_a/completion.json"
echo '=== FROZEN DATA INVENTORY ==='
source=/data1/home/sunyiq/kalmannet_hamid_weights_20260923_v1
find "$source/data" -maxdepth 1 -type f -printf '%f|%s\n' | sort
find "$source/formal_package_v3" -maxdepth 2 -type f -printf '%P|%s\n' | sort
echo '=== COMPLETE READONLY ==='
