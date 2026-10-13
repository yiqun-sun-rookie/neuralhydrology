#!/bin/bash
set -eo pipefail
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -B - <<'PY'
import base64,gzip,hashlib,io,json,tarfile
from pathlib import Path
original=Path('/data1/home/sunyiq/china_radiation_16_hpc_20261012_001/execution_v1/raw_recovery_attempt1/coordinate_repair_attempt2');entry=Path('/data1/home/sunyiq/china_radiation_16_hpc_20261012_001/execution_v1/raw_recovery_attempt1/coordinate_repair_attempt2/projection_argument_entry_v1');patch=Path('/data1/home/sunyiq/china_radiation_16_hpc_20261012_001/execution_v1/raw_recovery_attempt1/coordinate_repair_attempt2/projection_argument_repair_v1')
assert original.is_dir() and not original.is_symlink()
assert not entry.exists() and not entry.is_symlink() and not patch.exists() and not patch.is_symlink()
assert (original/'OWN_SUMMARY_JOB_ID.txt').read_text().strip()=='241367'
for name,expected in [('FAILED_BATCH_INPUTS.json','08dd954e645ec34442c874483e5e1fdbc3f862e72c2cb9e106e75a88ca301ae9'),('summary_requests_v1/REQUEST_MANIFEST.json','7b3ce8d0cb52d59e780503273dfa0ccb8b109af80668cc5da76a4e4769a8936f'),('ALGORITHMS_RESPONSE_BODY.bin','74d59ec8ff9194bcfa8f2e4bcdd8fed9422bb36ef10cf9d665a7482b3b80763d')]:
    p=original/name;assert p.is_file() and not p.is_symlink();assert hashlib.sha256(p.read_bytes()).hexdigest()==expected
packet=base64.b64decode('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',validate=True);manifest={'bytes': 3003, 'sha256': '0ffc8e87ae57035c223dac5de95261f788f17924eae499c98002c3e94da5a9ea', 'members': [{'name': 'hpc_projection_argument_repair.py', 'bytes': 7296, 'sha256': '4fcd1740026c4899b8f2576106399152cdbf4a63069cf0bf7790dc0c15a89ee6'}, {'name': 'projection_argument_repair.sbatch', 'bytes': 1096, 'sha256': '6de1f94fe747dd49ea219adf858905e65e63d18057ccff82183ae3d1e6805350'}]}
assert len(packet)==manifest['bytes'] and hashlib.sha256(packet).hexdigest()==manifest['sha256']
plain=gzip.decompress(packet);assert len(plain)<=1048576
prepared=[]
with tarfile.open(fileobj=io.BytesIO(plain),mode='r:') as archive:
    items=archive.getmembers();expected={row['name']:row for row in manifest['members']}
    assert len(items)==len(expected)==2 and {item.name for item in items}==set(expected)
    for item in items:
        assert item.isfile() and item.name==Path(item.name).name
        data=archive.extractfile(item).read();row=expected[item.name]
        assert len(data)==item.size==row['bytes'] and hashlib.sha256(data).hexdigest()==row['sha256']
        prepared.append((item.name,data))
assert sum(p.stat().st_size for p in original.parent.rglob('*') if p.is_file())+sum(len(x) for _,x in prepared)<=4294967296
entry.mkdir();(entry/'logs').mkdir()
for name,data in prepared:
    with (entry/name).open('xb') as out:out.write(data)
    print('OWN_PROJECTION_DEPLOY_SHA256='+hashlib.sha256(data).hexdigest()+' '+name)
PY
task_entry='/data1/home/sunyiq/china_radiation_16_hpc_20261012_001/execution_v1/raw_recovery_attempt1/coordinate_repair_attempt2/projection_argument_entry_v1'
set +e
task_submit=$(sbatch "$task_entry/projection_argument_repair.sbatch" 2>&1)
task_exit=$?
set -e
printf '%s\n' "$task_submit"
printf 'OWN_PROJECTION_SUBMIT_EXIT=%s\n' "$task_exit"
test "$task_exit" = 0
if [[ "$task_submit" =~ ^Submitted\ batch\ job\ ([0-9]+)$ ]]; then
    task_job=${BASH_REMATCH[1]}
else exit 1; fi
test ! -e "$task_entry/OWN_PROJECTION_JOB_ID.txt"
printf '%s\n' "$task_job" > "$task_entry/OWN_PROJECTION_JOB_ID.txt"
printf 'OWN_REQUEST_BUILD_JOB_ID=%s\nOWN_PROJECTION_JOB_ID=%s\n' "$task_job" "$task_job"
printf 'OWN_PROJECTION_SUBMIT_DONE\n'
