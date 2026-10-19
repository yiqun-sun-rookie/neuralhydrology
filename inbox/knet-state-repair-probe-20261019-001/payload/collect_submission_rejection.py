"""Read-only rejected-submission evidence export, with no sbatch or model call."""
import sys,json,subprocess,hashlib,io,tarfile,gzip,base64,datetime
from pathlib import Path
BASE=Path('/data1/home/sunyiq/knet_camels_hpc_20261012_001/attempts/state_channel_repair_probe_20261019_001')
sys.path.insert(0,str(BASE))
import safe_io as s
job=sys.argv[1];assert job.isdigit()
def command(args):
    try:
        p=subprocess.run(args,capture_output=True,text=True,timeout=20);return dict(returncode=p.returncode,stdout=p.stdout,stderr=p.stderr)
    except subprocess.TimeoutExpired:return dict(returncode=124,stdout='',stderr='read-only scheduler query timed out')
control=command(['scontrol','-o','show','job',job])
accounting=command(['sacct','-j',job,'--noheader','--parsable2','--format=JobID,JobName,State,ExitCode,ElapsedRaw,AllocCPUS,ReqMem,Submit,Start,End,WorkDir%180,SubmitLine%240,NodeList,NNodes'])
nodes=command(['sinfo','-p','hgpu4','-N','-h','-o','%N|%T|%m|%C'])
manifest=json.loads(s.read_checked(BASE/'deployment_manifest.json'))
source_names=[entry['path'] for entry in manifest['files']]+['deployment_manifest.json','submission_started.json','submission_stdout.txt','remote_preflight.json']
if (BASE/'submission.json').exists():source_names.append('submission.json')
data={};entries=[]
for name in sorted(set(source_names)):
    raw=s.read_checked(BASE/name);data[name]=raw;entries.append(dict(path=name,bytes=len(raw),sha256=hashlib.sha256(raw).hexdigest()))
identity=dict(experiment_id=BASE.name,remote_root=str(BASE),candidate_native_job_id=job,accepted_submission_json_present=(BASE/'submission.json').exists(),sbatch_stdout=s.read_checked(BASE/'submission_stdout.txt').decode(),collection_utc=datetime.datetime.now(datetime.timezone.utc).isoformat())
metadata=dict(schema='rejected_submission_evidence_v1',identity=identity,scontrol=control,accounting=accounting,partition_memory_snapshot=nodes,run_directory_exists=(BASE/'runs/04105700/attempt_001').exists(),files=entries)
data['collection_manifest.json']=(json.dumps(metadata,indent=2)+'\n').encode();stream=io.BytesIO()
with tarfile.open(fileobj=stream,mode='w') as tar:
    for name,raw in data.items():
        info=tarfile.TarInfo(name);info.size=len(raw);info.mtime=0;tar.addfile(info,io.BytesIO(raw))
payload=gzip.compress(stream.getvalue(),mtime=0);assert len(payload)<=8*1024**2
print('REJECTED_SUBMISSION_STATUS='+json.dumps({k:v for k,v in metadata.items() if k!='files'}),flush=True)
print('PROBE_ARCHIVE_METADATA='+json.dumps(dict(bytes=len(payload),sha256=hashlib.sha256(payload).hexdigest(),files=len(data))),flush=True)
print('PROBE_ARCHIVE_BASE64='+base64.b64encode(payload).decode(),flush=True)
