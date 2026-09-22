#!/usr/bin/env bash
# Read-only export for the completed two-basin technical probe.  The controller
# publishes this file verbatim; it neither creates files nor imports the model.
set -euo pipefail
ROOT=/data1/home/sunyiq/kalmannet_tukf09_scaled_noise_rehearsal_20260922/narrow_probe_v2/run/model
EXPECTED_MANIFEST=b552c509714680fffd2ca2a656f588eb4185297025d498d63826dbd064b8acb6
EXPECTED_A=25e58e5d84a4f174040e460df5c5f5a7495115b9ddfa346d87d6f3efab88de4d
EXPECTED_B=0660896bf2964bfd272d793e6f9ade4168329ecb4e6750c654442405a555276f
export ROOT EXPECTED_MANIFEST EXPECTED_A EXPECTED_B
python3 - <<'PY'
import base64, hashlib, io, json, os, stat, zipfile
from pathlib import Path, PurePosixPath

def fail(message): raise SystemExit('short evidence refusal: ' + message)
root = Path(os.environ['ROOT'])
if root != Path('/data1/home/sunyiq/kalmannet_tukf09_scaled_noise_rehearsal_20260922/narrow_probe_v2/run/model'):
 fail('fixed root changed')
manifest_path = root / 'manifest.final.sha256.json'
expected = {
 'basin_01047000/probe_arrays.npz': (os.environ['EXPECTED_A'], 80757),
 'basin_01047000/summary.json': ('02e606e480d1548a5a08278245dd28b500d29d7cb1f098e5c195de55789725d9', 487),
 'basin_01142500/probe_arrays.npz': (os.environ['EXPECTED_B'], 79664),
 'basin_01142500/summary.json': ('bdb35fe7a211656f92fb0d268a5707f9a38d05ebb8d1157b8f6e884204f5c97f', 493),
 'run_summary.json': ('dbc3c2cb5560bcbdd08b83e81bf2b11b030d5b0443806998f445386d24f82e5f', 1287),
 'started.json': ('920b4f99fc0f64934571529b9831dd1c9b920df6bf8e4787099cf10f51822610', 4072),
}
def regular(path, allowed_root=root):
 if not path.is_absolute() or not allowed_root.is_absolute(): fail('non-absolute path')
 try: path.resolve(strict=True).relative_to(allowed_root.resolve(strict=True))
 except ValueError: fail('out of root: '+str(path))
 try: path.relative_to(allowed_root)
 except ValueError: fail('lexical out of root: '+str(path))
 current = Path(path.parts[0])
 for component in path.parts[1:]:
  current = current / component
  try: mode = current.lstat().st_mode
  except FileNotFoundError: fail('missing path component: '+str(current))
  if stat.S_ISLNK(mode): fail('symbolic-link path component: '+str(current))
  if current == path:
   if not stat.S_ISREG(mode): fail('not regular: '+str(path))
  elif not stat.S_ISDIR(mode): fail('not directory: '+str(current))
def strict_json(data):
 return json.loads(data.decode('utf-8'), parse_constant=lambda x: (_ for _ in ()).throw(ValueError(x)), object_pairs_hook=lambda p: dict(p) if len({k for k,_ in p}) == len(p) else (_ for _ in ()).throw(ValueError('duplicate key')))
def read_manifest():
 regular(manifest_path); raw=manifest_path.read_bytes()
 if hashlib.sha256(raw).hexdigest()!=os.environ['EXPECTED_MANIFEST']: fail('manifest digest')
 m=strict_json(raw)
 if m.get('schema_version')!='tukf09_two_basin_hpc_probe_manifest_v1' or m.get('status')!='TWO_BASIN_NARROW_PROBE_COMPLETE' or m.get('file_count')!=6 or m.get('files') != {n:{'sha256':h,'size_bytes':s} for n,(h,s) in expected.items()}: fail('manifest contents')
 return raw
first=read_manifest()
submission = Path('/data1/home/sunyiq/kalmannet_tukf09_scaled_noise_rehearsal_20260922/narrow_probe_v2/control/submission.json')
regular(submission, root.parent.parent); identity = strict_json(submission.read_bytes())
if not isinstance(identity, dict): fail('submission JSON object')
if identity.get('returncode') != 0: fail('sbatch return code')
if identity.get('stdout') not in ('Submitted batch job 227288', 'Submitted batch job 227288\n'): fail('job identity')
if identity.get('stderr') != '': fail('sbatch stderr')
payload={'manifest.final.sha256.json': first}
for name,(digest,size) in expected.items():
 p=root / PurePosixPath(name); regular(p); data=p.read_bytes()
 if len(data)!=size or hashlib.sha256(data).hexdigest()!=digest: fail('member '+name)
 payload[name]=data
if sum(map(len,payload.values())) >= 1024*1024 or any(len(x)>=1024*1024 for x in payload.values()): fail('size limit')
if read_manifest()!=first: fail('manifest changed during read')
stream=io.BytesIO()
with zipfile.ZipFile(stream,'w',compression=zipfile.ZIP_DEFLATED,compresslevel=9,strict_timestamps=True) as z:
 for name in sorted(payload):
  info=zipfile.ZipInfo(name, date_time=(1980,1,1,0,0,0)); info.create_system=3; info.external_attr=0o100644<<16; info.compress_type=zipfile.ZIP_DEFLATED
  z.writestr(info,payload[name],compress_type=zipfile.ZIP_DEFLATED,compresslevel=9)
blob=stream.getvalue()
print('TUKF09_SHORT_PROBE_RECEIPT_V2')
print('channel=kalmannet-tukf09-noise-20260922')
print('sequence=12')
print('exit_code=0')
print('zip_sha256='+hashlib.sha256(blob).hexdigest())
print('zip_size='+str(len(blob)))
print('zip_base64='+base64.b64encode(blob).decode('ascii'))
print('END_TUKF09_SHORT_PROBE_RECEIPT_V2')
PY
