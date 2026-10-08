#!/usr/bin/env bash
set -eo pipefail
source /data1/home/sunyiq/miniconda3/etc/profile.d/conda.sh
conda activate nh_final
set -u
export PYTHONDONTWRITEBYTECODE=1
python -B - <<'PY'
import pathlib,io,tarfile,json,hashlib,subprocess,re,time,datetime
parent=pathlib.Path('/data1/home/sunyiq/zhenjiang_complete_comparison_20261006_002');root=pathlib.Path('/data1/home/sunyiq/zhenjiang_complete_comparison_20261008_recovery_002')
response=json.loads((parent/'records/monitoring_3h/gpu_compatibility_submission_007_response.json').read_text());m=re.fullmatch(r'Submitted batch job ([0-9]+)\s*',response['stdout'])
if response['returncode'] or not m:raise ValueError('unique replacement GPU probe receipt missing')
probejob=m.group(1);admission=json.loads((parent/'records/monitoring_3h'/('gpu_compatibility_'+probejob+'.json')).read_text())
if not admission['matches_frozen_device'] or admission['real_training_started'] or admission['node']!='ngu007':raise ValueError('replacement GPU admission differs')
r=subprocess.run(['sacct','-n','-X','-j',probejob,'--format=JobID,State,ExitCode','-P'],capture_output=True,text=True,check=True)
if not any(l.startswith(probejob+'|COMPLETED|0:0') for l in r.stdout.splitlines()):raise ValueError('synthetic GPU test not completed successfully')
inbox=pathlib.Path('inbox/zhenjiang-six-source-four-target-ukf');seq=int((inbox/'seq').read_text());raw=(inbox/('payload_complete_comparison_20261006_'+str(seq)+'.tar.gz')).read_bytes()
if hashlib.sha256(raw).hexdigest()!='96d07e13e554241b5f8d79b535e8a00fb14d4fb72f1a118fa44c17be9d9a09f2':raise ValueError('recovery archive differs')
if root.exists():raise FileExistsError('preserve existing recovery and inspect before further action')
with tarfile.open(fileobj=io.BytesIO(raw),mode='r:gz') as t:
 members=t.getmembers()
 if len({m.name for m in members})!=len(members):raise ValueError('duplicate package path')
 for m in members:
  p=pathlib.PurePosixPath(m.name)
  if not m.isfile() or p.is_absolute() or '..' in p.parts:raise ValueError('unsafe package file')
 content={m.name:t.extractfile(m).read() for m in members}
manifest=json.loads(content.pop('release_manifest.json'))
if set(content)!=set(manifest['files']):raise ValueError('release allow-list differs')
for n,b in content.items():
 spec=manifest['files'][n]
 if len(b)!=spec['bytes'] or hashlib.sha256(b).hexdigest()!=spec['sha256']:raise ValueError('recovery release content differs')
root.mkdir()
for n,b in content.items():
 p=root/n;p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(b)
