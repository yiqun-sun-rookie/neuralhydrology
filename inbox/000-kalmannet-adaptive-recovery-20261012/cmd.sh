#!/bin/bash
sequence=14
set -euo pipefail
umask 077
export TZ=UTC LC_ALL=C
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -I -S -B - <<'AUX14_READONLY'
from pathlib import Path
import base64,datetime,gzip,hashlib,json,os,stat,subprocess,sys,time
assert os.getuid()==2272 and not os.environ.get('SLURM_JOB_ID')
R=Path('/data1/home/sunyiq/kalmannet_cpu_frozen_test_chunk01_20261014_001');os.chdir(R)
N=R
OLD=Path('/data1/home/sunyiq/kalmannet_cpu_archived_learned_full_validation_20261013_001')
job='242006';started=time.monotonic()
def pin(raw):return dict(bytes=len(raw),sha256=hashlib.sha256(raw).hexdigest())
def ordinary(p,limit):
 st=p.lstat();assert stat.S_ISREG(st.st_mode) and st.st_uid==2272 and st.st_size<=limit and p.resolve()==p and not any(x.is_symlink() for x in (p,*p.parents));return p.read_bytes()
manifest_raw=ordinary(R/'source_manifest.json',128*1024);assert pin(manifest_raw)=={'bytes': 12068, 'sha256': '5ef7fc1601455963e502ad69ec5c9ff2b2a34988e3fcf9802ccd16ce628bb342'};manifest=json.loads(manifest_raw)
assert manifest['root']==str(R)
old_raw=ordinary(OLD/'source_manifest.json',65536);assert pin(old_raw)==dict(bytes=9660,sha256='c947d8f495bf7e5eba28664521c5d6e67f4baeb181436cba6aea52fdc4b4fb96');old_manifest=json.loads(old_raw)
def module(rel):
 raw=ordinary(OLD/rel,1024**2);assert pin(raw)==old_manifest['files'][rel];ns={'__name__':'selected_metadata_collection'};exec(compile(raw,rel,'exec'),ns);return ns
sys.path.insert(0,str(OLD/'control'));owned=module('control/owned_process_tree.py');fields=module('control/native_fields.py');root=module('control/root_adapter.py')
b_raw=ordinary(OLD/'metadata/native_executable_bindings.json',65536);assert pin(b_raw)==old_manifest['files']['metadata/native_executable_bindings.json'];bindings=json.loads(b_raw)['executables']
a_raw=ordinary(R/'metadata/admission.json',128*1024);assert pin(a_raw)=={'bytes': 3738, 'sha256': '95a19a94cb637d4d4239c3a46ab562faa9798dedc7ff37f5d16d4f0ce8835c84'};a=json.loads(a_raw)
submission=json.loads(ordinary(R/'output/submission_receipt.original.json',128*1024));assert submission['job_id']==job and submission['nonce']==a['nonce'] and submission['actual_submission_calls']==1
def query(name,args):
 binding=bindings[name];exe=Path(binding['resolved']);assert exe.stat().st_uid==0 and pin(exe.read_bytes())=={k:binding[k] for k in ('bytes','sha256')}
 argv=[str(exe),*args];gate="import os,sys; assert sys.stdin.buffer.read(1)==b'G'; os.execv(sys.argv[1],sys.argv[1:])"
 p=subprocess.Popen(['/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python','-I','-S','-B','-c',gate,*argv],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,start_new_session=True,env={**os.environ,'TZ':'UTC','LC_ALL':'C'})
 tree=owned['OwnedTree'](p.pid);deadline=min(time.monotonic()+15,started+75);p.stdin.write(b'G');p.stdin.flush();p.stdin.close();p.stdin=None
 try:
  while True:
   tree.observe();left=deadline-time.monotonic();assert left>0
   try:out,err=p.communicate(timeout=min(.05,left));break
   except subprocess.TimeoutExpired:continue
  p.wait();tree.observe();assert not tree.live() and not tree.ownership_uncertainty;assert len(out)<=65536 and len(err)<=65536
 except BaseException:
  if tree.live():tree.stop(p)
  raise
 return dict(argv=argv,returncode=p.returncode,stdout_base64=base64.b64encode(out).decode(),stderr_base64=base64.b64encode(err).decode(),stdout_identity=pin(out),stderr_identity=pin(err),owned_cleanup_verified=True,supervision_error=None,public_return_supervision_error=None,actual_deadline_exceeded=False,ownership=tree.receipt())

