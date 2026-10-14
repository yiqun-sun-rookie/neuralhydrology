#!/bin/bash
set -eo pipefail
export PYTHONDONTWRITEBYTECODE=1
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python - <<'PY'
import json,hashlib,base64,zipfile,io
from pathlib import Path
p=Path('/data1/home/sunyiq/hydrol85935_revision_20261008_001')
r=Path('/data1/home/sunyiq/hydrol85935_temporal_attempts/hpc_v009_001/hydrol85935_temporal_persistence_20261011_001')
o=p/'execution/hpc_v009'
files={'source/frozen/manifest.json':o/'frozen/manifest.json','evidence/CODE.sha256':p/'versions/v004/CODE.sha256','evidence/DATA.sha256':p/'versions/v004/DATA.sha256','evidence/parent_binding_v010.json':r/'control/parent_binding_v010.json','temporal_code/protocol.json':r/'code/protocol.json'}
expected={100:'ba26567cee1ec9f58237f2c4bd6fa84b5aba982a144de2b439099a5d13161bcd',200:'7d570d8eeefa71095ef4d43f6a301d44731e022672222d145edc4ee8877e8a53',300:'a5472a6d38d5691afb99f24eb00455f43b121125e2d07d144341fb97ad202bc8'}
for seed in expected:
 index=json.loads((o/f'frozen/training_assets/s{seed}.json').read_text())
 assert index['assets']['weight']['sha256']==expected[seed]
 for rel in [f'frozen/training_assets/s{seed}.json',f'training/s{seed}/complete.json',f'training/s{seed}/training_config.yml',f'training/s{seed}/training_metadata.json']:
  files['source/'+rel]=o/rel
 for name,v in index['assets'].items():
  rel=index['run_relative_path']+'/'+v['relative_path'];q=o/rel
  assert hashlib.sha256(q.read_bytes()).hexdigest()==v['sha256']
  files['source/'+rel]=q
for q in sorted((r/'code/temporal_20261011').glob('*.py')):files['temporal_code/temporal_20261011/'+q.name]=q
assert any(k.endswith('/run.py') for k in files)
manifest={'source_parent':str(p),'source_execution':str(o),'source_training_job':241335,'seeds':[100,200,300],'epoch':30,'files':{k:{'sha256':hashlib.sha256(q.read_bytes()).hexdigest(),'size':q.stat().st_size,'source':str(q)} for k,q in files.items()},'science_executed':False,'formal_ownership_changed':False}
buf=io.BytesIO()
with zipfile.ZipFile(buf,'w',zipfile.ZIP_DEFLATED,compresslevel=1) as z:
 for k,q in files.items():z.writestr(k,q.read_bytes())
 z.writestr('transfer_manifest.json',json.dumps(manifest,sort_keys=True,indent=2))
raw=buf.getvalue()
assert len(raw)<8000000
c=r/'control/local_gpu_start_20261014_001';c.mkdir(exist_ok=True)
q=c/'source_assets.zip'
if q.exists():assert q.read_bytes()==raw
else:
 with q.open('xb') as f:f.write(raw)
print('TRANSFER_MANIFEST '+json.dumps(manifest),flush=True)
print('TRANSFER_ARCHIVE '+json.dumps({'size':len(raw),'sha256':hashlib.sha256(raw).hexdigest()}),flush=True)
print('TRANSFER_BASE64 '+base64.b64encode(raw).decode(),flush=True)
PY
