#!/bin/bash
set -eo pipefail
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -B - <<'PY_READ'
import base64,datetime,hashlib,io,json,pathlib,re,subprocess,zipfile
root=pathlib.Path('/data1/home/sunyiq/china_input_completion_hpc_20261015_001/terrain_unit_provenance_v1')
assert root.resolve(strict=True)==root and not root.is_symlink()
expected_job='243151'
jobfile=root/'OWN_RECOVERY_JOB_ID'
assert not jobfile.is_symlink() and jobfile.read_text()==expected_job+'\n'
submitted=json.loads((root/'SUBMISSION_RESULT.json').read_bytes())
assert submitted['exit_code']==0 and re.findall(r'^Submitted batch job ([0-9]+)$',submitted['stdout'],re.M)==[expected_job]
print('OWN_RECOVERY_QUERY_JOB_ID='+expected_job)
print('OWN_RECOVERY_SERVER_QUERY_UTC='+datetime.datetime.now(datetime.timezone.utc).isoformat())
for label,args in [('SQUEUE',['squeue','-h','-j',expected_job,'-o','%i|%T|%N|%C|%M']),
 ('SACCT',['sacct','-j',expected_job,'--format=JobID,State,ExitCode,Elapsed,AllocCPUS,AllocTRES,MaxRSS','--parsable2','--noheader'])]:
 try:
  result=subprocess.run(args,capture_output=True,timeout=12)
  assert len(result.stdout)<=65536 and len(result.stderr)<=65536
  print(result.stdout.decode('utf-8','replace'),end='')
  print(result.stderr.decode('utf-8','replace'),end='')
  print('OWN_RECOVERY_'+label+'_EXIT='+str(result.returncode))
 except Exception as error:print('OWN_RECOVERY_'+label+'_ERROR='+type(error).__name__+':'+str(error))
for name in ['fetch.stdout','fetch.stderr']:
 path=root/name
 if path.is_file():
  assert not path.is_symlink()
  print('OWN_RECOVERY_LOG='+name)
  with path.open('rb') as stream:print(stream.read(8192).decode('utf-8','replace'))
allowed={'UNIT_PROVENANCE.json','UNIT_PROVENANCE_REVIEW.json','REPORT_PACK_FAILURE.json','SOURCE_HANDOFF_EVIDENCE.json','FETCH_STARTED.json','FETCH_RESULT.json','FETCH_FAILURE.json','FETCH_REPORT_FILES.json',
 'FETCH_RETAINED_EVIDENCE_INDEX.json','SUBMISSION_STARTED.json','SUBMISSION_RESULT.json','OWN_RECOVERY_JOB_ID',
 'acquire/SOURCE_RESULT.json','acquire/FAILURE.json','catalog/FUTURE_SOURCE_MANIFEST.json','catalog/FAILURE.json',
 'RECOVERY_RESULT.json','RECOVERY_FAILURE.json','REPORT_FILES.json','extract/SOURCE_RESULT.json',
 'extract/FAILURE.json','extract/DEM_HEADER.json','headers/HEADER_RESULT.json','headers/FAILURE.json',
 'terrain_main/TOPOGRAPHY_CONTRACT.json','terrain_main/SUMMARY.json','terrain_main/FAILURE.json',
 'terrain_independent/INDEPENDENT_CONTRACT.json','terrain_independent/INDEPENDENT_RESULT.json',
 'terrain_independent/ALL_DIFFERENCES.jsonl','terrain_independent/FAILURE.json','HPC_RETAINED_EVIDENCE_INDEX.json'}
for stage in ('source_bytes','catalog','sources','headers','terrain_main','terrain_independent'):
 allowed.update(stage+s for s in ('.stdout','.stderr','_STARTED.json','_EXECUTION.json'))
for number in range(1,5):
 allowed.update(f'acquire/SOURCE_{number}_{s}.json' for s in ('STARTED','HEADERS','RESULT'))
