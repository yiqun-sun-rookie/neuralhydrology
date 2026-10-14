#!/usr/bin/env bash
set -euo pipefail
python3 - <<'PY'
import datetime,hashlib,json,pathlib,subprocess
root=pathlib.Path('/data1/home/sunyiq/zhenjiang_complete_comparison_20261015_recovery_004')
case='explicit_gru__historical_capacity';run=case+'__tune_branch__filter_joint__s101__lr0p003'
def identity(p):
 b=p.read_bytes();return {'path':str(p),'bytes':len(b),'sha256':hashlib.sha256(b).hexdigest()}
code_files=sorted([*root.joinpath('src').glob('*.py'),*root.joinpath('scripts').glob('*.py'),*root.joinpath('vendor/pytides').glob('*.py')]);hashes={str(p.relative_to(root)):identity(p)['sha256'] for p in code_files};code=hashlib.sha256(json.dumps(hashes,sort_keys=True,separators=(',',':'),allow_nan=False).encode()).hexdigest();auth=json.loads((root/'records/authorization.json').read_bytes());assert code==auth['code_hash']
group=json.loads((root/'records'/case/'tune_branch_group_configs.json').read_bytes());assert len(group)==12
members={rid:{n:identity(root/'runs'/rid/n) for n in ['config.json','continuation.pt','failure.json','metrics.json']} for rid in group}
files={n:identity(root/n) for n in ['configs/protocol-v3.json','configs/registry-v3.json','records/authorization.json','records/data_preparation_complete.json','prepared/tuning/manifest.json','hpc/pathfix_covariance_recovery_squeue_20261015_004.slurm']}
queries=[]
for command in [['squeue','-h','-u','sunyiq','-o','%i|%j|%T|%Z'],['sacct','-n','-X','-j','242609','--format=JobID,State,ExitCode,Start,End,NodeList','-P']]:
 p=subprocess.run(command,capture_output=True,text=True,timeout=30);assert p.returncode==0;queries.append({'command':command,'stdout':p.stdout,'stderr':p.stderr,'returncode':p.returncode})
assert json.loads((root/'records/scheduler_jobs.json').read_bytes())[case]=='242609'
print(json.dumps({'status':'read_only_validation_covariance_source_identity','checked_at_beijing':datetime.datetime.now(datetime.timezone(datetime.timedelta(hours=8))).isoformat(),'source_root':str(root),'source_job':'242609','run_id':run,'code_hash':code,'source_code_file_hashes':hashes,'source_run_files':members[run],'all_member_source_files':members,'files':files,'queries':queries,'data_inputs_read':False,'checkpoints_loaded':False,'scientific_or_scheduler_mutations':False,'evaluation_values_read':False},sort_keys=True))
PY