queries=dict(scontrol=query('scontrol',['show','job',job,'--oneliner']),squeue=query('squeue',['--noheader','--jobs',job,'--format=%i|%T|%N']),sacct=query('sacct',['-j',job,'--parsable2','--noheader','--format='+root['ACCT']]))
assert queries['sacct']['returncode']==0 and not base64.b64decode(queries['sacct']['stderr_base64'])
accounting=fields['accounting'](base64.b64decode(queries['sacct']['stdout_base64']).decode(),job);main=next(x for x in accounting if x['JobIDRaw']==job)
assert main['WorkDir']==str(R) and main['JobName']=='cpu-frozen-test-chunk01-20261014-001' and main['UID']=='2272' and main['Partition']=='hcpu48y'
terminal=all(x['State'].split(' ')[0].rstrip('+') in root['TERMINAL'] for x in accounting)
if main['State'].split(' ')[0].rstrip('+') in root['TERMINAL']:assert main['Comment']==a['nonce']
else:
 c=queries['scontrol'];assert c['returncode']==0 and not base64.b64decode(c['stderr_base64'])
 f=fields['job_fields'](base64.b64decode(c['stdout_base64']).decode());assert f['JobId']==job and f['Comment']==a['nonce'] and f['WorkDir']==str(R) and f['JobName']=='cpu-frozen-test-chunk01-20261014-001'
 assert f['SubmitTime']==main['Submit'] and f['StartTime']==main['Start'] and f['NodeList']==main['NodeList']
 assert main['Comment'] in ('',a['nonce'])

result=dict(schema='readonly_frozen_cpu_test_job_and_transport_metadata_v1',observed_utc=datetime.datetime.now(datetime.timezone.utc).isoformat(),job_id=job,native_main=main,terminal=terminal,queries=queries,scientific_submissions=0,numeric_runs=0,other_jobs_modified=False,files=[],cases=[])
for p in [R/'output/opportunity_receipt.json',Path('/data1/home/sunyiq/kalmannet_joint_adaptive_comparison_20261006_v1/transport/sequence_284')/'controller.log']:
 if p.exists():
  raw=ordinary(p,2*1024**2);row=dict(path=str(p),identity=pin(raw))
  if p.name=='opportunity_receipt.json':
   own=json.loads(raw);row['fields']={k:own.get(k) for k in ('state','failure','owned_cleanup_verified','elapsed_seconds')};row['completed_tasks']=len(own.get('tasks',[]))
  else:row['error_text']=raw.decode('utf8','replace')[:3000]
  result['files'].append(row)
for task in json.loads(ordinary(R/'metadata/tasks.json',128*1024))['tasks']:
 directory=R/'package/runs'/(task['public_slot_id']+'__formal')/'formal';p=directory/'result.json'
 if p.exists():
  raw=ordinary(p,2*1024**2);r=json.loads(raw);result['cases'].append(dict(slot=task['public_slot_id'],state=r['state'],scientific_outcome=r['scientific_outcome'],result_identity=pin(raw),geometry=r.get('geometry'),error_type=r.get('error_type'),error=r.get('error')))
 elif (directory/'started.json').exists():
  rows=[json.loads(ordinary(p,64*1024)) for p in sorted(directory.glob('inference_complete_*.json'))]
  result['cases'].append(dict(slot=task['public_slot_id'],state='IN_PROGRESS_NO_COMPLETE_SCORE',completed_batches=len(rows),windows_in_completed_batch_metadata=sum(len(row['windows']) for row in rows),partial_scores=None))
result['transport284_file_sizes']=[];transport=Path('/data1/home/sunyiq/kalmannet_joint_adaptive_comparison_20261006_v1/transport/sequence_284')
for name in ('stdout','stderr','result.json','result.der','failure.der'):
 p=transport/name
 if p.exists():
  st=p.lstat();assert stat.S_ISREG(st.st_mode) and st.st_uid==2272 and not p.is_symlink();result['transport284_file_sizes'].append(dict(name=name,bytes=st.st_size,mtime=st.st_mtime))
print(json.dumps(result,sort_keys=True))

AUX14_READONLY
