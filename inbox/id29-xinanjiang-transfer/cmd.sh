#!/bin/bash
set -eo pipefail
printf 'SECOND_MODEL_READONLY_RESOURCE_PROBE\n'
date -Is
hostname
printf 'ROOT_EXISTS='
if test -e /data1/home/sunyiq/id29_xinanjiang_transfer_20260907_v01; then echo yes; else echo no; fi
printf 'DATA_EXISTS='
if test -d /data1/home/sunyiq/neuralhydrology/data/camels_us; then echo yes; else echo no; fi
command -v sbatch
sinfo -o '%P %a %l %D %c %m %G' | head -25
printf 'CONDA_CANDIDATES\n'
for p in /data1/home/sunyiq/miniconda3/etc/profile.d/conda.sh /data1/home/sunyiq/anaconda3/etc/profile.d/conda.sh; do
  if test -f "$p"; then printf '%s\n' "$p"; fi
done
printf 'ENV_CANDIDATES\n'
for p in /data1/home/sunyiq/miniconda3/envs/nh_final/bin/python /data1/home/sunyiq/anaconda3/envs/nh_final/bin/python; do
  if test -x "$p"; then
    "$p" -B -c 'import sys,importlib.metadata as m; print(sys.executable); print({x:m.version(x) for x in ["numpy","pandas","numba","cma","pytest"]})'
  fi
done
printf 'PROBE_COMPLETE\n'
