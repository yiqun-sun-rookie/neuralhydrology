#!/bin/bash
set -u
root=/data1/home/sunyiq/id25_graice_author_matched_20261016_001
test "$(cat "$root/job_id.txt")" = 244024 || exit 2
export PYTHONNOUSERSITE=1 PYTHONDONTWRITEBYTECODE=1
unset PYTHONPATH
probe() { printf '\nQUERY: %s\n' "$*"; timeout 40 "$@"; result=$?; printf 'QUERY_EXIT_CODE=%s\n' "$result"; }
probe date -Iseconds
probe cat "$root/job_id.txt" "$root/submissions.tsv"
probe scontrol -d show job 244024
probe sacct -j 244024 --format=JobIDRaw,JobName,Partition,State,ExitCode,Start,End,Elapsed,NodeList -n -P
probe squeue -h -u sunyiq -n id25_graice_m_261016 -o '%i|%j|%T|%P|%S|%R'
for name in logs/b04-244024.out logs/b04-244024.err; do
  if [ -f "$root/$name" ]; then printf '\nFILE=%s\n' "$root/$name"; tail -n 50 "$root/$name"; fi
done
for name in status.json interface_check.json runtime.json report.json failure_244024.json; do
  if [ -f "$root/$name" ]; then probe cat "$root/$name"; fi
done
probe sinfo -p hgpu2p,hgpu2 -N -O 'partition:12,nodelist:16,gres:16,gresused:28,cpusstate:22'
probe sinfo -p hgpu2p,hgpu2 -N -o '%P|%N|%t|%E'
for node in ngu003 ngu009; do probe scontrol -o show node "$node"; done
"$root/venv/bin/python" - <<'PY'
import importlib.metadata as md, json, os, sys
names=['tensorflow','numpy','h5py','scipy','scikit-learn','nvidia-cuda-runtime-cu12','nvidia-cuda-nvrtc-cu12','nvidia-cudnn-cu12','nvidia-cublas-cu12']
records=[]
for name in names:
    dist=md.distribution(name)
    wheel=dist.read_text('WHEEL') or ''
    records.append(dict(name=name,version=dist.version,wheel_tags=[x for x in wheel.splitlines() if x.startswith('Tag:')]))
print(json.dumps(dict(python=sys.version,metadata_host_glibc=os.confstr('CS_GNU_LIBC_VERSION'),packages=records,numerical_execution=False)))
PY
printf 'METADATA_EXIT_CODE=%s\n' "$?"
probe "$root/venv/bin/python" -m pip check
exit 0
