#!/bin/bash
set -eo pipefail
umask 077
export CUDA_VISIBLE_DEVICES='' PYTHONDONTWRITEBYTECODE=1
exec timeout --signal=TERM --kill-after=5s 30s /data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -B - <<'PY_OWN_SUBMISSION_READ'
import base64,datetime,hashlib,io,json,pathlib,zipfile
root=pathlib.Path('/data1/home/sunyiq/china_input_completion_hpc_20261015_001/hydroatlas_login_tail_compute_parse_v1')
assert root.resolve(strict=True)==root
def read(name):
 path=root/name
 assert path.resolve(strict=True)==path and path.is_file() and not path.is_symlink()
 before=path.stat();assert 0<=before.st_size<=65536
 raw=path.read_bytes();after=path.stat()
 assert len(raw)==before.st_size==after.st_size and before.st_mtime_ns==after.st_mtime_ns
 return raw
contract=read('TAIL_CONTRACT.json')
assert len(contract)==1373 and hashlib.sha256(contract).hexdigest()=='e3070acd66ffab461ed05242321a67225a0c784e3bdc35721a32fc591ef87b87'
entries={};missing=[];used=0
for name in ['DEPLOYMENT_STARTED.json', 'SUBMISSION_STARTED.json', 'SUBMISSION_RESULT.json', 'LOGIN_CONTROL_RESULT.json', 'LOGIN_CONTROL_FAILURE.json', 'TAIL_RESULT.json', 'TAIL_FAILURE.json', 'TAIL_TRANSPORT_TRACE.json', 'REDIRECT_STARTED.json', 'REDIRECT_HEADERS.json', 'REDIRECT_RESULT.json', 'TAIL_STARTED.json', 'TAIL_HEADERS.json', 'transport_LAUNCH.json', 'transport_STAGE_RESULT.json', 'transport_STAGE_POSTWRITE.json', 'transport.stdout', 'transport.stderr']:
 if not (root/name).exists():missing.append(name);continue
 raw=read(name);used+=len(raw);assert used<=2097152;entries[name]=raw
state=dict(server_utc=datetime.datetime.now(datetime.timezone.utc).isoformat(),
 job_id='UNKNOWN_NOT_QUERIED',scheduler_state='NOT_QUERIED',remote_root=str(root),
 missing_report_members=missing,report_members=len(entries),snapshot_only=True,
 source_gets=0,new_slurm_jobs=0,queue_queries=0,scientific_array_reads=0,model_calls=0,
 input_admission_approved=False,prediction_approved=False,automatic_checks_enabled=False)
entries['SUBMISSION_RECORD_STATUS_seq33.json']=(json.dumps(state,indent=2)+'\n').encode()
with (root/'SUBMISSION_RECORD_STATUS_seq33.json').open('xb') as stream:stream.write(entries['SUBMISSION_RECORD_STATUS_seq33.json'])
index={name:dict(path=str(root/name),bytes=len(raw),sha256=hashlib.sha256(raw).hexdigest()) for name,raw in entries.items()}
index_raw=(json.dumps(index,indent=2)+'\n').encode();assert len(index_raw)<=65536
buffer=io.BytesIO()
with zipfile.ZipFile(buffer,'w',compression=zipfile.ZIP_DEFLATED) as archive:
 for name,raw in sorted(entries.items()):archive.writestr(name,raw)
 archive.writestr('REPORT_FILES.json',index_raw)
packed=buffer.getvalue();assert len(packed)<=1048576
with (root/'SUBMISSION_RECORD_seq33.zip').open('xb') as stream:stream.write(packed)
print('OWN_ATLAS_SUBMISSION_FILE=SUBMISSION_RECORD_seq33.zip')
print('OWN_ATLAS_SUBMISSION_BYTES='+str(len(packed)))
print('OWN_ATLAS_SUBMISSION_SHA256='+hashlib.sha256(packed).hexdigest())
print('OWN_ATLAS_SUBMISSION_BASE64_BEGIN');print(base64.b64encode(packed).decode());print('OWN_ATLAS_SUBMISSION_BASE64_END')
print('OWN_ATLAS_SUBMISSION_DIAGNOSTIC_DONE')
PY_OWN_SUBMISSION_READ
