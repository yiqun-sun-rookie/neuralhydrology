#!/bin/bash
set -o pipefail
date -u '+UTC=%Y-%m-%dT%H:%M:%SZ'
printf '=== EXISTING_JOBS ===\n'
squeue -u "$USER" -o '%.18i %.14P %.35j %.8T %.10M %.30R'
printf '=== RESOURCES ===\n'
sinfo -p hgpu2p,hgpu4,hgpu8 -N -O nodelist,partition,gres:18,gresused:30,cpusstate
printf '=== STORAGE ===\n'
df -h "$HOME"
printf '=== OWN_TARGET ===\n'
if [ -e "/data1/home/sunyiq/precip_smallfit_hpc_20261012_v01/20261014T130222Z_a9e82e77_v01" ]; then echo TARGET_EXISTS; exit 10; else echo TARGET_UNUSED; fi
printf '=== TOOL_METADATA ===\n'
type sbatch
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -c 'import sys,importlib.metadata,json; print(json.dumps({"python":sys.version,"executable":sys.executable,"packages":{p:importlib.metadata.version(p) for p in ["torch","numpy","pandas","PyYAML","xarray","scipy"]}}))'
printf '=== TORCH_DIST_REQUIREMENTS ===\n'
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -c 'import importlib.metadata,json; print(json.dumps(importlib.metadata.requires("torch")))'
echo SMALLFIT_METADATA_COMPLETE
