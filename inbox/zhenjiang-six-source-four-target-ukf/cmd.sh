#!/usr/bin/env bash
set -eo pipefail
source /data1/home/sunyiq/miniconda3/etc/profile.d/conda.sh
conda activate nh_final
set -u
export PYTHONDONTWRITEBYTECODE=1
export CUDA_VISIBLE_DEVICES=""
python -B - <<'WAIT_SQRT_GPU'
import datetime,json,pathlib,subprocess,sys,time
root=pathlib.Path('/data1/home/sunyiq/zhenjiang_sqrt_covariance_repair_20261017_001')
jobs=json.loads((root/'records/scheduler_jobs.json').read_bytes())
assert jobs=={'sqrt_gpu_admission':'244223'}
job=jobs['sqrt_gpu_admission']
samples=[]
deadline=time.monotonic()+900
while True:
    command=['/usr/local/globle/softs/slurm/19.05.4.1/bin/squeue','-h','-j',job,'-o','%i|%T|%Z|%e']
    p=subprocess.run(command,capture_output=True,text=True,timeout=30)
    assert p.returncode==0,{'command':command,'stdout':p.stdout,'stderr':p.stderr}
    rows=[line.split('|') for line in p.stdout.splitlines() if line.strip()]
    assert len(rows)<=1
    if rows:assert rows[0][0]==job and rows[0][2]==str(root)
    samples.append({'at':datetime.datetime.now(datetime.timezone(datetime.timedelta(hours=8))).isoformat(),
                    'queue':p.stdout})
    if not rows or time.monotonic()>=deadline:break
    time.sleep(min(60,max(0,deadline-time.monotonic())))
print(json.dumps({'status':'sqrt_gpu_bounded_terminal_wait_complete','job_id':job,'root':str(root),
                  'samples':samples,'GPU_submissions':0,'formal_epochs_added':0}),flush=True)
subprocess.run([sys.executable,'-B',str(root/'hpc/gpu_workflow.py'),'probe'],cwd=root,check=True)
WAIT_SQRT_GPU
