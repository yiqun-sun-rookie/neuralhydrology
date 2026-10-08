#!/usr/bin/env bash
set -eo pipefail
printf '=== identity ===\n'
date -Is
hostname
id
printf '=== existing user jobs - read only ===\n'
squeue -u "$USER" -o '%.18i %.14P %.35j %.10T %.12M %.8C %.20b %.30R'
printf '=== partition resources ===\n'
sinfo -p hgpu2p,hgpu2,hgpu4,hgpu8 -N -O NodeList:20,Partition:12,StateLong:16,CPUsState:24,Gres:30,GresUsed:40
printf '=== storage ===\n'
df -hP /data1/home/"$USER"
printf '=== intended root must not exist ===\n'
ROOT=/data1/home/sunyiq/hydrol85935_revision_20261008_001
if [ -e "$ROOT" ] || [ -L "$ROOT" ]; then printf 'ROOT_ALREADY_EXISTS\n'; exit 3; fi
printf 'ROOT_AVAILABLE %s\n' "$ROOT"
printf '=== known data and runtime paths ===\n'
for p in "$HOME/neuralhydrology/data/camels_us" "$HOME/neuralhydrology/data/CAMELS_US" "$HOME/miniconda3/envs/nh_final/bin/python" "$HOME/neuralhydrology/results/18_lstm_fair_531" "$HOME/adv531"; do
  if [ -e "$p" ]; then ls -ld "$p"; readlink -f "$p"; else printf 'MISSING %s\n' "$p"; fi
done
printf '=== known original model identities ===\n'
for d in "$HOME/neuralhydrology/results/18_lstm_fair_531" "$HOME/adv531/results/18_lstm_fair_531"; do
  if [ -d "$d" ]; then
    find "$d" -mindepth 1 -maxdepth 2 -type f \( -name 'model_epoch030.pt' -o -name 'config.yml' \) -print
  fi
done
printf '=== compatibility metadata ===\n'
type sbatch
if [ -f "$HOME/miniconda3/envs/nh_final/conda-meta/history" ]; then tail -n 8 "$HOME/miniconda3/envs/nh_final/conda-meta/history"; fi
