#!/bin/bash
set -eo pipefail
python='/data1/home/sunyiq/miniconda3/envs/knet_clean/bin/python'
export PYTHONNOUSERSITE=1 PYTHONDONTWRITEBYTECODE=1
unset PYTHONPATH
"$python" -B - <<'PY'
from datetime import datetime,timezone
import base64,hashlib,io,json,os,pathlib,stat,subprocess,zipfile
root=pathlib.Path('/data1/home/sunyiq/kalmannet_tukf09_protection_diagnostic_20261001_attempt1')
assert root.is_dir() and not root.is_symlink()
submission=json.loads((root/'control'/'submission_confirmed.json').read_bytes())
assert submission['status']=='SINGLE_SYNTHETIC_JOB_SUBMISSION_CONFIRMED'
job=str(submission['job_id'])
assert job.isascii() and job.isdigit()
query=subprocess.run(['sacct','-j',job,'-n','-P','--format=JobID,State,ExitCode,Elapsed,MaxRSS,NodeList,AllocCPUS,Start,End'],
                     capture_output=True,timeout=30,check=True)
assert len(query.stdout)+len(query.stderr)<65536
lines=[line.split('|') for line in query.stdout.decode().splitlines() if line.strip()]
job_lines=[line for line in lines if line[0]==job]
assert len(job_lines)==1
state=job_lines[0][1].split()[0].rstrip('+')
assert state in {'COMPLETED','FAILED','TIMEOUT','OUT_OF_MEMORY','NODE_FAIL','CANCELLED','BOOT_FAIL','PREEMPTED','DEADLINE'}, 'job is not terminal'
queue=subprocess.run(['squeue','-j',job,'-h','-o','%i|%T'],capture_output=True,timeout=30)
assert len(queue.stdout)+len(queue.stderr)<65536
assert queue.returncode==0 or (queue.returncode==1 and b'Invalid job id specified' in queue.stderr), 'active-queue query unavailable'
assert not queue.stdout.strip(), 'job remains in active scheduler queue'
def inventory():
    output=[]
    for path in sorted(root.rglob('*')):
        info=path.lstat()
        assert not stat.S_ISLNK(info.st_mode)
        if stat.S_ISREG(info.st_mode):
            assert info.st_nlink==1
            output.append({'path':str(path.relative_to(root)),'bytes':info.st_size,'source_mtime_ns':info.st_mtime_ns})
        else:
            assert stat.S_ISDIR(info.st_mode)
    assert len(output)<16384 and sum(item['bytes'] for item in output)<=67108864
    return output
before=inventory()
buffer=io.BytesIO()
with zipfile.ZipFile(buffer,'w',compression=zipfile.ZIP_DEFLATED,compresslevel=6) as archive:
    for item in before:
        path=root/item['path']
        data=path.read_bytes()
        assert len(data)==item['bytes']
        item['sha256']=hashlib.sha256(data).hexdigest()
        entry=zipfile.ZipInfo('raw/'+item['path'],date_time=(1980,1,1,0,0,0))
        entry.external_attr=(stat.S_IFREG|0o600)<<16
        entry.compress_type=zipfile.ZIP_DEFLATED
        archive.writestr(entry,data)
after=inventory()
assert [{k:v for k,v in item.items() if k!='sha256'} for item in before]==after, 'terminal evidence changed during capture'
data=buffer.getvalue()
assert len(data)<=67108864
manifest={'kind':'readonly_synthetic_terminal_capture','time_iso_utc':datetime.now(timezone.utc).isoformat(),
          'job_id':int(job),'scheduler_state':state,'scheduler_raw':query.stdout.decode(),
          'queue_raw':{'returncode':queue.returncode,'stdout':queue.stdout.decode(),'stderr':queue.stderr.decode()},
          'file_count':len(before),'total_raw_bytes':sum(item['bytes'] for item in before),
          'files':before,'zip_bytes':len(data),'zip_sha256':hashlib.sha256(data).hexdigest(),
          'remote_output_files_created':0,'scientific_model_execution':False,'scheduler_changes':False}
print('TERMINAL_CAPTURE_MANIFEST_BEGIN')
print(json.dumps(manifest,sort_keys=True))
print('TERMINAL_CAPTURE_MANIFEST_END')
print('TERMINAL_CAPTURE_ZIP_BASE64_BEGIN')
print(base64.b64encode(data).decode())
print('TERMINAL_CAPTURE_ZIP_BASE64_END')
PY
