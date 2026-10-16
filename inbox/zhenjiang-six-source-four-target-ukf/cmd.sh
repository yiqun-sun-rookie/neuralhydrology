#!/usr/bin/env bash
set -eo pipefail
source /data1/home/sunyiq/miniconda3/etc/profile.d/conda.sh
conda activate nh_final
set -u
export PYTHONDONTWRITEBYTECODE=1
python -B - <<'PY'
import contextlib,hashlib,io,json,pathlib,re,runpy,subprocess
root=pathlib.Path('/data1/home/sunyiq/zhenjiang_training_covariance_failure_006_20261016_001')
job=str(json.loads((root/'records/scheduler_jobs.json').read_bytes())['covariance_diagnostic']);assert job=='244010'
capture=io.StringIO()
with contextlib.redirect_stdout(capture):runpy.run_path(str(root/'hpc/probe_covariance_diagnostic.py'),run_name='__main__')
doc=json.loads(capture.getvalue());assert doc['job_id']==job and doc['source_failed_job']=='243692'
control='/usr/local/globle/softs/slurm/19.05.4.1/bin/scontrol'
assert hashlib.sha256(pathlib.Path(control).read_bytes()).hexdigest()=='61ec1c503aa4481bbe6c12090a0c001f2b4efe26f2b638a8ddc797bf8984c51f'
commands=[[control,'show','job','-o',job],[control,'show','partition','-o'],[control,'show','node','-o'],
 ['sinfo','-h','-N','-o','%P|%N|%T|%G|%C'],
 ['sacctmgr','-n','-P','show','association','where','user=sunyiq','format=Cluster,Account,User,Partition,QOS,DefaultQOS']]
queries=[]
for c in commands:
 try:
  p=subprocess.run(c,capture_output=True,text=True,timeout=30)
  queries.append({'command':c,'returncode':p.returncode,'stdout':p.stdout,'stderr':p.stderr})
 except Exception as error:queries.append({'command':c,'error_type':type(error).__name__,'error':str(error)})
p=subprocess.run([control,'show','config'],capture_output=True,text=True,timeout=30)
keys=['SchedulerType','SchedulerParameters','SelectType','SelectTypeParameters','FastSchedule','GresTypes','PriorityType']
selected={k:v.strip() for line in p.stdout.splitlines() for k,separator,v in [line.partition('=')] if separator and k.strip() in keys}
doc['actual_current_scheduler_admission']={'queries':queries,'scheduler_configuration':{'returncode':p.returncode,'selected_nonsecret_fields':selected,'stderr':p.stderr},
 'same_job_window_already_adjusted':True,'new_jobs_submitted':0,'other_jobs_modified':False,
 'scheduler_mutated':False,'gpu_models_must_still_match_frozen_source':True,'alternate_partition_not_yet_admitted':True}
print(json.dumps(doc,sort_keys=True),flush=True)
PY
