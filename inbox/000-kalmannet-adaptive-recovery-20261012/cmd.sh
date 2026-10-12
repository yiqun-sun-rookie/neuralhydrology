#!/bin/bash
sequence=3
umask 077
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -I -B - <<'READONLY_DIAG'
import os,json,subprocess,hashlib,datetime,base64
from pathlib import Path
BASE=Path('/data1/home/sunyiq/kalmannet_joint_adaptive_comparison_20261006_v1')
R=BASE/'author_solver_capture_restart_20261012_003'
assert os.getuid()==os.geteuid()==2272
out={'read_only':True,'scientific_submissions':0,'observed_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'host':os.uname().nodename,'files':{},'queries':[]}
def take(path,cap=65536,tail=False):
 key=str(path)
 try:
  if path.is_symlink():out['files'][key]={'linked_refused':True};return
  if not path.exists():out['files'][key]={'exists':False};return
  s=path.stat();row={'exists':True,'bytes':s.st_size,'mtime_ns':s.st_mtime_ns}
  if path.is_file() and s.st_size<=cap:
   b=path.read_bytes();row.update(sha256=hashlib.sha256(b).hexdigest(),base64=base64.b64encode(b).decode())
  elif path.is_file() and tail:
   with path.open('rb') as f:f.seek(max(0,s.st_size-cap));b=f.read(cap)
   row.update(tail_base64=base64.b64encode(b).decode(),tail_only=True)
  elif path.is_dir():row['names']=sorted(x.name for x in path.iterdir())[:100]
  out['files'][key]=row
 except Exception as e:out['files'][key]={'error_type':type(e).__name__,'error':str(e)[:1024]}
for name in ['transport_boot/execution_adapter_result.json','science_root/submission_intent.json','science_root/submission_receipt.json','science_root/resource_admission.json','science_root/preentry_failure.json','science_root/job_process.json','science_root/output/started.json','science_root/output/summary.json','control_root/logs']:
 take(R/name)
for name in ['controller.log','stdout','stderr','result.json','result.der']:
 take(BASE/'transport/sequence_221'/name,262144)
logs=R/'control_root/logs'
if logs.is_dir() and not logs.is_symlink():
 for f in list(logs.iterdir())[:10]:take(f,65536,True)
def query(argv):
 try:
  p=subprocess.run(argv,stdin=subprocess.DEVNULL,capture_output=True,timeout=20,env={**os.environ,'TZ':'UTC','LC_ALL':'C'})
  out['queries'].append({'argv':argv,'returncode':p.returncode,'stdout':p.stdout[:131072].decode(errors='replace'),'stderr':p.stderr[:16384].decode(errors='replace'),'truncated':len(p.stdout)>131072})
 except Exception as e:out['queries'].append({'argv':argv,'error_type':type(e).__name__,'error':str(e)[:1024]})
query(['squeue','--user=sunyiq','--noheader','--format=%i|%j|%T|%M|%R|%Z'])
receipt=R/'science_root/submission_receipt.json';job=None
if receipt.is_file() and receipt.stat().st_size<65536:
 try:job=json.loads(receipt.read_bytes()).get('job_id')
 except Exception:pass
ids=['239882','240124','240268']
if job and str(job).isdigit():ids.append(str(job))
query(['sacct','--jobs='+','.join(ids),'--noheader','--parsable2','--format=JobIDRaw,JobName,State,ExitCode,ElapsedRaw,AllocCPUS,AllocTRES,NodeList,Start,End'])
try:
 q=subprocess.run(['ps','-u','sunyiq','-o','pid,ppid,etimes,stat,args'],capture_output=True,timeout=10)
 rows=[x for x in q.stdout.decode(errors='replace').splitlines() if ('cmd_221.sh' in x or 'sequence_221' in x or str(R) in x)]
 out['matching_processes']=[x[:2048] for x in rows][:30]
except Exception as e:out['ps_error']=type(e).__name__

OLD=Path('/data1/home/sunyiq/kalmannet_cpu240124_node_release_probe_20261012_001')

try:
 args=['/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python','-I','-S','-B',str(OLD/'control/launcher.py'),'collect','002']
 if (OLD/'output/collection_002').exists():out['final_old_collection']={'not_repeated':True,'already_exists':True}
 else:
  result=subprocess.run(args,stdin=subprocess.DEVNULL,capture_output=True,timeout=90)
  out['final_old_collection']={'argv':args,'returncode':result.returncode,'stdout':result.stdout.decode(errors='replace')[:131072],'stderr':result.stderr.decode(errors='replace')[:65536],'scientific_calls':0}
except Exception as exc:out['final_old_collection']={'error_type':type(exc).__name__,'no_replay':True}
for folder in ('output/node_native','output/collection_002','output/collection_002/native'):
 q=OLD/folder;take(q)
 if q.is_dir() and not q.is_symlink():
  for f in sorted(q.iterdir())[:30]:
   if f.is_file() and not f.is_symlink():take(f,262144)
for name in ('metadata/root_admission.json','output/submission_receipt.json'):take(OLD/name)
query(['sacct','-n','-P','--format=JobIDRaw,JobName,User,UID,Partition,Submit,Start,End,ElapsedRaw,AllocCPUS,AllocTRES,ReqTRES,State,ExitCode,NodeList,WorkDir,TimelimitRaw,Comment,CPUTimeRAW,TotalCPU','-j','240268'])
query(['squeue','--noheader','--user=sunyiq','--format=%i|%j|%u|%P|%T|%M|%l|%D|%R|%Z'])
query(['scontrol','show','node','icn274'])

for folder in ('','logs','output','native','metadata'):
 take(OLD/folder)
 if folder in ('logs','output','native'):
  q=OLD/folder
  if q.is_dir() and not q.is_symlink():
   for f in sorted(q.iterdir())[:25]:
    if f.is_file() and not f.is_symlink() and (f.suffix in ('.json','.log','.out','.err','.stdout','.stderr','.txt') or folder=='logs'):take(f,65536,True)
for name in ('submission_receipt.json','root_admission.json','metadata/source_manifest.json','node_binding.json','node_result.json','probe_result.json'):
 take(OLD/name)
query(['scontrol','show','job','241249'])
query(['scontrol','show','job','240268'])
query(['sprio','--jobs=241249'])
query(['scontrol','show','nodes','ngu201,ngu202,ngu203'])
query(['scontrol','show','partition','hgpu8'])

raw=json.dumps(out,ensure_ascii=False,sort_keys=True).encode();assert len(raw)<2*1024*1024
print(raw.decode())
READONLY_DIAG
