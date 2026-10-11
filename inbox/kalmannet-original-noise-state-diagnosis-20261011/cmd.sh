#!/bin/bash
set -eo pipefail
/data1/home/sunyiq/kalmannet_original_noise_multiday_evaluation_20261008_recovery3/runtime/venv/bin/python -X utf8 -B - <<'OUTCOME_QUERY'
import json,subprocess
from pathlib import Path
r=Path('/data1/home/sunyiq/kalmannet_original_noise_internal_state_diagnosis_20261011')
value={'files':{},'scientific_submissions':0,'scientific_retries':0}
for path in sorted((r/'submissions').glob('*')):
    value['files'][path.name]=path.read_text(encoding='utf-8')
for label,command in [('queue',['squeue','--user=sunyiq','--name=noise-state-six','--noheader','--format=%i|%j|%t|%C|%R']),('accounting',['sacct','-X','-n','-P','--name=noise-state-six','-S','2026-10-11','-o','JobID,JobName,State,ExitCode,Submit,Start,End,AllocCPUS,WorkDir']),('sbatch_identity',['bash','-lc','type sbatch; command -v sbatch'])]:
    p=subprocess.run(command,capture_output=True,text=True,timeout=45)
    value[label]={'exit_code':p.returncode,'stdout':p.stdout,'stderr':p.stderr}
value['case_files']=[str(p.relative_to(r)) for p in (r/'results/cases').rglob('*') if p.is_file()]
print('SUBMISSION_OUTCOME_JSON='+json.dumps(value),flush=True)
OUTCOME_QUERY
