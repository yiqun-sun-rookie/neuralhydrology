#!/usr/bin/env bash
set -eo pipefail
source /data1/home/sunyiq/miniconda3/etc/profile.d/conda.sh
conda activate nh_final
set -u
python -B - <<'EXPORT_003'
import base64,hashlib,io,json,tarfile,datetime,importlib.metadata as meta,sys
from pathlib import Path
root=Path('/data1/home/sunyiq/zhenjiang_fixed200_003_lstm_dev100_20261022_001')
sha=lambda raw:hashlib.sha256(raw).hexdigest()
spec=json.loads((root/'spec.json').read_bytes())
prepared=json.loads((root/'prepared.json').read_bytes())
manifest=json.loads((root/'model_manifest.json').read_bytes())
expected={'spec.json':prepared['spec_sha256'],'run_comparison.py':prepared['wrapper_sha256'],
          'inputs_2022.npz':prepared['input_sha256'],'model_manifest.json':prepared['model_manifest_sha256'],
          'sources/tide_fit.json':prepared['tide_parameters_sha256']}
for item in manifest:
 method=item['method']
 expected['sources/'+method+'/config.json']=item['source']['config']['sha256']
 expected['sources/'+method+'/epoch_100.pt']=item['source']['checkpoint']['sha256']
 expected['sources/parent_best.pt']=item['parent_hash']
names=sorted(set(expected)|{'prepared.json','original_foundation_source.json','excluded_calendar.json'})
buffer=io.BytesIO();files=[]
with tarfile.open(fileobj=buffer,mode='w:gz') as archive:
 for name in names:
  raw=(root/name).read_bytes();digest=sha(raw)
  if name in expected and digest!=expected[name]:raise ValueError('changed source: '+name)
  info=tarfile.TarInfo(name);info.size=len(raw);info.mode=0o644
  archive.addfile(info,io.BytesIO(raw))
  files.append({'path':name,'bytes':len(raw),'sha256':digest})
raw=buffer.getvalue()
if len(raw)>8000000:raise ValueError('bundle exceeds bounded receipt transfer size')
versions={}
for name in ['torch','numpy','scipy','pandas','matplotlib']:
 try:versions[name]=meta.version(name)
 except meta.PackageNotFoundError:versions[name]=None
print(json.dumps({'schema':'003-autodl-source-export-v1','at_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),
 'source_root':str(root),'files':files,'archive_bytes':len(raw),'archive_sha256':sha(raw),
 'python':sys.version,'environment_versions':versions,'source_writes':0,'training_submissions':0}))
print('BEGIN_003_ARCHIVE_BASE64')
encoded=base64.b64encode(raw).decode('ascii')
for pos in range(0,len(encoded),65536):print(encoded[pos:pos+65536])
print('END_003_ARCHIVE_BASE64')
EXPORT_003
