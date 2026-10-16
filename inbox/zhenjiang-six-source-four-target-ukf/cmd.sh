#!/usr/bin/env bash
set -eo pipefail
source /data1/home/sunyiq/miniconda3/etc/profile.d/conda.sh
conda activate nh_final
set -u
export PYTHONDONTWRITEBYTECODE=1
python -B - <<'PY'
import contextlib,io,json,pathlib,runpy,subprocess
root=pathlib.Path('/data1/home/sunyiq/zhenjiang_training_covariance_failure_006_20261016_001')
job=str(json.loads((root/'records/scheduler_jobs.json').read_bytes())['covariance_diagnostic'])
assert job=='244010'
captured=io.StringIO()
with contextlib.redirect_stdout(captured):
 runpy.run_path(str(root/'hpc/probe_covariance_diagnostic.py'),run_name='__main__')
doc=json.loads(captured.getvalue())
assert doc['job_id']==job and doc['source_failed_job']=='243692'
commands=[['squeue','-h','-j',job,'-o','%i|%T|%R|%l|%q|%a|%p|%f|%b'],
          ['sinfo','-h','-N','-p','hgpu2p','-o','%N|%t|%G|%C|%m|%f']]
queries=[]
for command in commands:
 p=subprocess.run(command,capture_output=True,text=True,timeout=30)
 queries.append({'command':command,'returncode':p.returncode,'stdout':p.stdout,'stderr':p.stderr})
doc['current_own_job_queue_diagnosis']={'job_id':job,'queries':queries,'scheduler_mutated':False,
 'other_jobs_modified':False,'training_inputs_read':False,'queue_estimates_are_not_actual_start_or_end':True}
print(json.dumps(doc,sort_keys=True),flush=True)
PY
