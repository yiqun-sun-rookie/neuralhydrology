#!/bin/bash
set -eo pipefail
root=/data1/home/sunyiq/id25_graice_author_matched_20261016_001
hostname
date -u +%FT%TZ
if [ -e "$root" ]; then echo B04_ROOT_ALREADY_EXISTS; else echo B04_ROOT_UNUSED; fi
squeue -h -u sunyiq -n id25_graice_m_261016 -o '%i|%j|%T|%M|%R'
sinfo -p hgpu2p -N -O nodelist,gres:18,gresused:28,cpusstate
for file in /data1/home/sunyiq/id25_regional_daily_storage_20261012_001/inputs/inputs.npz /data1/home/sunyiq/id25_graice_lstmnosif_20261015_001/venv/bin/python /data1/home/sunyiq/id25_graice_lstmnosif_20261015_001/venv/runtime_ready; do
  test -f "$file"
  stat -c '%n|%s|%y' "$file"
done
/data1/home/sunyiq/id25_graice_lstmnosif_20261015_001/venv/bin/python -m pip list --format=freeze | awk '/^(tensorflow|keras|numpy|scikit-learn|nvidia|matplotlib|pandas|h5py|ml-dtypes)/'
echo B04_PREFLIGHT_COMPLETE
