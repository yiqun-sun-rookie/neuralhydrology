#!/usr/bin/env bash
# Read-only inspection before creating the isolated run or submitting any job.
set -eo pipefail
date -u '+UTC=%Y-%m-%dT%H:%M:%SZ'
printf 'HOME_PATH=%s\n' "$HOME"
printf 'HOST=%s\n' "$(hostname)"
if [ -e "$HOME/precip_dynamic_filter_20260930" ]; then
    echo ROOT_COLLISION
    exit 21
fi
echo ROOT_AVAILABLE
test -d "$HOME/neuralhydrology/data/camels_us"
test -f "$HOME/neuralhydrology/neuralhydrology/evaluation/assimilation.py"
test -f "$HOME/neuralhydrology/neuralhydrology/utils/assimilationconfig.py"
sha256sum "$HOME/neuralhydrology/neuralhydrology/evaluation/assimilation.py" "$HOME/neuralhydrology/neuralhydrology/utils/assimilationconfig.py"
df -h "$HOME"
sinfo -p hgpu4,hgpu8,hgpu2p -N -O nodelist,partition,gres:18,gresused:30,cpusstate
squeue -u "$USER" -o '%.18i %.14P %.30j %.8T %.10M %.20R'
scontrol show partition hgpu4
