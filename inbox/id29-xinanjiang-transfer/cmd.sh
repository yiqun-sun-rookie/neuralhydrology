#!/bin/bash
# Read-only file export of the completed development stage; no model computation.
set -eo pipefail
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -B - <<'PY'
import base64,hashlib,io,json,pathlib,subprocess,tarfile
root=pathlib.Path('/data1/home/sunyiq/id29_xinanjiang_transfer_20260907_v01')
digest=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
identity='59a8f8b50776086c5b1263e441cfc9cf80299b80feca24a60919d582d5d21545'
transfer='5f644f707c9b67eacf89562e7484cfc42f859dfcdad597b1eeb58584a99a2d04'
if digest(root/'bundle/MANIFEST.json')!=identity:
    raise ValueError('bundle identity changed')
for name,expected in json.loads((root/'bundle/MANIFEST.json').read_text()).items():
    if digest(root/'bundle'/name)!=expected:
        raise ValueError('bundle file changed: '+name)
status=subprocess.run(['sacct','-j','223708','-n','-P','--format=JobIDRaw,State,ExitCode'],
                      check=True,capture_output=True,text=True).stdout.splitlines()
if not any(row.split('|')[:3]==['223708','COMPLETED','0:0'] for row in status):
    raise ValueError('development is not successfully complete')
stage=root/'development'
summary=json.loads((stage/'summary.json').read_text())
if (summary.get('status')!='success' or summary.get('candidate_evaluations')!=37632
        or summary.get('successful_arm_basins')!=1176 or summary.get('transfer_sha256')!=transfer
        or digest(stage/'frozen_transfer.json')!=transfer):
    raise ValueError('development prerequisite identity/count mismatch')
files=sorted(p for p in stage.rglob('*') if p.is_file())
files += [root/'development_job_id.txt',root/'approve_development.json',
          root/'logs/id29-xaj-learn_223708.out',root/'logs/id29-xaj-learn_223708.err']
if any(p.is_symlink() or not p.is_file() or not p.resolve().is_relative_to(root) for p in files):
    raise ValueError('unsafe export path')
manifest={p.relative_to(root).as_posix():digest(p) for p in files}
buffer=io.BytesIO()
with tarfile.open(fileobj=buffer,mode='w:gz') as archive:
    for path in files:
        archive.add(path,arcname=path.relative_to(root).as_posix(),recursive=False)
    value=json.dumps(manifest,sort_keys=True,indent=2).encode()
    info=tarfile.TarInfo('EXPORT_MANIFEST.json')
    info.size=len(value)
    archive.addfile(info,io.BytesIO(value))
payload=buffer.getvalue()
if len(payload)>64*1024*1024:
    raise ValueError('archive exceeds mailbox file limit; use separately reviewed chunk export')
metadata={'stage':'development','files':len(files),'archive_bytes':len(payload),
          'archive_sha256':hashlib.sha256(payload).hexdigest(),
          'summary_sha256':digest(stage/'summary.json'),'transfer_sha256':transfer,
          'bundle_manifest_sha256':identity,'development_job':'223708'}
print('EXPORT_METADATA',json.dumps(metadata,sort_keys=True))
print('BEGIN_BASE64_STAGE')
print(base64.b64encode(payload).decode('ascii'))
print('END_BASE64_STAGE')
PY
