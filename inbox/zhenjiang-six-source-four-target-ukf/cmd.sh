#!/usr/bin/env bash
set -euo pipefail
cd /data1/home/sunyiq/zhenjiang_complete_comparison_20261006_001
python3 - <<'PY'
import json,pathlib,re,subprocess
root=pathlib.Path.cwd()
record=root/'records/scheduler_jobs.json'
jobs=list(json.loads(record.read_text()).values()) if record.exists() else []
print(json.dumps({'own_jobs':jobs,'receipts':len(jobs)}))
if jobs:
    for command in [['squeue','-h','-j',','.join(jobs),'-o','%i|%j|%T|%R'],
                    ['sacct','-n','-X','-j',','.join(jobs),'--format=JobID,JobName,State,ExitCode','-P']]:
        r=subprocess.run(command,capture_output=True,text=True)
        print(r.stdout)
for p in sorted((root/'logs').glob('*.out')):
    raw=p.read_text(errors='replace'); print('LOG',p.name); print(raw[-14000:])
for p in sorted((root/'records').glob('*/progress.json')):
    print('PROGRESS',p.relative_to(root).as_posix(),p.read_text())
steps=sorted((root/'runs').glob('*/first_optimizer_step.json'))
print(json.dumps({'runs_with_real_optimizer_step':len(steps),'evaluation_values_read':False}))
for p in steps[:12]: print('FIRST_STEP',p.parent.name,p.read_text())
done=root/'records/data_preparation_complete.json'
if done.exists():
    report=json.loads(done.read_text()); print(json.dumps({'data_status':report['status'],
        'source_files':report['source_files'],'fresh_tide_fits':report['fresh_tide_fits'],
        'eligible_windows':{k:v['eligible_windows'] for k,v in report['reports'].items()}}))
PY
