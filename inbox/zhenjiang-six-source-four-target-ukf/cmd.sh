#!/usr/bin/env bash
set -eo pipefail
source /data1/home/sunyiq/miniconda3/etc/profile.d/conda.sh
conda activate nh_final
set -u
export PYTHONDONTWRITEBYTECODE=1
python -B - <<'PY'
import hashlib,io,json,pathlib,subprocess,tarfile
payload=pathlib.Path('inbox/zhenjiang-six-source-four-target-ukf/payload_complete_comparison_20261006_242.tar.gz')
raw=payload.read_bytes();assert hashlib.sha256(raw).hexdigest()=='43f8899e911899bba9e1eecb0c77f2f8a4e4a4837868d52b5bef915cefeb3d0b'
root=pathlib.Path('/data1/home/sunyiq/zhenjiang_complete_comparison_20261012_recovery_003')
assert not root.exists(),'preserve existing recovery; inspect before any further action'
with tarfile.open(fileobj=io.BytesIO(raw),mode='r:gz') as t:
 members=t.getmembers();assert len({m.name for m in members})==len(members)
 assert all(m.isfile() and not pathlib.PurePosixPath(m.name).is_absolute() and '..' not in pathlib.PurePosixPath(m.name).parts for m in members)
 content={m.name:t.extractfile(m).read() for m in members}
manifest=json.loads(content['release_manifest.json'])
assert set(content)==set(manifest['files'])|{'release_manifest.json'}
for name,entry in manifest['files'].items():
 assert len(content[name])==entry['bytes'] and hashlib.sha256(content[name]).hexdigest()==entry['sha256'],name
root.mkdir()
for name,b in content.items():
 p=root/name;p.parent.mkdir(parents=True,exist_ok=True)
 with p.open('xb') as f:f.write(b)
for name in ['runs','logs','artifacts']:(root/name).mkdir(exist_ok=True)
print(json.dumps({'status':'gradient_recovery_release_verified','root':str(root),'code_hash':manifest['code_hash'],'files':len(content)}),flush=True)
subprocess.run(['python','-B',str(root/'hpc/prepare_recovery.py')],cwd=str(root),check=True)
subprocess.run(['python','-B',str(root/'hpc/submit_recovery.py')],cwd=str(root),check=True)
PY
