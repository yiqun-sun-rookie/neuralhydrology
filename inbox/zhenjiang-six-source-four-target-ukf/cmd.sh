#!/usr/bin/env bash
set -euo pipefail
python3 - <<'PY'
import hashlib,io,json,pathlib,tarfile,subprocess
payload=pathlib.Path('inbox/zhenjiang-six-source-four-target-ukf/payload_complete_comparison_20261006_155.tar.gz'); raw=payload.read_bytes()
if hashlib.sha256(raw).hexdigest()!='5e7c0a481a213ce4d58d190678fa75f7d284e50432e446b3012c9551fd56791b': raise ValueError('archive differs')
root=pathlib.Path('/data1/home/sunyiq/zhenjiang_complete_comparison_20261006_002')
if root.exists(): raise FileExistsError('preserve existing recovery and jobs')
with tarfile.open(fileobj=io.BytesIO(raw),mode='r:gz') as tar:
    members=tar.getmembers()
    if len({m.name for m in members})!=len(members): raise ValueError('duplicate release path')
    for member in members:
        p=pathlib.PurePosixPath(member.name)
        if p.is_absolute() or '..' in p.parts or not member.isfile(): raise ValueError('unsafe release path')
    content={m.name:tar.extractfile(m).read() for m in members}
manifest=json.loads(content.pop('release_manifest.json'))
if set(manifest['files'])!=set(content): raise ValueError('release list differs')
for name,data in content.items():
    spec=manifest['files'][name]
    if len(data)!=spec['bytes'] or hashlib.sha256(data).hexdigest()!=spec['sha256']: raise ValueError('release file changed')
root.mkdir()
for name,data in content.items():
    p=root/name; p.parent.mkdir(parents=True,exist_ok=True); p.write_bytes(data)
(root/'release_manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
for name in ('logs','runs','reports','predictions','artifacts'): (root/name).mkdir(exist_ok=True)
print(json.dumps({'status':'recovery_release_verified','files':len(content),'code_hash':manifest['code_hash']}),flush=True)
subprocess.run(['python3','-B',str(root/'hpc/scheduler_submit.py')],cwd=str(root),check=True)
PY
