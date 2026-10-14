#!/bin/bash
set -eo pipefail
ROOT=/data1/home/sunyiq/china_soil_classification_12_hpc_20261014_001/runtime_recovery_v1
test -d /data1/home/sunyiq/china_soil_classification_12_hpc_20261014_001/preflight_v1
test ! -e "$ROOT"
test ! -e /data1/home/sunyiq/china_soil_classification_12_hpc_20261014_001/deps_v1
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -B - <<'PY_COPY'
import hashlib,json,os,pathlib
root=pathlib.Path('/data1/home/sunyiq/china_soil_classification_12_hpc_20261014_001/runtime_recovery_v1')
source=pathlib.Path(os.environ['HOME'])/'hpc_mailbox/inbox/china-soil12-20261014/payload/runtime_recovery_v1'
members=json.loads('[{"name":"runtime_recovery.py","local_path":"inputs/runtime_payload_v1/runtime_recovery.py","bytes":12086,"sha256":"6a70311ae0a33ff09909bb66e1071b8593e4dea779e070b0eed4f6170d65911a","git_blob_sha1":"74df67444a58a78ffe02b0f8137ff61394f93c0a"},{"name":"runtime_recovery.sbatch","local_path":"inputs/runtime_payload_v1/runtime_recovery.sbatch","bytes":981,"sha256":"c5e682022037425c59cb290210799d50fdf7909119657e41b1bdcb68340b535d","git_blob_sha1":"4f0195c8531b2d05ca3baad61ddc56ab4b1d66d2"},{"name":"RUNTIME_RECOVERY_CONTRACT.json","local_path":"inputs/runtime_payload_v1/RUNTIME_RECOVERY_CONTRACT.json","bytes":4747,"sha256":"4f2a3954c8b2f6c0bf088be560324ca5c87e911bdb6f820c85a03954fe94b713","git_blob_sha1":"0ecd117e663ea2bb807a4951be24dd02ea411b77"},{"name":"B_MISSING_SAMPLE_GEOMETRY_BYTES.geojson","local_path":"inputs/runtime_payload_v1/B_MISSING_SAMPLE_GEOMETRY_BYTES.geojson","bytes":97391,"sha256":"7c95350f5c283d73651b42dfce404615359a2feed09c719616541a0b07eea7e1","git_blob_sha1":"5779915b8427c7d34d9b5e1cb3ddc7763e2335c9"}]')
archive_identity=json.loads('null')
assert not root.exists() and len(members)==4 and sum(x['bytes'] for x in members)<=1048576
contents={}
for item in members:
    assert pathlib.Path(item['name']).name==item['name'] and item['bytes']<=2097152
    path=source/item['name']
    assert not path.is_symlink() and path.is_file() and path.stat().st_size==item['bytes']
    raw=path.read_bytes()
    assert len(raw)==item['bytes'] and hashlib.sha256(raw).hexdigest()==item['sha256']
    contents[item['name']]=raw
assert archive_identity is None and set(contents)=={'runtime_recovery.py','runtime_recovery.sbatch','RUNTIME_RECOVERY_CONTRACT.json','B_MISSING_SAMPLE_GEOMETRY_BYTES.geojson'}
root.mkdir()
(root/'logs').mkdir()
for name,raw in contents.items():
    with (root/name).open('xb') as f:f.write(raw)
print('OWN_RUNTIME_PAYLOAD_FILES='+str(len(members)))
print('OWN_RUNTIME_PAYLOAD_BYTES='+str(sum(x['bytes'] for x in members)))
print('OWN_RUNTIME_ORIGINAL_ARRAY_READS=0')
PY_COPY
cd "$ROOT"
test ! -e OWN_RUNTIME_SUBMIT_STARTED
test ! -e OWN_RUNTIME_JOB_ID
printf 'ONE_SUBMISSION_ONLY\n' > OWN_RUNTIME_SUBMIT_STARTED
set +e
submit_output=$(sbatch runtime_recovery.sbatch 2>&1)
submit_exit=$?
set -e
printf '%s\n' "$submit_output"
printf 'OWN_RUNTIME_SUBMIT_EXIT=%s\n' "$submit_exit"
test "$submit_exit" = 0
job=$(printf '%s\n' "$submit_output" | sed -n 's/^Submitted batch job \([0-9][0-9]*\)$/\1/p')
test -n "$job"
test "$(printf '%s\n' "$job" | wc -l)" = 1
printf '%s\n' "$job" > OWN_RUNTIME_JOB_ID
printf 'OWN_RUNTIME_JOB_ID=%s\n' "$job"
printf 'OWN_RUNTIME_SUBMIT_DONE\n'
