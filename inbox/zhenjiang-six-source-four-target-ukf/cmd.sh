#!/usr/bin/env bash
set -eo pipefail
source /data1/home/sunyiq/miniconda3/etc/profile.d/conda.sh
conda activate nh_final
set -u
export PYTHONDONTWRITEBYTECODE=1
python -B - <<'PY'
import hashlib,io,json,pathlib,subprocess,tarfile
inbox=pathlib.Path('inbox/zhenjiang-six-source-four-target-ukf')
seq=int((inbox/'seq').read_text());assert seq==218
payload=inbox/('payload_complete_comparison_20261006_'+str(seq)+'.tar.gz')
raw=payload.read_bytes()
assert hashlib.sha256(raw).hexdigest()=='b6cf983ce2a03b24bed24ec43bfea4761c62efb881336886c1a89a6ac27a002e'
root=pathlib.Path('/data1/home/sunyiq/zhenjiang_gradient_diagnostic_20261011_001')
if root.exists():raise FileExistsError('preserve existing diagnostic deployment; inspect its exclusive submission records without repeating')
with tarfile.open(fileobj=io.BytesIO(raw),mode='r:gz') as tar:
    members=tar.getmembers()
    assert len({m.name for m in members})==len(members)
    for member in members:
        p=pathlib.PurePosixPath(member.name)
        assert not p.is_absolute() and '..' not in p.parts and member.isfile()
    content={m.name:tar.extractfile(m).read() for m in members}
manifest_raw=content.pop('release_manifest.json');manifest=json.loads(manifest_raw)
assert manifest['diagnostic_root']==str(root) and not manifest['formal_training_sources_changed']
assert set(content)==set(manifest['files'])
for name,data in content.items():
    identity=manifest['files'][name]
    assert len(data)==identity['bytes'] and hashlib.sha256(data).hexdigest()==identity['sha256']
spec=json.loads(content['diagnostic_spec.json'])
assert spec['diagnostic_root']==str(root) and spec['formal_checkpoint_write_allowed'] is False
root.mkdir()
for name,data in content.items():
    p=root/name;p.parent.mkdir(parents=True,exist_ok=True)
    with p.open('xb') as f:f.write(data)
with (root/'release_manifest.json').open('xb') as f:f.write(manifest_raw)
(root/'logs').mkdir()
print(json.dumps({'status':'isolated_gradient_diagnostic_release_verified','root':str(root),'archive_sha256':hashlib.sha256(raw).hexdigest(),'formal_training_sources_changed':False,'evaluation_values_read':False}),flush=True)
subprocess.run(['python','-B',str(root/'hpc/submit_gradient_diagnostic_20261011.py')],cwd=root,check=True)
PY
