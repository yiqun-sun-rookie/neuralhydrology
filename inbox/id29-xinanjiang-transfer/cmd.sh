#!/bin/bash
set -eo pipefail
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -B - <<'PY'
import base64,hashlib,io,json,pathlib,tarfile
root=pathlib.Path('/data1/home/sunyiq/id29_xinanjiang_transfer_20260907_v01')
summary=root/'pilot/summary.json'
expected='f5f124944f652809dd33fbc9c0fbb9dac44bd30c3ec146cd760e1d138aa70640'
if hashlib.sha256(summary.read_bytes()).hexdigest()!=expected:
    raise ValueError('pilot summary changed')
files=sorted(p for p in (root/'pilot').rglob('*') if p.is_file())
files += [root/'pilot-tests.xml',root/'pilot_job_id.txt']
buffer=io.BytesIO()
with tarfile.open(fileobj=buffer,mode='w:gz') as archive:
    for path in files:
        archive.add(path,arcname=path.relative_to(root).as_posix(),recursive=False)
payload=buffer.getvalue()
print('EXPORT_FILES',len(files))
print('EXPORT_SHA256',hashlib.sha256(payload).hexdigest())
print('BEGIN_BASE64_PILOT')
print(base64.b64encode(payload).decode('ascii'))
print('END_BASE64_PILOT')
PY
