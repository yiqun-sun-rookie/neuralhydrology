#!/bin/bash
set -eo pipefail
printf 'READ_ONLY_PREFLIGHT horizon seed42\n'
date -Is
hostname
printf '\nOWN_JOBS\n'
squeue -u sunyiq -o '%.18i %.16P %.42j %.10T %.12M %.12l %.6D %R'
printf '\nGPU_PARTITIONS\n'
sinfo -p hgpu2p,hgpu2,hgpu4,hgpu8 -N -o '%N %P %t %G %m %c'
printf '\nPARTITION_LIMITS\n'
scontrol show partition hgpu4
scontrol show partition hgpu8
printf '\nNEW_ROOT_MUST_BE_ABSENT\n'
target=/data1/home/sunyiq/kalmannet_wrr_training_horizon_20260916
if [ -e "$target" ] || [ -L "$target" ]; then
  printf 'ROOT_ALREADY_EXISTS %s\n' "$target"
  exit 31
fi
printf 'ROOT_ABSENT %s\n' "$target"
df -h /data1/home/sunyiq
printf '\nEXISTING_ENV_READONLY\n'
ls -ld /data1/home/sunyiq/miniconda3/envs/knet_clean
/data1/home/sunyiq/miniconda3/envs/knet_clean/bin/python --version
printf '\nTRAIN_VALIDATION_ONLY\n'
data=/data1/home/sunyiq/kalmannet_wrr_hp_extension_20260902/repo/data/processed/high_flow_aug
stat -c '%n %s bytes' "$data/train_win800_19990101_01-20070527_03.pt" "$data/val_win800_20070527_04-20090314_13.pt"
sha256sum "$data/train_win800_19990101_01-20070527_03.pt" "$data/val_win800_20070527_04-20090314_13.pt"
printf '\nREAD_ONLY_PREFLIGHT_COMPLETE\n'
