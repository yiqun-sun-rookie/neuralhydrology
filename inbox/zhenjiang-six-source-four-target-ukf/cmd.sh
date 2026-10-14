#!/usr/bin/env bash
set -eo pipefail
source /data1/home/sunyiq/miniconda3/etc/profile.d/conda.sh
conda activate nh_final
set -u
export PYTHONDONTWRITEBYTECODE=1
export OMP_NUM_THREADS=4
export MKL_NUM_THREADS=4
python -B - <<'PY'
import datetime,hashlib,io,json,pathlib,subprocess,tarfile
inbox=pathlib.Path('inbox/zhenjiang-six-source-four-target-ukf')
sequence=int((inbox/'seq').read_text())
assert sequence==443
payload=inbox/f'payload_complete_comparison_20261006_{sequence}.tar.gz'
raw=payload.read_bytes()
assert hashlib.sha256(raw).hexdigest()=='d1666abd21fcfddbbb6f700bfe7bc4665c2164cb13ff2ee41b25393e41b72235'
root=pathlib.Path('/data1/home/sunyiq/zhenjiang_complete_comparison_20261015_recovery_004')
assert not root.exists(),'existing release requires read-only reconciliation, never overwrite or repeat preparation'
with tarfile.open(fileobj=io.BytesIO(raw),mode='r:gz') as archive:
    members=archive.getmembers()
    assert members and all(m.isfile() for m in members)
    names=[m.name for m in members]
    assert len(names)==len(set(names))
    for member in members:
        relative=pathlib.PurePosixPath(member.name)
        assert not relative.is_absolute() and '..' not in relative.parts
        assert root in (root/member.name).resolve().parents
    content={m.name:archive.extractfile(m).read() for m in members}
manifest=json.loads(content['release_manifest.json'])
assert set(content)==set(manifest['files'])|{'release_manifest.json'}
assert manifest['code_hash']=='0a5820033841bb4274dab7be44719992e21cd31546bf45bc079becf0d8464cb7'
for name,item in manifest['files'].items():
    assert len(content[name])==item['bytes'] and hashlib.sha256(content[name]).hexdigest()==item['sha256']
root.mkdir(exist_ok=False)
for name,data in content.items():
    path=root/name
    path.parent.mkdir(parents=True,exist_ok=True)
    with path.open('xb') as stream:stream.write(data)
for name in ('runs','logs','artifacts'):(root/name).mkdir(exist_ok=True)
record={'status':'covariance_recovery_release_deployed','checked_at_beijing':datetime.datetime.now(datetime.timezone(datetime.timedelta(hours=8))).isoformat(),
        'root':str(root),'sequence':sequence,'code_hash':manifest['code_hash'],'payload_sha256':hashlib.sha256(raw).hexdigest(),
        'payload_bytes':len(raw),'release_manifest_sha256':hashlib.sha256(content['release_manifest.json']).hexdigest(),
        'files_authenticated':len(manifest['files']),'formal_training_submitted':False,'evaluation_values_read':False}
with (root/'records/covariance_release_deployment_443.json').open('x') as stream:json.dump(record,stream,sort_keys=True,indent=2);stream.write('\n')
print(json.dumps(record,sort_keys=True),flush=True)
subprocess.run(['python','-B',str(root/'hpc/prepare_covariance_recovery_20261015.py')],cwd=str(root),check=True)
subprocess.run(['python','-B',str(root/'hpc/audit_covariance_continuation_20261015.py')],cwd=str(root),check=True)
PY
