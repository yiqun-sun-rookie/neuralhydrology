#!/bin/bash
set -eu
root=/data1/home/sunyiq/id25_graice_author_matched_20261016_001
test "$(cat "$root/job_id.txt")" = 244024
export PYTHONNOUSERSITE=1 PYTHONDONTWRITEBYTECODE=1
unset PYTHONPATH
printf 'CHECK_TIME='
date -Iseconds
timeout 30 scontrol -d show job 244024
timeout 30 sinfo -p hgpu2p,hgpu2 -N -O 'partition:12,nodelist:16,gres:16,gresused:28,cpusstate:22'
timeout 30 sinfo -p hgpu2p,hgpu2 -N -o '%P|%N|%t|%E'
for node in ngu003 ngu009; do timeout 30 scontrol -o show node "$node"; done
test -f "$root/venv/runtime_ready"
grep -qx 'exit_code=0' "$root/env_status_v002.txt"
"$root/venv/bin/python" - <<'PY'
import importlib.metadata as md, json, os, sys
names = ['tensorflow','numpy','h5py','scipy','scikit-learn','nvidia-cuda-runtime-cu12','nvidia-cuda-nvrtc-cu12','nvidia-cudnn-cu12','nvidia-cublas-cu12']
records = []
for name in names:
    dist=md.distribution(name)
    wheel=dist.read_text('WHEEL') or ''
    records.append(dict(name=name,version=dist.version,wheel_tags=[x for x in wheel.splitlines() if x.startswith('Tag:')]))
assert md.version('tensorflow')=='2.15.1'
assert md.version('nvidia-cuda-runtime-cu12')=='12.2.140'
assert md.version('nvidia-cudnn-cu12')=='8.9.4.25'
print(json.dumps(dict(python=sys.version,metadata_host_glibc=os.confstr('CS_GNU_LIBC_VERSION'),packages=records,numerical_execution=False)))
PY
"$root/venv/bin/python" -m pip check
printf 'B04_METADATA_COMPATIBILITY_CHECK_PASSED\n'
