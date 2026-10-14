#!/usr/bin/env bash
set -eo pipefail
source /data1/home/sunyiq/miniconda3/etc/profile.d/conda.sh
conda activate nh_final
set -u
export PYTHONDONTWRITEBYTECODE=1
cd /data1/home/sunyiq/zhenjiang_complete_comparison_20261015_recovery_004
python -B hpc/audit_covariance_continuation_20261015.py
python -B - <<'PY'
import datetime,hashlib,json,pathlib,subprocess
root=pathlib.Path.cwd();job='242582'
def record(p):
 b=p.read_bytes();return {'path':str(p),'bytes':len(b),'sha256':hashlib.sha256(b).hexdigest()}
source=pathlib.Path('/data1/home/sunyiq/zhenjiang_complete_comparison_20261012_recovery_003/hpc/prepare_recovery.py')
logs=[]
for p in root.joinpath('logs').glob('*_'+job+'.out'):
 b=p.read_bytes();logs.append(dict(record(p),text=b.decode(errors='replace')))
records={str(p.relative_to(root)):json.loads(p.read_bytes()) for p in sorted(root.joinpath('records').glob('covariance_submission_initial.*.json'))}
records['scheduler_jobs.json']=json.loads(root.joinpath('records/scheduler_jobs.json').read_bytes())
queries=[]
for c in [['squeue','-h','-u','sunyiq','-o','%i|%j|%T|%Z'],['sacct','-n','-X','-j',job,'--format=JobID,State,ExitCode,Start,End,NodeList,AllocTRES','-P']]:
 p=subprocess.run(c,capture_output=True,text=True,timeout=30);queries.append({'command':c,'returncode':p.returncode,'stdout':p.stdout,'stderr':p.stderr})
print(json.dumps({'status':'covariance_startup_failure_read_only_scene','checked_at_beijing':datetime.datetime.now(datetime.timezone(datetime.timedelta(hours=8))).isoformat(),'root':str(root),'job_id':job,'source_helper':record(source),'target_helper_exists':root.joinpath('hpc/prepare_recovery.py').exists(),'logs':logs,'records':records,'queries':queries,'evaluation_values_read':False,'scientific_or_scheduler_mutations':False},sort_keys=True))
PY
