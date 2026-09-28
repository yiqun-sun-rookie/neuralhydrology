#!/usr/bin/env bash
set -eo pipefail
root=/data1/home/sunyiq/kalmannet_wrr_counter_diagnosis_20260928_v1
old=/data1/home/sunyiq/kalmannet_hamid_weights_20260923_v1
model=/data1/home/sunyiq/kalmannet_wrr_hp_extension_20260902/repo/experiments/optimize_hyper_parameters/wrr_hp_extension_20260902/runs/formal_seed42_gpu/idx0014_lr0p01_hs64_nl1_mult15
echo '=== EXCLUSIVE ROOT ==='
if [ -e "$root" ]; then echo 'ROOT_ALREADY_EXISTS'; exit 2; else echo 'ROOT_AVAILABLE'; fi
echo '=== FROZEN INPUTS ==='
for path in "$model/results/best_model.pt" "$model/config_used.yaml" "$old/data/val_win800_20070527_04-20090314_13.pt" "$old/probe_package_v2/sources/walrus.py" "$old/probe_package_v2/sources/walrus_observed.py" "$old/formal_package_v3/sources/network.py"; do
  if [ ! -f "$path" ]; then echo "MISSING $path"; exit 3; fi
  sha256sum "$path"
done
echo '=== RESOURCE QUEUES ==='
sinfo -h -p hgpu2p,hgpu2,hgpu4,hgpu8 -o '%P|%a|%l|%D|%t|%G' | head -20
echo '=== OWN RUNNING OR PENDING JOBS ==='
squeue -h -u sunyiq -o '%i|%j|%T|%P|%R' | head -35
