#!/usr/bin/env bash
set -euo pipefail
python3 -B - <<'PY'
import datetime,json,pathlib,subprocess
root=pathlib.Path('/data1/home/sunyiq/zhenjiang_validation_joseph_compensation_20261015_001')
source=pathlib.Path('/data1/home/sunyiq/zhenjiang_complete_comparison_20261015_recovery_004')
def query(command):
    p=subprocess.run(command,capture_output=True,text=True,timeout=30)
    assert p.returncode==0
    return {'command':command,'returncode':p.returncode,'stdout':p.stdout,'stderr':p.stderr}
queue=query(['squeue','-h','-u','sunyiq','-o','%i|%j|%T|%Z'])
matches=[line.split('|') for line in queue['stdout'].splitlines()
         if '|zj_gru_val_joseph_diag_' in line or line.endswith('|'+str(root)) or line.endswith('|'+str(source))]
record={'status':'joseph_deployment_read_only_reconciliation','checked_at_beijing':datetime.datetime.now(datetime.timezone(datetime.timedelta(hours=8))).isoformat(),
    'diagnostic_root':str(root),'root_exists':root.exists(),
    'submission_attempt_exists':(root/'records/diagnostic_submission_attempt.json').exists(),
    'submission_response_exists':(root/'records/diagnostic_submission_response.json').exists(),
    'scheduler_jobs_exists':(root/'records/scheduler_jobs.json').exists(),'evidence_exists':(root/'evidence').exists(),
    'matching_active_rows':matches,'queue':queue,
    'source_scheduler_jobs':json.loads((source/'records/scheduler_jobs.json').read_bytes()),
    'accounting':query(['sacct','-n','-X','-j','242609,242731','--format=JobID,State,ExitCode,Start,End','-P']),
    'scheduler_mutated':False,'formal_training_restarted':False,'evaluation_values_read':False}
print(json.dumps(record,sort_keys=True))
PY
