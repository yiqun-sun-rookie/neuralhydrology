#!/bin/bash
set -eo pipefail
umask 077
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -B - <<'PY_BODY_READ_19'
import base64,datetime,hashlib,json,pathlib,zipfile
root=pathlib.Path('/data1/home/sunyiq/china_input_completion_hpc_20261015_001/vegetation_body_acquisition_v1');expected_pid=int('19539');sequence=19
assert root.resolve(strict=True)==root and not root.is_symlink()
def read(path,limit):
 assert path.resolve(strict=True)==path and not path.is_symlink() and path.is_file()
 size=path.stat().st_size;assert 0<=size<=limit
 value=path.read_bytes();assert len(value)==size
 return value
launch=json.loads(read(root/'LAUNCH.json',65536));assert launch['pid']==expected_pid
raw=read(root/'VEGETATION_BODY_CONTRACT.json',8*1024**2)
assert hashlib.sha256(raw).hexdigest()=='652be55ddf97eec773cff1ac99f9dab6e45828d023a8e2a60a808699084830fd'
contract=json.loads(raw);assert len(contract['items'])==1196
state=dict(server_utc=datetime.datetime.now(datetime.timezone.utc).isoformat(),pid=expected_pid,
 scientific_array_reads=0,model_calls=0,new_slurm_jobs=0,automatic_checks_enabled=False)
proc=pathlib.Path('/proc')/str(expected_pid)
def proc_read(name):
 path=proc/name;assert path.resolve(strict=True)==path and not path.is_symlink()
 with path.open('rb') as stream:value=stream.read(16385)
 assert len(value)<=16384
 return value
try:
 raw=proc_read('cmdline');stat=proc_read('stat').decode();parts=stat[stat.rfind(')')+2:].split()
 state.update(own_helper_identity_matches=(raw.split(b'\0')[:-1]==[x.encode() for x in launch['argv']]
  and launch['start_ticks'] is not None and parts[19]==launch['start_ticks']),process_state=parts[0])
except FileNotFoundError:state['process_state']='NOT_PRESENT_NO_FAILURE_INFERRED'
state['control_terminal']=(root/'CONTROL_RESULT.json').exists() or (root/'CONTROL_FAILURE.json').exists()
names=['LAUNCH_REQUESTED.json','LAUNCH.json','CONTROL_STARTED.json','CONTROL_RESULT.json','CONTROL_FAILURE.json',
 'WORKER_LAUNCH.json','TLS_AND_RESOURCE.json','REUSED_BODIES.json','BODY_ACQUISITION_RESULT.json',
 'BODY_ACQUISITION_FAILURE.json','BODY_PERIODS.json','worker.stdout','worker.stderr','control.stdout','control.stderr']
for item in contract['items']:
 if item['reuse'] is None:
  for suffix in ('.STARTED.json','.RESULT.json','.events.jsonl'):names.append('requests/'+item['key']+suffix)
assert len(names)<=3610
entries={};used=0;missing=[]
for name in names:
 path=root/name
 if not path.exists():missing.append(name);continue
 limit=8*1024**2 if name=='BODY_PERIODS.json' else 65536
 size=path.stat().st_size;assert used+size<=24*1024**2
 value=read(path,limit);used+=len(value);entries[name]=value
state.update(report_members=len(entries),missing_report_members=missing,snapshot_only=True)
status_name='STATUS_seq'+str(sequence)+'.json'
entries[status_name]=(json.dumps(state,indent=2)+'\n').encode();assert len(entries[status_name])<=1048576
with (root/status_name).open('xb') as stream:stream.write(entries[status_name])
table={name:dict(path=str(root/name),bytes=len(value),sha256=hashlib.sha256(value).hexdigest()) for name,value in entries.items()}
index=(json.dumps(table,indent=2)+'\n').encode()
assert len(index)<=4*1024**2 and used+len(entries[status_name])+len(index)<=24*1024**2
target=root/('DELIVERY_seq'+str(sequence)+'_BODY.zip')
with zipfile.ZipFile(target,'x',compression=zipfile.ZIP_DEFLATED) as archive:
 archive.writestr('REPORT_FILES.json',index)
 for name,value in entries.items():archive.writestr(name,value)
assert target.stat().st_size<=5*1024**2
raw=read(target,5*1024**2)
print('OWN_BODY_STATUS_PID='+str(expected_pid))
print('OWN_BODY_TERMINAL='+str(int(state['control_terminal'])))
print('OWN_BODY_FILE='+target.name);print('OWN_BODY_BYTES='+str(len(raw)))
print('OWN_BODY_SHA256='+hashlib.sha256(raw).hexdigest())
print('OWN_BODY_BASE64_BEGIN');print(base64.b64encode(raw).decode());print('OWN_BODY_BASE64_END')
print('OWN_BODY_STATUS_DONE')
PY_BODY_READ_19
