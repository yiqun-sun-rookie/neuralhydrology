#!/usr/bin/env bash
set -eo pipefail
source /data1/home/sunyiq/miniconda3/etc/profile.d/conda.sh
conda activate nh_final
set -u
export PYTHONDONTWRITEBYTECODE=1
export CUDA_VISIBLE_DEVICES=""
python -B - <<'SQRT_COMPLETE_PROBE'
import base64,datetime,gzip,hashlib,json,pathlib,subprocess
root=pathlib.Path('/data1/home/sunyiq/zhenjiang_sqrt_covariance_repair_20261017_001')
jobs=json.loads((root/'records/scheduler_jobs.json').read_bytes())
assert jobs=={'sqrt_gpu_admission':'244223'}
assert hashlib.sha256((root/'gpu_spec.json').read_bytes()).hexdigest()=='74533563fdba6a1d20ce5068eba8b2e9a1a63a5b96af3866ff326db9bfd407d1'
job=jobs['sqrt_gpu_admission'];base='/usr/local/globle/softs/slurm/19.05.4.1/bin/'
def query(arguments):
    p=subprocess.run(arguments,capture_output=True,text=True,timeout=40)
    return {'command':arguments,'returncode':p.returncode,'stdout':p.stdout,'stderr':p.stderr}
acct=query([base+'sacct','-n','-X','-j',job,'--format=JobID,State,ExitCode,Start,End,NodeList','-P'])
assert acct['returncode']==0,acct
entries=[line.split('|') for line in acct['stdout'].splitlines() if line.strip()]
assert len(entries)<=1 and (not entries or entries[0][0]==job)
queue=query([base+'squeue','-h','-j',job,'-o','%i|%T|%N|%Z|%S|%e|%l|%r'])
resolved=False
if queue['returncode']:
    assert queue['stdout']=='' and queue['stderr'].strip()=='slurm_load_jobs error: Invalid job id specified',queue
    assert len(entries)==1 and entries[0][1] in ['COMPLETED','FAILED','TIMEOUT','CANCELLED','NODE_FAIL','OUT_OF_MEMORY'],acct
    assert entries[0][3] not in ['Unknown','N/A',''] and entries[0][4] not in ['Unknown','N/A','']
    resolved=True
record={'status':'sqrt_gpu_workflow_status','root':str(root),'job_id':job,'scheduler_jobs':jobs,
        'checked_at':datetime.datetime.now(datetime.timezone(datetime.timedelta(hours=8))).isoformat(),
        'queue':queue,'accounting':acct,'terminal_accounting_confirms_live_queue_absence':resolved,
        'formal_epochs_added':0,'documents':{},'logs':{}}
for name in ['records/gpu_hardware.json','records/gpu_original39.json','records/gpu_original39_output.json',
             'records/gpu_bootstrap.json','evidence_gpu/result.json']:
    path=root/name
    if not path.is_file():continue
    raw=path.read_bytes();value=json.loads(raw)
    if name=='evidence_gpu/result.json' and 'combined_training_stability' in value:
        value['combined_training_stability']['step_jitter_count']=len(value['combined_training_stability'].pop('step_jitters'))
    record['documents'][name]={'bytes':len(raw),'sha256':hashlib.sha256(raw).hexdigest(),
        'encoding':'gzip_base64_complete_json','content':base64.b64encode(gzip.compress(raw,mtime=0)).decode(),'value':value}
for path in (root/'logs').glob('*_'+job+'.out'):
    with path.open('rb') as stream:
        stream.seek(max(0,path.stat().st_size-12000));tail=stream.read().decode(errors='replace')
    record['logs'][path.name]={'bytes':path.stat().st_size,'tail':tail}
print(json.dumps(record,sort_keys=True),flush=True)
SQRT_COMPLETE_PROBE
