#!/bin/bash
set -eo pipefail
/data1/home/sunyiq/kalmannet_original_noise_multiday_evaluation_20261008_recovery3/runtime/venv/bin/python -X utf8 -B - <<'CLOSED_SAVED_CHECK_OPERATION'
import hashlib,importlib.util,json,sys
from pathlib import Path
p=Path('/data1/home/sunyiq/kalmannet_original_noise_internal_state_diagnosis_20261011_recovery1/verification/v3/remote_saved_review.py')
assert hashlib.sha256(p.read_bytes()).hexdigest()=='c307b44ddc06d674a4359bac1822dd42ba75cedce099a86ff62f6ffe89b91e82'
spec=importlib.util.spec_from_file_location('preserved_closed_job_helper',p)
h=importlib.util.module_from_spec(spec);spec.loader.exec_module(h)
h.BOUND=h.Bound(whole=False)
assert h.read(h.FOLDER/'submission.json')['job_id']=='240096'
queue=h.command(['squeue','--user=sunyiq','--noheader','--format=%i|%j|%t'])
queue=[x for x in queue.splitlines() if x.split('|')[0].strip()=='240096']
account=h.command(['sacct','-j','240096','--allocations','--noheader','--parsable2','--format=JobIDRaw,State,ExitCode,ElapsedRaw,AllocCPUS,ReqCPUS,NNodes,Timelimit,NodeList'])
rows=[x.rstrip('|').split('|') for x in account.splitlines() if x.split('|')[0].strip()=='240096']
row=rows[0] if len(rows)==1 else None
terminal=bool(not queue and row and row[1].split()[0] in h.TERMINAL)
assert terminal, 'Closed-artifact read prohibited until exact scheduler terminal identity and absent queue'
print('REMOTE_JSON='+json.dumps(h.seal()),flush=True)
CLOSED_SAVED_CHECK_OPERATION
