#!/usr/bin/env bash
set -eo pipefail
source /data1/home/sunyiq/miniconda3/etc/profile.d/conda.sh
conda activate nh_final
set -u
export PYTHONDONTWRITEBYTECODE=1
python -B - <<'PY'
import datetime,hashlib,io,json,pathlib,tarfile
inbox=pathlib.Path('inbox/zhenjiang-six-source-four-target-ukf')
sequence=int((inbox/'seq').read_text())
assert sequence==435
payload=inbox/f'payload_complete_comparison_20261006_{sequence}.tar.gz'
raw=payload.read_bytes()
assert hashlib.sha256(raw).hexdigest()=='772592ab97413af0569a100c554f2689f07161bdd903f799765400e1f9663d2f'
base=pathlib.Path('/data1/home/sunyiq')
root=base/'zhenjiang_covariance_factor_audit_20261015_001'
assert not root.exists(),'new diagnostic root already exists: inspect original deployment, never overwrite or repeat submission'
with tarfile.open(fileobj=io.BytesIO(raw),mode='r:gz') as archive:
    members=archive.getmembers()
    assert members and all(m.isfile() for m in members)
    names=[m.name for m in members]
    assert len(names)==len(set(names))
    for member in members:
        relative=pathlib.PurePosixPath(member.name)
        assert not relative.is_absolute() and '..' not in relative.parts
        assert relative.parts[0]==root.name and len(relative.parts)>1
        assert root in (base/member.name).resolve().parents
    root.mkdir(exist_ok=False)
    for member in members:
        path=base/member.name
        path.parent.mkdir(parents=True,exist_ok=True)
        with path.open('xb') as stream:
            stream.write(archive.extractfile(member).read())
manifest=json.loads((root/'package_manifest.json').read_text())
for relative,identity in manifest['files'].items():
    path=root/relative
    assert hashlib.sha256(path.read_bytes()).hexdigest()==identity['sha256'] and path.stat().st_size==identity['bytes']
(root/'logs').mkdir(exist_ok=True)
record={'status':'new_saved_matrix_audit_deployed','checked_at_beijing':datetime.datetime.now(datetime.timezone(datetime.timedelta(hours=8))).isoformat(),
    'root':str(root),'sequence':sequence,'payload_sha256':hashlib.sha256(raw).hexdigest(),'payload_bytes':len(raw),
    'package_manifest_sha256':hashlib.sha256((root/'package_manifest.json').read_bytes()).hexdigest(),
    'files_authenticated':len(manifest['files']),'source_training_files_written':False,'evaluation_values_read':False}
with (root/'records/package_deployment.json').open('x') as f:json.dump(record,f,sort_keys=True,indent=2);f.write('\n')
print(json.dumps(record,sort_keys=True),flush=True)
PY
python -B /data1/home/sunyiq/zhenjiang_covariance_factor_audit_20261015_001/hpc/submit_saved_matrix_audit.py
python -B /data1/home/sunyiq/zhenjiang_covariance_factor_audit_20261015_001/hpc/probe_saved_matrix_audit.py
