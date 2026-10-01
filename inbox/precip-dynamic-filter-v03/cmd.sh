#!/usr/bin/env bash
# Locate existing read-only inputs; no directories or jobs are changed.
set -o pipefail
date -u '+UTC=%Y-%m-%dT%H:%M:%SZ'
for task_candidate in "$HOME/neuralhydrology" "$HOME/neuralhydrology/data/camels_us" "$HOME/neuralhydrology/data/CAMELS_US" "$HOME/data/camels_us" "$HOME/data/CAMELS_US" "$HOME/nh_data/camels_us" "$HOME/precip_input_da_2026_09"; do
    if [ -d "$task_candidate" ]; then
        printf 'EXISTS=%s\n' "$task_candidate"
    else
        printf 'MISSING=%s\n' "$task_candidate"
    fi
done
df -h "$HOME"
sinfo -p hgpu4,hgpu8,hgpu2p -N -O nodelist,partition,gres:18,gresused:30,cpusstate
squeue -u "$USER" -o '%.18i %.14P %.30j %.8T %.10M %.20R'
scontrol show partition hgpu4
