#!/bin/bash
set -eo pipefail
umask 077
exec timeout --signal=TERM --kill-after=5s 85s /data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -B - <<'PY_GEOLOGY_READ'
import base64,datetime,hashlib,json,pathlib,re,subprocess,zipfile
root=pathlib.Path('/data1/home/sunyiq/china_input_completion_hpc_20261015_001/geology_diagnostic_v1')
sequence=21;job_id='243305'
assert re.fullmatch('[0-9]+',job_id) and root.resolve(strict=True)==root and not root.is_symlink()
def read(path,limit):
 assert path.resolve(strict=True)==path and path.is_file() and not path.is_symlink()
 before=path.stat();assert 0<=before.st_size<=limit
 value=path.read_bytes();after=path.stat()
 assert len(value)==before.st_size==after.st_size and before.st_mtime_ns==after.st_mtime_ns
 return value
assert read(root/'OWN_GEOLOGY_JOB_ID',128)==(job_id+'\n').encode()
submission=json.loads(read(root/'SUBMISSION_RESULT.json',65536))
assert submission['status']=='UNIQUE_JOB_SUBMITTED' and submission['job_id']==job_id
raw=read(root/'GEOLOGY_DIAGNOSTIC_CONTRACT.json',65536)
assert hashlib.sha256(raw).hexdigest()=='74d39e2433fa521455ff81f536016f33cc54f2008d045a99e14cd077bff40b03'
state=dict(server_utc=datetime.datetime.now(datetime.timezone.utc).isoformat(),job_id=job_id,
 scientific_array_reads=0,source_downloads=0,model_calls=0,training=0,new_slurm_jobs=0,
 automatic_checks_enabled=False,snapshot_only=True)
commands=[('squeue',['squeue','-j',job_id,'--noheader','--format=%i|%T|%C|%R']),
 ('sacct',['sacct','-j',job_id,'--noheader','--parsable2','--format=JobIDRaw,State,ExitCode,Elapsed,AllocCPUS,MaxRSS'])]
entries={}
for label,command in commands:
 outcome=subprocess.run(command,capture_output=True,timeout=30)
 assert len(outcome.stdout)<=65536 and len(outcome.stderr)<=65536
 for suffix,value in (('stdout',outcome.stdout),('stderr',outcome.stderr)):
  name=label+'_seq'+str(sequence)+'.'+suffix
  with (root/name).open('xb') as stream:stream.write(value)
  entries[name]=value
 state[label+'_exit_code']=outcome.returncode
names=['SUBMISSION_STARTED.json','SUBMISSION_RESULT.json','GEOLOGY_CONTROL_STARTED.json',
 'GEOLOGY_CONTROL_RESULT.json','GEOLOGY_CONTROL_FAILURE.json','GEOLOGY_MAIN_RESULT.json',
 'GEOLOGY_MAIN_FAILURE.json','GEOLOGY_UNMATCHED_COLUMNS.json','GEOLOGY_INDEPENDENT_RESULT.json',
 'main_LAUNCH.json','independent_LAUNCH.json','main_CONTROL_RESULT.json','independent_CONTROL_RESULT.json',
 'main.stdout','main.stderr','independent.stdout','independent.stderr',
 'logs/geology-'+job_id+'.out','logs/geology-'+job_id+'.err']
missing=[];used=sum(map(len,entries.values()))
for name in names:
 path=root/name
 if not path.exists():missing.append(name);continue
 limit=2097152 if name in ('GEOLOGY_MAIN_RESULT.json','GEOLOGY_INDEPENDENT_RESULT.json') else 65536
 value=read(path,limit);assert used+len(value)<=4194304
 used+=len(value);entries[name]=value
state['control_terminal']=(root/'GEOLOGY_CONTROL_RESULT.json').exists() or (root/'GEOLOGY_CONTROL_FAILURE.json').exists()
states=[]
if state['sacct_exit_code']==0:
 for line in entries['sacct_seq'+str(sequence)+'.stdout'].decode('utf8').splitlines():
  fields=line.split('|')
  if fields and fields[0]==job_id:
   assert len(fields)>=6;states.append(fields[1].split()[0].rstrip('+'))
assert len(states)<=1
state['scheduler_state']=states[0] if states else 'UNKNOWN'
state['scheduler_terminal']=state['scheduler_state'] in ['COMPLETED','FAILED','TIMEOUT','OUT_OF_MEMORY','CANCELLED','NODE_FAIL','BOOT_FAIL','DEADLINE','PREEMPTED']
state['nonterminal_confirmed']=(not state['control_terminal'] and state['scheduler_state'] in ['PENDING','RUNNING','CONFIGURING'])
state.update(report_members=len(entries),missing_report_members=missing)
status='STATUS_seq'+str(sequence)+'.json'
entries[status]=(json.dumps(state,indent=2)+'\n').encode();assert len(entries[status])<=65536
with (root/status).open('xb') as stream:stream.write(entries[status])
table={name:dict(path=str(root/name),bytes=len(value),sha256=hashlib.sha256(value).hexdigest()) for name,value in entries.items()}
index=(json.dumps(table,indent=2)+'\n').encode()
assert len(index)<=65536 and sum(map(len,entries.values()))+len(index)<=4194304
target=root/('DELIVERY_seq'+str(sequence)+'_GEOLOGY.zip')
with zipfile.ZipFile(target,'x',compression=zipfile.ZIP_DEFLATED) as archive:
 archive.writestr('REPORT_FILES.json',index)
 for name,value in entries.items():archive.writestr(name,value)
assert target.stat().st_size<=1048576
raw=read(target,1048576)
print('OWN_GEOLOGY_JOB_ID='+job_id)
print('OWN_GEOLOGY_TERMINAL='+str(int(state['control_terminal'] or state['scheduler_terminal'])))
print('OWN_GEOLOGY_NONTERMINAL_CONFIRMED='+str(int(state['nonterminal_confirmed'])))
print('OWN_GEOLOGY_FILE='+target.name);print('OWN_GEOLOGY_BYTES='+str(len(raw)))
print('OWN_GEOLOGY_SHA256='+hashlib.sha256(raw).hexdigest())
print('OWN_GEOLOGY_BASE64_BEGIN');print(base64.b64encode(raw).decode());print('OWN_GEOLOGY_BASE64_END')
print('OWN_GEOLOGY_STATUS_DONE')
PY_GEOLOGY_READ