def sha(raw):return hashlib.sha256(raw).hexdigest()
def emit(name,maximum):
 path=root/name
 if not path.is_file():return
 assert not path.is_symlink() and path.stat().st_size<=maximum
 raw=path.read_bytes()
 assert 0<len(raw)<=maximum
 print('OWN_RECOVERY_FILE='+name)
 print('OWN_RECOVERY_BYTES='+str(len(raw)))
 print('OWN_RECOVERY_SHA256='+sha(raw))
 print('OWN_RECOVERY_BASE64_BEGIN')
 print(base64.b64encode(raw).decode())
 print('OWN_RECOVERY_BASE64_END')
entries={}
for marker,archive_name,table_name in [('FETCH_REPORTS_READY.json','FETCH_REPORTS.zip','FETCH_REPORT_FILES.json'),
 ('COMPUTE_REPORTS_READY.json','RECOVERY_REPORTS.zip','REPORT_FILES.json')]:
 path=root/marker
 if not path.is_file():continue
 desc=json.loads(path.read_bytes())
 archive_path=root/archive_name
 assert desc['path']==str(archive_path) and archive_path.stat().st_size==desc['bytes']<=4194304
 archive_raw=archive_path.read_bytes()
 assert sha(archive_raw)==desc['sha256']
 with zipfile.ZipFile(io.BytesIO(archive_raw)) as archive:
  names=archive.namelist()
  assert len(names)==len(set(names)) and set(names)<=allowed
  assert sum(item.file_size for item in archive.infolist())<=128*1024**2
  table_length=archive.getinfo(table_name).file_size
  if table_name in entries:
   assert len(entries[table_name])==table_length
  else:
   assert sum(map(len,entries.values()))+table_length<=128*1024**2
  table_raw=archive.read(table_name)
  if table_name in entries:assert entries[table_name]==table_raw
  entries[table_name]=table_raw
  table=json.loads(table_raw)
  assert set(table)==set(names)-{table_name}
  for name in names:
   length=archive.getinfo(name).file_size
   if name not in entries:
    assert sum(map(len,entries.values()))+length<=128*1024**2
   else:
    assert len(entries[name])==length
   value=archive.read(name)
   if name!=table_name:
    assert table[name]['path']==str(root/name) and len(value)==table[name]['bytes'] and sha(value)==table[name]['sha256']
   if name in entries:assert entries[name]==value
   entries[name]=value
if entries:
 assert sum(map(len,entries.values()))<=128*1024**2
 delivery=root/'DELIVERY_seq14_REPORTS.zip'
 assert not delivery.exists()
 table={name:dict(path=str(root/name),bytes=len(raw),sha256=sha(raw)) for name,raw in entries.items()}
 with zipfile.ZipFile(delivery,'x',compression=zipfile.ZIP_DEFLATED) as archive:
  archive.writestr('DELIVERY_FILES.json',(json.dumps(table,ensure_ascii=False,indent=2)+'\n').encode())
  for name,raw in entries.items():archive.writestr(name,raw)
 if delivery.stat().st_size<=4194304:emit(delivery.name,4194304)
 else:print('OWN_RECOVERY_DELIVERY_OVER_LIMIT_RETAINED')
for name in ['UNIT_PROVENANCE.json','UNIT_PROVENANCE_REVIEW.json','REPORT_PACK_FAILURE.json','SOURCE_HANDOFF_EVIDENCE.json','acquire/SOURCE_RESULT.json','FETCH_RESULT.json','FETCH_FAILURE.json','RECOVERY_RESULT.json','RECOVERY_FAILURE.json',
             'FETCH_DELIVERY_FAILURE.json']:
 emit(name,65536)
for name in ['FETCH_STARTED.json','FETCH_RESULT.json','SUBMISSION_STARTED.json','OWN_RECOVERY_JOB_ID',
 'catalog/FUTURE_SOURCE_MANIFEST.json','extract/DEM_HEADER.json','headers/HEADER_RESULT.json',
 'terrain_main/SUMMARY.json','terrain_independent/INDEPENDENT_RESULT.json','RECOVERY_RESULT.json']:
 print('OWN_RECOVERY_PATH_EXISTS='+name+'|'+str((root/name).exists()))
print('OWN_RECOVERY_READ_DONE')
PY_READ
