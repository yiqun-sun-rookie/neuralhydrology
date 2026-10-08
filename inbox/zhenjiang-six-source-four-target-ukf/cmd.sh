#!/usr/bin/env bash
set -euo pipefail
python3 - <<'PY'
import datetime,json,pathlib,subprocess
root=pathlib.Path('/data1/home/sunyiq/zhenjiang_complete_comparison_20261006_002')
jobs=json.loads((root/'records/scheduler_jobs.json').read_text())
job=str(jobs['legacy_lstm__small'])
report={'checked_at':datetime.datetime.now(datetime.timezone.utc).isoformat(),'job':job,'read_only':True,'commands':[]}
commands=[['scontrol','show','job','-o',job],['sstat','-j',job+'.batch','--format=JobID,AveCPU,MaxRSS','-P'],['ssh','-o','BatchMode=yes','-o','ConnectTimeout=10','ngu011',"date -Is; ps -u sunyiq -o pid,ppid,stat,etimes,time,pcpu,wchan:30,args; nvidia-smi; sleep 15; date -Is; ps -u sunyiq -o pid,ppid,stat,etimes,time,pcpu,wchan:30,args; nvidia-smi"]]
for command in commands:
 try:
  r=subprocess.run(command,capture_output=True,text=True,timeout=50)
  report['commands'].append({'command':command,'returncode':r.returncode,'stdout':r.stdout[-60000:],'stderr':r.stderr[-5000:]})
 except Exception as e:report['commands'].append({'command':command,'error':str(e)})
print(json.dumps(report,ensure_ascii=True))
PY
