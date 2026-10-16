#!/usr/bin/env bash
set -eo pipefail
source /data1/home/sunyiq/miniconda3/etc/profile.d/conda.sh
conda activate nh_final
set -u
export PYTHONDONTWRITEBYTECODE=1
python -B - <<'PY'
import contextlib,datetime,io,json,pathlib,runpy,subprocess
root=pathlib.Path('/data1/home/sunyiq/zhenjiang_training_covariance_failure_006_A40_20261016_002')
stream=io.StringIO()
with contextlib.redirect_stdout(stream):
    runpy.run_path(str(root/'hpc/probe_covariance_diagnostic.py'),run_name='__main__')
record=json.loads(stream.getvalue());job=record['job_id']
assert job=='244098' and record['diagnostic_root']==str(root)
base='/usr/local/globle/softs/slurm/19.05.4.1/bin/'
commands=[
 [base+'scontrol','show','job','-o',job],
 [base+'sinfo','-N','-p','hgpu4','-o','%N|%t|%C|%G|%m|%e|%f'],
 [base+'scontrol','show','node','-o','ngu[101-104]'],
 [base+'squeue','-h','-p','hgpu4','-o','%i|%T|%N|%C|%b|%S|%e|%l|%r'],
]
record['current_A40_admission_queries']=[]
for command in commands:
    p=subprocess.run(command,capture_output=True,text=True,timeout=30)
    record['current_A40_admission_queries'].append(dict(command=command,returncode=p.returncode,stdout=p.stdout,stderr=p.stderr))
record['current_job_log_tails']={}
for path in sorted((root/'logs').glob('*_'+job+'.out')):
    with path.open('rb') as f:
        f.seek(max(0,path.stat().st_size-16000));tail=f.read().decode(errors='replace')
    record['current_job_log_tails'][path.name]={'bytes':path.stat().st_size,'tail':tail}
record['admission_observed_at_beijing']=datetime.datetime.now(datetime.timezone(datetime.timedelta(hours=8))).isoformat()
print(json.dumps(record,sort_keys=True),flush=True)
PY
