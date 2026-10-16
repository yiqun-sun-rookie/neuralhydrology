#!/bin/bash
set -eo pipefail
umask 077
export CUDA_VISIBLE_DEVICES='' PYTHONDONTWRITEBYTECODE=1
exec timeout --signal=TERM --kill-after=5s 85s /data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -B - <<'PY_OWN_TAIL_READ'
import base64,datetime,hashlib,io,json,pathlib,re,subprocess,zipfile
root=pathlib.Path('/data1/home/sunyiq/china_input_completion_hpc_20261015_001/hydroatlas_login_tail_compute_parse_v1');sequence=35;job_id='243776'
assert root.resolve(strict=True)==root and (job_id=='NONE' or re.fullmatch('[0-9]+',job_id))
def read(path,limit):
 assert path.resolve(strict=True)==path and path.is_file() and not path.is_symlink()
 before=path.stat();assert 0<=before.st_size<=limit
 value=path.read_bytes();after=path.stat()
 assert len(value)==before.st_size==after.st_size and before.st_mtime_ns==after.st_mtime_ns
 return value
assert hashlib.sha256(read(root/'TAIL_CONTRACT.json',65536)).hexdigest()=='e3070acd66ffab461ed05242321a67225a0c784e3bdc35721a32fc591ef87b87'
submission_root=pathlib.Path('/data1/home/sunyiq/china_input_completion_hpc_20261015_001/hydroatlas_tail_parse_memfix_v1');assert submission_root.resolve(strict=True)==submission_root
submission_raw=read(submission_root/'SUBMISSION_RESULT.json',65536)
submission=json.loads(submission_raw)
assert submission['job_id']==job_id
if job_id=='NONE':
 assert submission['status']=='SOURCE_TRANSPORT_FAILED_NO_JOB' and not (submission_root/'OWN_ATLAS_DIRECTORY_JOB_ID').exists()
else:
 assert submission['status']=='UNIQUE_JOB_SUBMITTED' and read(submission_root/'OWN_ATLAS_DIRECTORY_JOB_ID',128)==(job_id+'\n').encode()
entries={'MEMFIX_SUBMISSION_RESULT.json':submission_raw};state=dict(server_utc=datetime.datetime.now(datetime.timezone.utc).isoformat(),job_id=job_id,
 scientific_array_reads=0,source_downloads=0,model_calls=0,new_slurm_jobs=0,input_admission_approved=False,
 prediction_approved=False,automatic_checks_enabled=False,snapshot_only=True,zip_fragment_files_returned=0)
if job_id!='NONE':
 for label,cmd in [('squeue',['squeue','-j',job_id,'--noheader','--format=%i|%T|%C|%R']),
  ('sacct',['sacct','-j',job_id,'--noheader','--parsable2','--format=JobIDRaw,State,ExitCode,Elapsed,AllocCPUS,MaxRSS'])]:
  result=subprocess.run(cmd,capture_output=True,timeout=25);assert len(result.stdout)<=65536 and len(result.stderr)<=65536
  state[label+'_exit_code']=result.returncode
  for suffix,value in [('stdout',result.stdout),('stderr',result.stderr)]:
   name=label+'_seq'+str(sequence)+'.'+suffix
   with (root/name).open('xb') as stream:stream.write(value)
   entries[name]=value
