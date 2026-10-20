"""Stage frozen files and make exactly one recorded submission."""
import os,sys,io,json,re,hashlib,tarfile,subprocess,datetime
from pathlib import Path
root=Path('/data1/home/sunyiq/knet_camels_hpc_20261012_001/attempts/state_channel_init_probe_20261020_001')
payload=Path(sys.argv[1]);expected=sys.argv[2];assert re.fullmatch('[0-9a-f]{64}',expected)
for p in (root,*root.parents,payload,*payload.parents):assert not p.is_symlink()
raw=payload.read_bytes();assert hashlib.sha256(raw).hexdigest()==expected
root.mkdir(parents=True,exist_ok=True)
with tarfile.open(fileobj=io.BytesIO(raw),mode='r:gz') as tar:
    seen=set()
    for member in tar.getmembers():
        rel=Path(member.name);assert member.isfile() and not rel.is_absolute() and '..' not in rel.parts and member.name not in seen;seen.add(member.name)
        path=root/rel
        for p in (path,*path.parents):assert not p.is_symlink()
        content=tar.extractfile(member).read();path.parent.mkdir(parents=True,exist_ok=True)
        if path.exists():assert path.read_bytes()==content
        else:
            with path.open('xb') as f:f.write(content)
sys.path.insert(0,str(root));import safe_io as s
from probe_protocol import submission_env,MEMORY_ENV
manifest=json.loads(s.read_checked(root/'deployment_manifest.json'))
for row in manifest['files']:
    code=s.read_checked(root/row['path'],row['sha256']);assert len(code)==row['bytes']
    if row['path'].endswith('.py'):compile(code,row['path'],'exec')
script=s.read_checked(root/'probe.slurm');assert b'\r' not in script and b'--mem' not in script
(root/'logs').mkdir(exist_ok=True)
identity_path=root/'execution_identity.json'
if identity_path.exists():
    print('DEPLOYMENT_RESULT='+s.read_checked(identity_path).decode());raise SystemExit(0)
if (root/'submission_started.json').exists():raise RuntimeError('Existing submission intent; inspect only, no second submission')
auth=json.loads(s.read_checked(root/'execution_authorization.json'));assert auth['status']=='AUTHORIZED'
template=root.parents[1]/'template';mraw=s.read_checked(template/'bundle_manifest.json',auth['template_manifest_sha256'])
for row in json.loads(mraw)['files']:s.read_checked(template/row['path'],row['sha256'])
s.create('remote_preflight.json',dict(status='PASS',template_manifest_sha256=auth['template_manifest_sha256'],utc=datetime.datetime.now(datetime.timezone.utc).isoformat()))
intent=dict(utc=datetime.datetime.now(datetime.timezone.utc).isoformat(),archive_sha256=expected,script_sha256=hashlib.sha256(script).hexdigest(),channel='knet-state-init-probe-20261020-001',sequence=1,submission_replay_forbidden=True)
s.create('submission_started.json',intent)
env=submission_env(os.environ);removed=[x for x in MEMORY_ENV if x in os.environ]
reply=subprocess.run(['sbatch',str(root/'probe.slurm')],env=env,capture_output=True,text=True)
text=reply.stdout+reply.stderr;matches=re.findall(r'Submitted batch job ([0-9]+)',text)
s.create('submission_reply.json',dict(returncode=reply.returncode,stdout=reply.stdout,stderr=reply.stderr,removed_memory_environment_names=removed))
s.create('submission_stdout.txt',text.encode())
success=reply.returncode==0 and len(matches)==1
rejected=not success and ('Batch job submission failed' in text or 'Memory specification can not be satisfied' in text)
record=dict(status='SUBMITTED' if success else 'SUBMISSION_REJECTED' if rejected else 'SUBMISSION_OUTCOME_UNKNOWN',job_id=matches[0] if success else None,remote_root=str(root),channel=intent['channel'],deployment_sequence=1,archive_sha256=expected,script_sha256=intent['script_sha256'],contract_sha256=hashlib.sha256(s.read_checked(root/'probe_contract.json')).hexdigest(),submitted_utc=datetime.datetime.now(datetime.timezone.utc).isoformat(),sbatch_returncode=reply.returncode,sbatch_reply=text,submission_count=1)
if success:
    s.create('submission.json',record)
    control=subprocess.run(['scontrol','-d','show','job',record['job_id']],capture_output=True,text=True,timeout=15)
    s.create('submission_scontrol.json',dict(returncode=control.returncode,stdout=control.stdout,stderr=control.stderr))
s.create('execution_identity.json',record);print('DEPLOYMENT_RESULT='+json.dumps(record),flush=True)
