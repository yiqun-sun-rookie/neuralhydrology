#!/usr/bin/env bash
set -euo pipefail
python3 - <<'PY'
import base64,datetime,hashlib,json,pathlib,subprocess
ORIGINAL=pathlib.Path('/data1/home/sunyiq/zhenjiang_complete_comparison_20261006_002')
ROOT=pathlib.Path('/data1/home/sunyiq/zhenjiang_complete_comparison_20261006_recovery_001')
CASE='explicit_gru__historical_capacity'
RUN=CASE+'__tune_branch__filter_joint__s101__lr0p003'
def sha(path):
    h=hashlib.sha256()
    with path.open('rb') as f:
        for chunk in iter(lambda:f.read(1048576),b''): h.update(chunk)
    return h.hexdigest()
def evidence(path,include=False):
    if not path.exists(): return {'path':str(path),'exists':False}
    st=path.stat(); d={'path':str(path),'exists':True,'bytes':st.st_size,'mtime_ns':st.st_mtime_ns,'sha256':sha(path)}
    if include: d['base64']=base64.b64encode(path.read_bytes()).decode()
    return d
def command(args):
    p=subprocess.run(args,capture_output=True,text=True,timeout=30)
    return {'command':args,'returncode':p.returncode,'stdout':p.stdout,'stderr':p.stderr}
jobs=json.loads((ROOT/'records/scheduler_jobs.json').read_text())
job=str(jobs[CASE]); assert job.isdigit()
report={'status':'read_only_gradient_fault_source_probe','checked_at_beijing':datetime.datetime.now(datetime.timezone(datetime.timedelta(hours=8))).isoformat(),'source_root':str(ROOT),'case':CASE,'run':RUN,'scheduler_jobs':jobs,'scheduler_queries':[command(['squeue','-h','-j',job,'-o','%i|%j|%T|%R|%N']),command(['sacct','-n','-X','-j',job,'--format=JobID,JobName,State,ExitCode,Elapsed,NodeList,Reason','-P']),command(['scontrol','show','job',job])],'training_inputs_read':False,'checkpoints_loaded':False,'evaluation_values_read':False,'source_files_written':False}
files=sorted([*ROOT.joinpath('src').glob('*.py'),*ROOT.joinpath('scripts').glob('*.py'),*ROOT.joinpath('vendor/pytides').glob('*.py')])
hashes={p.relative_to(ROOT).as_posix():sha(p) for p in files}
report['code_file_hashes']=hashes
report['code_hash']=hashlib.sha256(json.dumps(hashes,sort_keys=True,separators=(',',':'),allow_nan=False).encode()).hexdigest()
report['metadata_files']={}
for name in ['records/authorization.json','records/data_preparation_complete.json','configs/protocol-v3.json','configs/registry-v3.json','prepared/tuning_manifest.json','records/'+CASE+'/tune_foundation_group_outcome.json','records/'+CASE+'/tune_branch_group_configs.json']:
    p=ROOT/name;d=evidence(p);report['metadata_files'][name]=d
    if p.exists() and p.stat().st_size<200000 and not name.endswith('registry-v3.json'): d['value']=json.loads(p.read_text())
report['runs']={}
for folder in sorted(ROOT.joinpath('runs').glob(CASE+'__tune_branch__*')):
    report['runs'][folder.name]={n:evidence(folder/n,include=(n=='config.json' and folder.name==RUN)) for n in ['config.json','continuation.pt','metrics.json','failure.json']}
    report['runs'][folder.name]['failure_value']=json.loads((folder/'failure.json').read_text())
report['slurm_sources']=[evidence(ORIGINAL/'hpc/pathfix_explicit_gru__historical_capacity.slurm',True),evidence(ROOT/'hpc/recover_case.slurm',True)]
report['submission_provenance']=[evidence(p,True) for p in sorted(ORIGINAL.joinpath('hpc').glob('pathfix*historical_capacity*.json'))]+[evidence(ROOT/'records/recovery_submission_attempt.json',True),evidence(ROOT/'records/recovery_submission_response.json',True)]
print(json.dumps(report,sort_keys=True,allow_nan=False))
PY
