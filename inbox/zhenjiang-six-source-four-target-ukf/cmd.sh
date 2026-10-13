#!/usr/bin/env bash
set -eo pipefail
source /data1/home/sunyiq/miniconda3/etc/profile.d/conda.sh
conda activate nh_final
set -u
python -B - <<'PY'
import datetime,json,pathlib,subprocess
root=pathlib.Path('/data1/home/sunyiq/zhenjiang_complete_comparison_20261006_002')
job=str(json.loads((root/'records/scheduler_jobs.json').read_text())['explicit_gru__small'])
bin='/usr/local/globle/softs/slurm/19.05.4.1/bin/'
commands=[[bin+'squeue','--helpformat'],[bin+'squeue','--version'],[bin+'squeue','-h','-j',job,'-o','%i|%T|%Z|%e|%l|%P|%C|%b|%N'],[bin+'scontrol','show','job','-o',job],['ldd',bin+'squeue']]
rows=[]
for command in commands:
 p=subprocess.run(command,capture_output=True,text=True,timeout=30);rows.append({'command':command,'returncode':p.returncode,'stdout':p.stdout,'stderr':p.stderr})
print(json.dumps({'status':'read_only_registered_slurm_queue_interface_probe','checked_at_beijing':datetime.datetime.now(datetime.timezone(datetime.timedelta(hours=8))).isoformat(),'own_reference_job':job,'queries':rows,'scheduler_mutated':False,'evaluation_values_read':False},sort_keys=True))
PY
