#!/bin/bash
set -eo pipefail
umask 077
exec timeout --signal=TERM --kill-after=5s 85s /data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -B - <<'PY_NATIVE_HEADER_READ'
import base64,datetime,hashlib,json,pathlib,re,subprocess,zipfile
root=pathlib.Path('/data1/home/sunyiq/china_input_completion_hpc_20261015_001/vegetation_headers_v1')
sequence=25;job_id='243332'
assert re.fullmatch('[0-9]+',job_id) and root.resolve(strict=True)==root and not root.is_symlink()
def read(path,limit):
 assert path.resolve(strict=True)==path and path.is_file() and not path.is_symlink()
 before=path.stat();assert 0<=before.st_size<=limit
 value=path.read_bytes();after=path.stat()
 assert len(value)==before.st_size==after.st_size and before.st_mtime_ns==after.st_mtime_ns
 return value
assert read(root/'OWN_HEADER_JOB_ID',128)==(job_id+'\n').encode()
submission=json.loads(read(root/'SUBMISSION_RESULT.json',65536))
assert submission['status']=='UNIQUE_JOB_SUBMITTED' and submission['job_id']==job_id
raw=read(root/'VEGETATION_HEADER_CONTRACT.json',65536)
assert hashlib.sha256(raw).hexdigest()=='2b4fc5526a55ce6209971b55903620c62c4de4fc541d47c9df00ee2b5335b351'
contract=json.loads(raw)
keys=contract['expected_keys'];assert len(keys)==1196 and len(set(keys))==1196
assert all(re.fullmatch(r'(?:FVC|LAI)_[0-9]{7}',key) for key in keys)
state=dict(server_utc=datetime.datetime.now(datetime.timezone.utc).isoformat(),job_id=job_id,
 scientific_array_reads=0,source_downloads=0,model_calls=0,training=0,new_slurm_jobs=0,
 input_admission_approved=False,prediction_approved=False,
 automatic_checks_enabled=False,snapshot_only=True)
commands=[('squeue',['squeue','-j',job_id,'--noheader','--format=%i|%T|%C|%R']),
 ('sacct',['sacct','-j',job_id,'--noheader','--parsable2','--format=JobIDRaw,State,ExitCode,Elapsed,AllocCPUS,MaxRSS'])]
entries={}
for label,command in commands:
 outcome=subprocess.run(command,capture_output=True,timeout=25)
 assert len(outcome.stdout)<=65536 and len(outcome.stderr)<=65536
 for suffix,value in (('stdout',outcome.stdout),('stderr',outcome.stderr)):
  name=label+'_seq'+str(sequence)+'.'+suffix
  with (root/name).open('xb') as stream:stream.write(value)
  entries[name]=value
 state[label+'_exit_code']=outcome.returncode
limits={name:65536 for name in ['SUBMISSION_STARTED.json','SUBMISSION_RESULT.json',
 'CONTROL_STARTED.json','CONTROL_RESULT.json','CONTROL_FAILURE.json','WORKER_LAUNCH.json',
 'VEGETATION_HEADER_RESULT.json','VEGETATION_HEADER_FAILURE.json','worker.stdout','worker.stderr',
 'logs/header-'+job_id+'.out','logs/header-'+job_id+'.err']}
limits.update({'HEADER_PERIODS.json':1048576,'HEADER_COMPARISON_RESULT.json':1048576})
limits.update({'header_reports/'+key+'.json':12288 for key in keys})
missing=[];used=sum(map(len,entries.values()))
for name,limit in limits.items():
 path=root/name
 if not path.exists():missing.append(name);continue
 value=read(path,limit);assert used+len(value)<=24*1024**2
 used+=len(value);entries[name]=value
state['control_terminal']=(root/'CONTROL_RESULT.json').exists() or (root/'CONTROL_FAILURE.json').exists()
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
state.update(report_members=len(entries),missing_report_members=missing,
 saved_compact_header_reports=sum(name.startswith('header_reports/') for name in entries))
status='STATUS_seq'+str(sequence)+'.json'
entries[status]=(json.dumps(state,indent=2)+'\n').encode();assert len(entries[status])<=65536
with (root/status).open('xb') as stream:stream.write(entries[status])
table={name:dict(path=str(root/name),bytes=len(value),sha256=hashlib.sha256(value).hexdigest()) for name,value in entries.items()}
index=(json.dumps(table,indent=2)+'\n').encode()
assert len(index)<=1048576 and sum(map(len,entries.values()))+len(index)<=24*1024**2
target=root/('DELIVERY_seq'+str(sequence)+'_NATIVE_HEADERS.zip')
with zipfile.ZipFile(target,'x',compression=zipfile.ZIP_DEFLATED) as archive:
 archive.writestr('REPORT_FILES.json',index)
 for name,value in entries.items():archive.writestr(name,value)
assert target.stat().st_size<=5*1024**2
raw=read(target,5*1024**2)
print('OWN_HEADER_JOB_ID='+job_id)
print('OWN_HEADER_TERMINAL='+str(int(state['control_terminal'] or state['scheduler_terminal'])))
print('OWN_HEADER_NONTERMINAL_CONFIRMED='+str(int(state['nonterminal_confirmed'])))
print('OWN_HEADER_FILE='+target.name);print('OWN_HEADER_BYTES='+str(len(raw)))
print('OWN_HEADER_SHA256='+hashlib.sha256(raw).hexdigest())
print('OWN_HEADER_BASE64_BEGIN');print(base64.b64encode(raw).decode());print('OWN_HEADER_BASE64_END')
print('OWN_HEADER_STATUS_DONE')
PY_NATIVE_HEADER_READ
