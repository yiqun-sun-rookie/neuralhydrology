#!/usr/bin/env bash
set -eo pipefail
source /data1/home/sunyiq/miniconda3/etc/profile.d/conda.sh
conda activate nh_final
set -u
export PYTHONDONTWRITEBYTECODE=1
python -B - <<'PY'
import hashlib,io,json,pathlib,subprocess,tarfile
inbox=pathlib.Path('inbox/zhenjiang-six-source-four-target-ukf')
seq=int((inbox/'seq').read_text())
payload=inbox/('payload_complete_comparison_20261006_'+str(seq)+'.tar.gz')
raw=payload.read_bytes()
if hashlib.sha256(raw).hexdigest()!='0b61c2061b7070e0071947e9d5f86a7953f0c9d345d37d413e2d778ef250f7b8':raise ValueError('recovery archive differs')
root=pathlib.Path('/data1/home/sunyiq/zhenjiang_complete_comparison_20261006_recovery_001')
if root.exists():raise FileExistsError('preserve existing recovery and inspect it')
with tarfile.open(fileobj=io.BytesIO(raw),mode='r:gz') as tar:
 members=tar.getmembers()
 if len({m.name for m in members})!=len(members):raise ValueError('duplicate recovery archive path')
 for m in members:
  p=pathlib.PurePosixPath(m.name)
  if p.is_absolute() or '..' in p.parts or not m.isfile():raise ValueError('unsafe recovery archive entry')
 content={m.name:tar.extractfile(m).read() for m in members}
manifest=json.loads(content.pop('release_manifest.json'))
if set(content)!=set(manifest['files']):raise ValueError('recovery archive allow-list differs')
for name,data in content.items():
 spec=manifest['files'][name]
 if len(data)!=spec['bytes'] or hashlib.sha256(data).hexdigest()!=spec['sha256']:raise ValueError('recovery source changed')
root.mkdir()
for name,data in content.items():
 p=root/name;p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(data)
(root/'release_manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
for name in ('logs','runs','reports','predictions'):(root/name).mkdir(exist_ok=True)
print(json.dumps({'status':'isolated_numeric_recovery_release_verified','root':str(root),'code_hash':manifest['code_hash']}),flush=True)
subprocess.run(['python','-B',str(root/'hpc/prepare_recovery.py')],cwd=root,check=True)
subprocess.run(['python','-B',str(root/'hpc/submit_recovery.py')],cwd=root,check=True)
PY