(root/'release_manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
for name in ('logs','runs','reports','predictions','artifacts'):(root/name).mkdir(exist_ok=True)
def write(p,v):
 with p.open('x') as f:json.dump(v,f,indent=2)
write(root/'records/gpu_compatibility_admission.json',admission)
fault=json.loads((root/'records/source_stall_evidence.json').read_text());case=fault['case'];job=str(json.loads((parent/'records/scheduler_jobs.json').read_text())[case])
if job!=fault['job_id'] or fault['status']!='technical_training_stall_confirmed':raise ValueError('source job and fault binding differs')
files=sorted([*parent.joinpath('src').glob('*.py'),*parent.joinpath('scripts').glob('*.py'),*parent.joinpath('vendor/pytides').glob('*.py')]);hashes={p.relative_to(parent).as_posix():hashlib.sha256(p.read_bytes()).hexdigest() for p in files}
code=hashlib.sha256(json.dumps(hashes,sort_keys=True,separators=(',',':')).encode()).hexdigest()
if code!=fault['source_code_hash']:raise ValueError('source implementation changed before stop')
for n in ('protocol-v3.json','registry-v3.json'):
 if (root/'configs'/n).read_bytes()!=(parent/'configs'/n).read_bytes():raise ValueError('scientific protocol changed before stop')
source_records={}
for run,observed in fault['members'].items():
 folder=parent/'runs'/run;config=folder/'config.json';checkpoint=folder/'continuation.pt';metrics=folder/'metrics.json'
 if hashlib.sha256(config.read_bytes()).hexdigest()!=observed['config']['sha256']:raise ValueError('source run config changed')
 if checkpoint.stat().st_mtime_ns!=observed['continuation_checkpoint_stat']['mtime_ns']:raise ValueError('source checkpoint advanced; do not stop')
 if len(json.loads(metrics.read_text())['validation_mae_cm'])!=observed['metrics']['completed_epochs']:raise ValueError('source epoch advanced; do not stop')
 source_records[run]={'config_sha256':hashlib.sha256(config.read_bytes()).hexdigest(),'checkpoint_sha256':hashlib.sha256(checkpoint.read_bytes()).hexdigest(),'metrics_sha256':hashlib.sha256(metrics.read_bytes()).hexdigest(),'checkpoint_bytes':checkpoint.stat().st_size}
r=subprocess.run(['scontrol','show','job','-o',job],capture_output=True,text=True,check=True);scheduler=r.stdout
if 'JobState=RUNNING' not in scheduler or ('WorkDir='+str(parent)+' ') not in scheduler or ('JobName=zj_legacy_lstm__small_') not in scheduler:raise ValueError('unique stalled source scheduler binding differs')
queue=subprocess.run(['squeue','-h','-u','sunyiq','-o','%i|%T|%j|%Z'],capture_output=True,text=True,check=True)
matching=[l for l in queue.stdout.splitlines() if 'legacy_lstm__small' in l or 'zj_lstm_small_recovery_261008_002' in l]
if len(matching)!=1 or not matching[0].startswith(job+'|'):raise ValueError('other same-case allocation exists; do not duplicate')
command='python3 -c '+repr("import base64;exec(compile(base64.b64decode('aW1wb3J0IHBhdGhsaWIsanNvbixzdWJwcm9jZXNzLGRhdGV0aW1lCnJvb3Q9cGF0aGxpYi5QYXRoKCcvZGF0YTEvaG9tZS9zdW55aXEvemhlbmppYW5nX2NvbXBsZXRlX2NvbXBhcmlzb25fMjAyNjEwMDZfMDAyJyk7am9iPXN0cihqc29uLmxvYWRzKChyb290LydyZWNvcmRzL3NjaGVkdWxlcl9qb2JzLmpzb24nKS5yZWFkX3RleHQoKSlbJ2xlZ2FjeV9sc3RtX19zbWFsbCddKTtwaWRzPVtdCmZvciBwIGluIHBhdGhsaWIuUGF0aCgnL3Byb2MnKS5pdGVyZGlyKCk6CiBpZiBub3QgcC5uYW1lLmlzZGlnaXQoKTpjb250aW51ZQogdHJ5OgogIGlmICdzY3JpcHRzL3RyYWluX3N1cGVyY29tcHV0ZXJfY2FzZS5weSAtLWNhc2UgbGVnYWN5X2xzdG1fX3NtYWxsJyBpbiAocC8nY21kbGluZScpLnJlYWRfYnl0ZXMoKS5yZXBsYWNlKGInXDAnLGInICcpLmRlY29kZSgpIGFuZCAocC8nY3dkJykucmVzb2x2ZSgpPT1yb290IGFuZCAoJ2pvYl8nK2pvYikgaW4gKHAvJ2Nncm91cCcpLnJlYWRfdGV4dCgpOnBpZHMuYXBwZW5kKHAubmFtZSkKIGV4Y2VwdCBPU0Vycm9yOnBhc3MKaWYgbGVuKHBpZHMpIT0xOnJhaXNlIFZhbHVlRXJyb3IoJ3N0YWxsZWQgc291cmNlIFBJRCBub3QgdW5pcXVlJykKcj1zdWJwcm9jZXNzLnJ1bihbc3RyKHJvb3QvJ2hwYy9kaWFnbm9zdGljX3Rvb2xzL3B5LXNweS0wLjQuMicpLCdkdW1wJywnLS1waWQnLHBpZHNbMF0sJy0tbmF0aXZlJ10sY2FwdHVyZV9vdXRwdXQ9VHJ1ZSx0ZXh0PVRydWUsdGltZW91dD0xNSkKcHJpbnQoanNvbi5kdW1wcyh7J2F0JzpkYXRldGltZS5kYXRldGltZS5ub3coKS5hc3RpbWV6b25lKCkuaXNvZm9ybWF0KCksJ3BpZCc6cGlkc1swXSwncmV0dXJuY29kZSc6ci5yZXR1cm5jb2RlLCdzdGRvdXQnOnIuc3Rkb3V0LCdzdGRlcnInOnIuc3RkZXJyfSkpCg=='),'final_own_stack_check','exec'))")
r=subprocess.run(['ssh','-o','BatchMode=yes','-o','ConnectTimeout=10','ngu011',command],capture_output=True,text=True,timeout=25)
if r.returncode:raise ValueError('cannot re-confirm source stall before stop')
stack=json.loads(r.stdout)
if stack['returncode'] or 'cudaStreamSynchronize' not in stack['stdout'] or 'src/training.py:83' not in stack['stdout']:raise ValueError('source no longer at confirmed CUDA stall; do not stop')
logpath=parent/'logs'/('zj_legacy_lstm__small_261006_pathfix_'+job+'.out');lograw=logpath.read_bytes()
write(root/'records/source_before_stop.json',{'source_job':job,'scheduler':scheduler,'own_queue':queue.stdout,'source_code_hash':code,'source_records':source_records,'fresh_stack':stack,'source_log_sha256':hashlib.sha256(lograw).hexdigest(),'source_log':lograw.decode(errors='replace')})
write(root/'records/source_stop_attempt.json',{'source_job':job,'authorization':'user authorized restoration of confirmed technical failures','status':'reserved','at':datetime.datetime.now().astimezone().isoformat()})
r=subprocess.run(['scancel',job],capture_output=True,text=True,timeout=15);write(root/'records/source_stop_response.json',{'returncode':r.returncode,'stdout':r.stdout,'stderr':r.stderr})
if r.returncode:raise RuntimeError('source stop uncertain; inspect without repeating')
confirmed=None
for i in range(12):
 q=subprocess.run(['squeue','-h','-j',job,'-o','%i|%T'],capture_output=True,text=True,timeout=10)
 a=subprocess.run(['sacct','-n','-X','-j',job,'--format=JobID,State,ExitCode','-P'],capture_output=True,text=True,timeout=10)
 if not q.stdout.strip() and (q.returncode==0 or 'invalid job id' in q.stderr.lower()) and a.returncode==0 and any(l.startswith(job+'|CANCELLED') for l in a.stdout.splitlines()):confirmed={'status':'stalled_source_allocation_stopped','source_job':job,'queue':q.stdout,'queue_stderr':q.stderr,'accounting':a.stdout};break
 time.sleep(3)
if confirmed is None:raise RuntimeError('source allocation has not ended; do not duplicate')
write(root/'records/source_stop_confirmed.json',confirmed)
print(json.dumps({'status':'stalled_source_allocation_stopped','source_job':job,'root':str(root)}),flush=True)
subprocess.run(['python','-B',str(root/'hpc/prepare_recovery.py')],cwd=root,check=True)
subprocess.run(['python','-B',str(root/'hpc/submit_recovery.py')],cwd=root,check=True)
PY
