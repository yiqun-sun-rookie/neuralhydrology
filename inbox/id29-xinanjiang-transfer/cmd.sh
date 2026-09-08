#!/bin/bash
# One-shot deployment of the independently reviewed two-basin recovery payload.
set -eo pipefail
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -B - <<'PY'
import hashlib,json,pathlib,re,subprocess,tarfile

ORIGINAL=pathlib.Path('/data1/home/sunyiq/id29_xinanjiang_transfer_20260907_v01')
RECOVERY=pathlib.Path('/data1/home/sunyiq/id29_xinanjiang_transfer_20260907_v01_recovery_01')
PAYLOAD=pathlib.Path('/data1/home/sunyiq/hpc_mailbox/inbox/id29-xinanjiang-transfer/receiver_recovery_bundle.tar.gz')
EXPECTED_ARCHIVE='57921e5dbe9371908138bf46e9a01b926a8e720297fc0cfd031ed91dd2e73c37'
EXPECTED_MANIFEST='81c617b6fc9b66616b17400d2ad086100c4cc5229ec36ccbf96170107d8abaa2'
EXPECTED_SUMMARY='0d01d9643f7725432a89dade8a4854b008f6f015baf0edc6c0f847f9d0264da9'
EXPECTED_TRANSFER='5f644f707c9b67eacf89562e7484cfc42f859dfcdad597b1eeb58584a99a2d04'
EXPECTED_BUNDLE='59a8f8b50776086c5b1263e441cfc9cf80299b80feca24a60919d582d5d21545'
EXPECTED_RUNNER='be6c6dfaab387e9ed39c2b72f7f21d288bdb7efcc1ce0cdbc2ce5f970c356013'
EXPECTED_SLURM='2a9f5132a7c3b5ed760c7e77d9a88b45d3e1257ea2615b2a61a8e76bb5b5bb4f'

def digest(path): return hashlib.sha256(path.read_bytes()).hexdigest()
def require(value,message):
    if not value: raise ValueError(message)
def write(path,value):
    with path.open('x') as stream:
        json.dump(value,stream,sort_keys=True,indent=2,allow_nan=False); stream.write('\n')

require(not RECOVERY.exists(),'recovery root already exists; never resubmit or overwrite')
require(PAYLOAD.is_file() and digest(PAYLOAD)==EXPECTED_ARCHIVE,'recovery payload identity')
require(digest(ORIGINAL/'receiver/summary.json')==EXPECTED_SUMMARY,'original failure summary changed')
require(digest(ORIGINAL/'development/frozen_transfer.json')==EXPECTED_TRANSFER,'frozen transfer changed')
require(digest(ORIGINAL/'bundle/MANIFEST.json')==EXPECTED_BUNDLE,'frozen bundle changed')
status=subprocess.run(['sacct','-j','223833','-n','-P','--format=JobIDRaw,State,ExitCode'],
                      check=True,capture_output=True,text=True,timeout=40).stdout.splitlines()
require(any(row.split('|')[:3]==['223833','FAILED','1:0'] for row in status),'source job terminal identity')
queue=subprocess.run(['squeue','-h','-o','%i|%T'],check=True,capture_output=True,text=True,timeout=40).stdout.splitlines()
active=[row for row in queue if row.split('|',1)[0]=='223833']
require(not active,'source receiver job is still active; do not duplicate')

with tarfile.open(PAYLOAD,'r:gz') as archive:
    members=archive.getmembers(); names=[m.name for m in members]
    require(len(names)==len(set(n.casefold() for n in names))==15,'recovery archive member count/uniqueness')
    for member in members:
        path=pathlib.PurePosixPath(member.name)
        require(member.isfile() and not path.is_absolute() and len(path.parts)>1
                and path.parts[0]=='recovery' and '..' not in path.parts,'unsafe recovery member')
    RECOVERY.mkdir(exist_ok=False)
    for member in members:
        path=RECOVERY.joinpath(*pathlib.PurePosixPath(member.name).parts[1:])
        path.parent.mkdir(parents=True,exist_ok=True)
        with archive.extractfile(member) as source,path.open('xb') as target:
            while True:
                block=source.read(1<<20)
                if not block: break
                target.write(block)
require(digest(RECOVERY/'MANIFEST.json')==EXPECTED_MANIFEST,'recovery manifest identity')
manifest=json.loads((RECOVERY/'MANIFEST.json').read_text())
require(len(manifest)==14,'recovery manifest count')
for name,expected in manifest.items(): require(digest(RECOVERY/name)==expected,'recovery member changed: '+name)
require(manifest['run_receiver_recovery.py']==EXPECTED_RUNNER and manifest['receiver_recovery.slurm']==EXPECTED_SLURM,
        'recovery executable identity')
contract=json.loads((RECOVERY/'recovery_contract.json').read_text())
require(contract['basins']==['05120500','09492400'] and contract['expected_successful_arms']==16
        and contract['maximum_cpus']==2 and contract['maximum_hours']==1
        and contract['source_summary_sha256']==EXPECTED_SUMMARY,'recovery contract scope')
source_manifest={p.relative_to(ORIGINAL).as_posix():digest(p)
                 for p in sorted((ORIGINAL/'receiver').rglob('*')) if p.is_file()}
require(len(source_manifest)>360,'original receiver inventory unexpectedly small')
write(RECOVERY/'source_receiver_manifest.json',source_manifest)
(RECOVERY/'logs').mkdir()
write(RECOVERY/'approve_recovery.json',{
    'approved':True,'scope':'two_input_gate_failures_16_arms_only','basins':['05120500','09492400'],
    'source_job':'223833','source_summary_sha256':EXPECTED_SUMMARY,'transfer_sha256':EXPECTED_TRANSFER,
    'bundle_manifest_sha256':EXPECTED_BUNDLE,'recovery_archive_sha256':EXPECTED_ARCHIVE,
    'recovery_manifest_sha256':EXPECTED_MANIFEST,'runner_sha256':EXPECTED_RUNNER,'slurm_sha256':EXPECTED_SLURM,
    'reviewer':'second_model_independent_review','maximum_cpus':2,'maximum_hours':1,
    'user_authority':'later explicit instruction to restore an abnormally stopped monitored job'})
try:
    result=subprocess.run(['sbatch','--parsable',str(RECOVERY/'receiver_recovery.slurm')],cwd=RECOVERY,
                          capture_output=True,text=True,timeout=40)
except Exception as exc:
    write(RECOVERY/'submission_receipt.json',{'status':'uncertain','error':type(exc).__name__+': '+str(exc)})
    raise RuntimeError('recovery submission uncertain; preserve root and do not retry') from exc
write(RECOVERY/'submission_receipt.json',{'status':'returned','returncode':result.returncode,
      'stdout':result.stdout,'stderr':result.stderr})
require(result.returncode==0,'recovery sbatch failed; preserve root and do not retry')
job=result.stdout.strip()
require(re.fullmatch(r'[0-9]+(?:;[A-Za-z0-9_.-]+)?',job) is not None,
        'ambiguous recovery job id; inspect, never resubmit')
with (RECOVERY/'job_id.txt').open('x') as stream: stream.write(job+'\n')
print('RECOVERY_SUBMITTED_JOB='+job)
snapshot=subprocess.run(['squeue','-j',job.split(';')[0],'-o','%.18i %.20j %.10T %.10M %.6D %R'],
                        capture_output=True,text=True,timeout=40)
print(snapshot.stdout)
if snapshot.returncode: print('SQUEUE_SNAPSHOT_UNAVAILABLE',snapshot.stderr)
PY
