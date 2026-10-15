#!/usr/bin/env bash
set -eo pipefail
source /data1/home/sunyiq/miniconda3/etc/profile.d/conda.sh
conda activate nh_final
set -u
export PYTHONDONTWRITEBYTECODE=1
python -B /data1/home/sunyiq/zhenjiang_complete_comparison_20261015_recovery_005/hpc/audit_covariance_continuation_20261015.py
python -B /data1/home/sunyiq/zhenjiang_complete_comparison_20261015_recovery_005/hpc/submit_joseph_recovery_squeue_20261015.py
python3 - <<'PY'
import datetime,json,pathlib,subprocess
root=pathlib.Path('/data1/home/sunyiq/zhenjiang_complete_comparison_20261015_recovery_005')
case='explicit_gru__historical_capacity'
jobs=json.loads((root/'records/scheduler_jobs.json').read_text());job=str(jobs[case])
queries=[]
for command in (['squeue','-h','-u','sunyiq','-o','%i|%T|%Z|%e|%l|%P|%C|%b|%N'],
                ['sacct','-n','-X','-j',job,'--format=JobID,State,ExitCode,Start,End,NodeList','-P']):
    p=subprocess.run(command,capture_output=True,text=True,timeout=30)
    assert p.returncode==0,p.stderr
    queries.append({'command':command,'returncode':p.returncode,'stdout':p.stdout,'stderr':p.stderr})
print(json.dumps({'status':'covariance_formal_submission_status','checked_at_beijing':datetime.datetime.now(datetime.timezone(datetime.timedelta(hours=8))).isoformat(),
                 'case':case,'root':str(root),'job_id':job,'scheduler_jobs':jobs,'queries':queries,
                 'evaluation_values_read':False,'formal_progress_confirmed':False},sort_keys=True))
PY
