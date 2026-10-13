#!/usr/bin/env bash
set +u
set -eo pipefail
source /data1/home/sunyiq/miniconda3/etc/profile.d/conda.sh
conda activate nh_final
set -u
export PYTHONDONTWRITEBYTECODE=1
python -B - <<'PY'
import hashlib,io,json,pathlib,subprocess,sys,tarfile
inbox=pathlib.Path('inbox/zhenjiang-six-source-four-target-ukf');seq=int((inbox/'seq').read_text());raw=(inbox/('payload_complete_comparison_20261006_'+str(seq)+'.tar.gz')).read_bytes()
assert hashlib.sha256(raw).hexdigest()=='c47922886f5919ad372a20c4914a144e8a2b2ee8b37de5fdb294861df42b2c62'
root=pathlib.Path('/data1/home/sunyiq/zhenjiang_complete_comparison_20261012_recovery_003')
with tarfile.open(fileobj=io.BytesIO(raw),mode='r:gz') as archive:
    entries={}
    for member in archive.getmembers():
        name=pathlib.PurePosixPath(member.name)
        assert member.isfile() and not name.is_absolute() and '..' not in name.parts and member.name not in entries
        assert member.name.startswith(('hpc/','records/scheduler_queue_repair_20261014_001'))
        entries[member.name]=archive.extractfile(member).read()
manifest=json.loads(entries['records/scheduler_queue_repair_20261014_001_manifest.json'])
assert set(entries)==set(manifest['payload_files'])|{'records/scheduler_queue_repair_20261014_001_manifest.json'}
for name,expected in manifest['payload_files'].items():assert hashlib.sha256(entries[name]).hexdigest()==expected['sha256'] and len(entries[name])==expected['bytes']
for name,data in entries.items():
    target=root/name;assert target.resolve().is_relative_to(root.resolve());target.parent.mkdir(parents=True,exist_ok=True)
    if target.exists():assert target.read_bytes()==data
    else:
        with target.open('xb') as f:f.write(data)
print(json.dumps({'status':'scheduler_queue_repair_payload_verified','files':len(entries),'payload_sha256':hashlib.sha256(raw).hexdigest(),'training_sources_modified':False}),flush=True)
subprocess.run([sys.executable,'-B',str(root/'hpc/admit_scheduler_queue_repair_20261014.py')],cwd=root,check=True)
PY
