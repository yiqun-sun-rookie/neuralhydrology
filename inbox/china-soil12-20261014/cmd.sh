#!/bin/bash
set -eo pipefail
umask 077
ROOT=/data1/home/sunyiq/china_soil_classification_12_hpc_20261014_001/independent_v1
test ! -e "$ROOT"
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -B - <<'PY_COPY'
import hashlib,json,os,pathlib
root=pathlib.Path('/data1/home/sunyiq/china_soil_classification_12_hpc_20261014_001/independent_v1')
assert root.parent.resolve(strict=True)==root.parent and not root.exists()
source=pathlib.Path(os.environ['HOME'])/'hpc_mailbox/inbox/china-soil12-20261014/payload/independent_v1'
members=json.loads('[{"name":"INDEPENDENT_CONTRACT.json","local_path":"inputs/soil_independent_payload_v2/INDEPENDENT_CONTRACT.json","bytes":1181,"sha256":"3056c9da3e5e201278b60e3fdc6157ce76532dc05cd0c8e8bbb3010fdbed688e","git_blob_sha1":"82f9100f56621b4d4b2e8ab38cfc233be5060a08"},{"name":"independent_recompute.py","local_path":"inputs/soil_independent_payload_v2/independent_recompute.py","bytes":17069,"sha256":"6dcccf88c471bc8a269503a9def9b143baf104babdf4faf75e020357261bf726","git_blob_sha1":"1da4492c46426f56d1463b33fdd91cfbbfb1ce7b"},{"name":"soil_independent.sbatch","local_path":"inputs/soil_independent_payload_v2/soil_independent.sbatch","bytes":1099,"sha256":"c4fab4c45e23ccbb82a2f681ee4bd0a07977ac1c9e874ff19ad38796eed560f3","git_blob_sha1":"52b5870a3c99e8e48fd85d89cb9c436e63cd30d6"}]')
assert len(members)==3 and sum(x['bytes'] for x in members)<=131072
contents={}
for row in members:
    name=row['name']
    assert pathlib.Path(name).name==name
    path=source/name
    assert path.is_file() and not path.is_symlink() and path.stat().st_size==row['bytes']
    raw=path.read_bytes()
    assert len(raw)==row['bytes'] and hashlib.sha256(raw).hexdigest()==row['sha256']
    contents[name]=raw
entry=json.loads(contents['INDEPENDENT_CONTRACT.json'])
for key in ('main_summary','numerical_contract'):
    row=entry[key]
    path=pathlib.Path(row['path'])
    assert path.is_file() and not path.is_symlink() and path.stat().st_size==row['bytes']
    raw=path.read_bytes()
    assert len(raw)==row['bytes'] and hashlib.sha256(raw).hexdigest()==row['sha256']
assert set(contents)=={'INDEPENDENT_CONTRACT.json','independent_recompute.py','soil_independent.sbatch'}
root.mkdir()
(root/'logs').mkdir()
for name,raw in contents.items():
    with (root/name).open('xb') as f:f.write(raw)
print('OWN_SOIL_PAYLOAD_FILES=3')
print('OWN_SOIL_PAYLOAD_BYTES='+str(sum(x['bytes'] for x in members)))
print('OWN_SOIL_LOCAL_ARRAY_READS=0')
print('OWN_SOIL_EXTERNAL_SOURCE_GETS=0')
PY_COPY
cd "$ROOT"
test ! -e OWN_SOIL_SUBMIT_STARTED
test ! -e OWN_SOIL_JOB_ID
printf 'ONE_SUBMISSION_ONLY\n' > OWN_SOIL_SUBMIT_STARTED
set +e
output=$(sbatch soil_independent.sbatch 2>&1)
code=$?
set -e
printf '%s\n' "$output"
printf 'OWN_SOIL_SUBMIT_EXIT=%s\n' "$code"
test "$code" = 0
job=$(printf '%s\n' "$output" | sed -n 's/^Submitted batch job \([0-9][0-9]*\)$/\1/p')
test -n "$job"
test "$(printf '%s\n' "$job" | wc -l)" = 1
printf '%s\n' "$job" > OWN_SOIL_JOB_ID
printf 'OWN_SOIL_JOB_ID=%s\n' "$job"
printf 'OWN_SOIL_SUBMIT_DONE\n'
