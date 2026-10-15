#!/bin/bash
set -eo pipefail
umask 077
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -B - <<'PY_XML_READ'
import base64,datetime,hashlib,json,pathlib,zipfile
root=pathlib.Path('/data1/home/sunyiq/china_input_completion_hpc_20261015_001/missing_vegetation_xml_v1')
expected_pid=int('38607')
assert root.resolve(strict=True)==root and not root.is_symlink()
def read(path,limit):
 assert path.resolve(strict=True)==path and not path.is_symlink() and path.is_file()
 size=path.stat().st_size;assert 0<=size<=limit
 value=path.read_bytes();assert len(value)==size
 return value
launch=json.loads(read(root/'LAUNCH.json',65536));assert launch['pid']==expected_pid
contract_raw=read(root/'MISSING_XML_CONTRACT.json',1048576)
assert hashlib.sha256(contract_raw).hexdigest()=='68f4c65b8f251c2b26a30a299349498d4b78220ec09e6cf833c20ed450ecb3e2'
contract=json.loads(contract_raw);assert len(contract['missing'])==1193
state=dict(server_utc=datetime.datetime.now(datetime.timezone.utc).isoformat(),pid=expected_pid,
 scientific_array_reads=0,model_calls=0,new_slurm_jobs=0,automatic_checks_enabled=False)
proc=pathlib.Path('/proc')/str(expected_pid)
def proc_read(name):
 path=proc/name;assert path.resolve(strict=True)==path and not path.is_symlink()
 with path.open('rb') as stream:raw=stream.read(16385)
 assert len(raw)<=16384
 return raw
try:
 raw=proc_read('cmdline');stat=proc_read('stat').decode()
 ticks=stat[stat.rfind(')')+2:].split()[19]
 state['own_helper_identity_matches']=(raw.split(b'\0')[:-1]==[x.encode() for x in launch['argv']]
  and launch['start_ticks'] is not None and ticks==launch['start_ticks'])
 state['process_state']=stat[stat.rfind(')')+2:].split()[0]
except FileNotFoundError:state['process_state']='NOT_PRESENT_NO_FAILURE_INFERRED'
names=['LAUNCH_REQUESTED.json','LAUNCH.json','CONTROL_STARTED.json','CONTROL_RESULT.json','CONTROL_FAILURE.json',
 'WORKER_LAUNCH.json','TLS_AND_RESOURCE.json','XML_RECOVERY_RESULT.json','XML_RECOVERY_FAILURE.json',
 'XML_PERIODS.json','worker.stdout','worker.stderr','control.stdout','control.stderr']
for item in contract['missing']:
 for suffix in ('.STARTED.json','.RESULT.json','.events.jsonl'):
  names.append('requests/'+item['key']+suffix)
assert len(names)<=3600
entries={};used=0;missing=[]
for name in names:
 path=root/name
 if not path.exists():missing.append(name);continue
 limit=4194304 if name=='XML_PERIODS.json' else 65536
 size=path.stat().st_size;assert used+size<=16777216
 value=read(path,limit);used+=len(value);entries[name]=value
state.update(report_members=len(entries),missing_report_members=missing,snapshot_only=True)
entries['STATUS_seq16.json']=(json.dumps(state,indent=2)+'\n').encode()
with (root/'STATUS_seq16.json').open('xb') as stream:stream.write(entries['STATUS_seq16.json'])
table={name:dict(path=str(root/name),bytes=len(value),sha256=hashlib.sha256(value).hexdigest()) for name,value in entries.items()}
index=(json.dumps(table,indent=2)+'\n').encode()
assert len(index)<=4194304 and used+len(entries['STATUS_seq16.json'])+len(index)<=16777216
target=root/'DELIVERY_seq16_XML.zip'
with zipfile.ZipFile(target,'x',compression=zipfile.ZIP_DEFLATED) as archive:
 archive.writestr('REPORT_FILES.json',index)
 for name,value in entries.items():archive.writestr(name,value)
assert target.stat().st_size<=4194304
raw=read(target,4194304)
print('OWN_XML_STATUS_PID='+str(expected_pid))
print('OWN_XML_FILE=DELIVERY_seq16_XML.zip')
print('OWN_XML_BYTES='+str(len(raw)))
print('OWN_XML_SHA256='+hashlib.sha256(raw).hexdigest())
print('OWN_XML_BASE64_BEGIN');print(base64.b64encode(raw).decode());print('OWN_XML_BASE64_END')
print('OWN_XML_STATUS_DONE')
PY_XML_READ