limits={'DEPLOYMENT_STARTED.json': 65536, 'SUBMISSION_STARTED.json': 65536, 'SUBMISSION_RESULT.json': 65536, 'LOGIN_CONTROL_RESULT.json': 65536, 'LOGIN_CONTROL_FAILURE.json': 65536, 'CONTROL_STARTED.json': 65536, 'CONTROL_RESULT.json': 65536, 'CONTROL_FAILURE.json': 65536, 'TAIL_RESULT.json': 65536, 'TAIL_FAILURE.json': 65536, 'TAIL_TRANSPORT_TRACE.json': 65536, 'REDIRECT_STARTED.json': 65536, 'REDIRECT_HEADERS.json': 65536, 'REDIRECT_RESULT.json': 65536, 'TAIL_STARTED.json': 65536, 'TAIL_HEADERS.json': 65536, 'transport_LAUNCH.json': 65536, 'transport_STAGE_RESULT.json': 65536, 'transport_STAGE_POSTWRITE.json': 65536, 'transport.stdout': 65536, 'transport.stderr': 65536, 'directory_LAUNCH.json': 65536, 'directory_STAGE_RESULT.json': 65536, 'directory_STAGE_POSTWRITE.json': 65536, 'directory.stdout': 65536, 'directory.stderr': 65536, 'presence_LAUNCH.json': 65536, 'presence_STAGE_RESULT.json': 65536, 'presence_STAGE_POSTWRITE.json': 65536, 'presence.stdout': 65536, 'presence.stderr': 65536, 'HYDROATLAS_DIRECTORY_RESULT.json': 65536, 'HYDROATLAS_DIRECTORY_FAILURE.json': 65536, 'logs/parse-'+job_id+'.out': 65536, 'logs/parse-'+job_id+'.err': 65536, 'HYDROATLAS_DIRECTORY_MEMBERS.json': 2097152, 'COMMON_SOURCE_PRESENCE_RESULT.json': 1048576, 'squeue_seq35.stdout': 65536, 'squeue_seq35.stderr': 65536, 'sacct_seq35.stdout': 65536, 'sacct_seq35.stderr': 65536};missing=[];used=sum(map(len,entries.values()))
for name,limit in limits.items():
 if name in entries:continue
 path=(submission_root/name if name.startswith('logs/') else root/name)
 if not path.exists():missing.append(name);continue
 value=read(path,limit);assert used+len(value)<=4194304;used+=len(value);entries[name]=value
state['control_terminal']=job_id=='NONE' or (root/'CONTROL_RESULT.json').exists() or (root/'CONTROL_FAILURE.json').exists()
states=[]
if job_id!='NONE' and state.get('sacct_exit_code')==0:
 for line in entries['sacct_seq'+str(sequence)+'.stdout'].decode().splitlines():
  fields=line.split('|')
  if fields[0]==job_id:assert len(fields)>=6;states.append(fields[1].split()[0].rstrip('+'))
assert len(states)<=1
state['scheduler_state']=states[0] if states else ('NO_JOB_TRANSPORT_FAILED' if job_id=='NONE' else 'UNKNOWN')
state['scheduler_terminal']=state['scheduler_state'] in ['NO_JOB_TRANSPORT_FAILED','COMPLETED','FAILED','TIMEOUT','OUT_OF_MEMORY','CANCELLED','NODE_FAIL','BOOT_FAIL','DEADLINE','PREEMPTED']
state['nonterminal_confirmed']=not state['control_terminal'] and state['scheduler_state'] in ['PENDING','RUNNING','CONFIGURING']
state.update(report_members=len(entries),missing_report_members=missing)
status='STATUS_seq'+str(sequence)+'.json';entries[status]=(json.dumps(state,indent=2)+'\n').encode()
with (root/status).open('xb') as stream:stream.write(entries[status])
index={name:dict(path=str(submission_root/'SUBMISSION_RESULT.json') if name=='MEMFIX_SUBMISSION_RESULT.json' else str(submission_root/name) if name.startswith('logs/') else str(root/name),bytes=len(raw),sha256=hashlib.sha256(raw).hexdigest()) for name,raw in entries.items()}
index_raw=(json.dumps(index,indent=2)+'\n').encode();assert len(index_raw)<=65536
packed_io=io.BytesIO()
with zipfile.ZipFile(packed_io,'w',compression=zipfile.ZIP_DEFLATED) as archive:
 for name,raw in sorted(entries.items()):archive.writestr(name,raw)
 archive.writestr('REPORT_FILES.json',index_raw)
packed=packed_io.getvalue();assert len(packed)<=1048576
filename='DELIVERY_seq'+str(sequence)+'_ATLAS_DIRECTORY.zip'
with (root/filename).open('xb') as stream:stream.write(packed)
print('OWN_ATLAS_DIRECTORY_JOB_ID='+job_id)
print('OWN_ATLAS_DIRECTORY_FILE='+filename)
print('OWN_ATLAS_DIRECTORY_BYTES='+str(len(packed)))
print('OWN_ATLAS_DIRECTORY_SHA256='+hashlib.sha256(packed).hexdigest())
print('OWN_ATLAS_DIRECTORY_BASE64_BEGIN');print(base64.b64encode(packed).decode());print('OWN_ATLAS_DIRECTORY_BASE64_END')
print('OWN_ATLAS_DIRECTORY_TERMINAL='+str(int(state['control_terminal'] or state['scheduler_terminal'])))
print('OWN_ATLAS_DIRECTORY_NONTERMINAL_CONFIRMED='+str(int(state['nonterminal_confirmed'])))
print('OWN_ATLAS_DIRECTORY_STATUS_DONE')
PY_OWN_TAIL_READ
