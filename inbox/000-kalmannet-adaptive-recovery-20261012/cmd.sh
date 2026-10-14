#!/bin/bash
sequence=15
set -euo pipefail
umask 077
export TZ=UTC LC_ALL=C
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -I -S -B - <<'AUX15_READONLY'
from pathlib import Path
import base64,datetime,gzip,hashlib,json,os,stat,subprocess,sys,time
assert os.getuid()==2272 and not os.environ.get('SLURM_JOB_ID')
R=Path('/data1/home/sunyiq/kalmannet_cpu_archived_learned_full_validation_20261013_001');os.chdir(R)
job='241931';manifest_sha='c947d8f495bf7e5eba28664521c5d6e67f4baeb181436cba6aea52fdc4b4fb96';admission_sha='3ca38de8f6708facd9fc5f34cf9b8206ad497847bbb2f89b9c62d28869e2a6ff';started=time.monotonic()
def pin(raw):return dict(bytes=len(raw),sha256=hashlib.sha256(raw).hexdigest())
def ordinary(p,limit):
 st=p.lstat();assert stat.S_ISREG(st.st_mode) and st.st_uid==2272 and st.st_size<=limit and p.resolve()==p and not any(x.is_symlink() for x in (p,*p.parents));return p.read_bytes()
raw=ordinary(R/'source_manifest.json',65536);assert pin(raw)==dict(bytes=9660,sha256=manifest_sha);manifest=json.loads(raw)
def module(rel):
 raw=ordinary(R/rel,1024**2);assert pin(raw)==manifest['files'][rel]
 ns={'__name__':'full16_readonly_collection'};exec(compile(raw,rel,'exec'),ns);return ns
sys.path.insert(0,str(R/'control'))
serial=module('control/serial_prefix.py');root=module('control/root_adapter.py');fields=module('control/native_fields.py');owned=module('control/owned_process_tree.py')
a_raw=ordinary(R/'metadata/root_admission.json',256*1024);assert pin(a_raw)==dict(bytes=7614,sha256=admission_sha);a=json.loads(a_raw)
raw=ordinary(R/'metadata/native_executable_bindings.json',65536);assert pin(raw)==manifest['files']['metadata/native_executable_bindings.json'];bindings=json.loads(raw)['executables']
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
N=Path('/data1/home/sunyiq/kalmannet_cpu_frozen_test_chunk02_20261014_001')
T=Path('/data1/home/sunyiq/kalmannet_cpu_frozen_test_chunk01_20261014_001')
F=Path('/data1/home/sunyiq/kalmannet_cpu_selected48_required128_replay_20261014_001')
C=Path('/data1/home/sunyiq/kalmannet_cpu_selected48_preflight_20261014_002')
P=Path('/data1/home/sunyiq/kalmannet_cpu_selected48_preflight_20261014_001')
S=Path('/data1/home/sunyiq/kalmannet_cpu_original45_selection_20261014_001')
prior_raw=ordinary(S/'execution/collection270/external_receipt.original.json',128*1024);prior=json.loads(prior_raw)
assert pin(prior_raw)==dict(bytes=8192,sha256='20113563a2755b24b27e3deccaf72350dfdbc13fb05d16155976fa063b7b2cc5')
assert prior['job_id']=='241946' and prior['job_terminal_verified'] and prior['task_internal_cleanup_verified'] and prior['technical_opportunity_completed'] and prior['selector_runs']==1 and prior['model_calls']==prior['test_tensor_reads']==0
queue=query('squeue',['--noheader','--user','sunyiq','--format=%i|%j|%T|%Z|%o'])
assert queue['returncode']==0 and not base64.b64decode(queue['stderr_base64'])
scope=json.loads(ordinary(R/'metadata/scope_isolation.json',65536))
decision=serial['amended_queue'](queue['argv'],0,base64.b64decode(queue['stdout_base64']).decode(),'',scope['protected_job'],scope['same_study_new_roots']+[str(S),str(P),str(C),str(F),str(N),str(T),'/data1/home/sunyiq/kalmannet_cpu_frozen_test_chunk03_20261014_001','/data1/home/sunyiq/kalmannet_cpu_frozen_test_chunk04_20261014_001'])

test=Path('/data1/home/sunyiq/kalmannet_wrr_closeout_20260928_v1/plain_preflight_v1/inputs/repo/data/processed/high_flow_aug/test_win800_20090314_14-20110101_01.pt')
st=test.lstat();assert stat.S_ISREG(st.st_mode) and st.st_uid==2272 and test.resolve()==test and not any(p.is_symlink() for p in (test,*test.parents))
test_descriptor=dict(role='dataset_test',original='G:\\github\\pycharm\\projects\\kalmannet\\data\\processed\\high_flow_aug\\test_win800_20090314_14-20110101_01.pt',path=str(test),bytes=st.st_size,
 sha256='df18203c073314c5a15c6df77411cb972a0a3f983d97cc468760ff12dbd6908a',sha256_source='Original frozen registry/runtime metadata, not newly computed here',stat_only=True,tensor_file_opened=False)
print(json.dumps(dict(schema='frozen_test_later_partition_fresh_queue_metadata_v1',selected_root=str(N),previous_test_root=str(T),test_descriptor=test_descriptor,test_tensor_reads=0,test_tensor_hashes=0,observed_utc=datetime.datetime.now(datetime.timezone.utc).isoformat(),queue=queue,decision=decision,
 predecessor_selection_terminal_identity=pin(prior_raw),selected_root_absent=not N.exists() and not N.is_symlink(),selected_boot_absent=not Path(str(N)+'_transport_boot').exists(),numeric_runs=0,scientific_submissions=0,other_jobs_modified=False),sort_keys=True))
transport=Path('/data1/home/sunyiq/kalmannet_joint_adaptive_comparison_20261006_v1/transport/sequence_287')
diagnostic=dict(schema='readonly_frozen_cpu_test_submission287_diagnostic_v1',observed_utc=datetime.datetime.now(datetime.timezone.utc).isoformat(),root=str(N),root_exists=N.exists(),queue=queue,files=[],numeric_runs=0,scientific_submissions=0,other_jobs_modified=False)
for p in [transport/name for name in ('stdout','stderr','result.json','result.der','failure.der','controller.log')]+[N/'submission_receipt.json',N/'output/submission_receipt.json',N/'output/opportunity_receipt.json']:
 if p.exists():
  st=p.lstat();assert stat.S_ISREG(st.st_mode) and st.st_uid==2272 and not p.is_symlink();row=dict(path=str(p),bytes=st.st_size,mtime=st.st_mtime)
  if p.name in ('stdout','stderr','controller.log','submission_receipt.json','opportunity_receipt.json') and st.st_size<=128*1024:
   raw=ordinary(p,128*1024);row['identity']=pin(raw);row['text']=raw.decode('utf8','replace')
  diagnostic['files'].append(row)
print(json.dumps(diagnostic,sort_keys=True))

AUX15_READONLY
