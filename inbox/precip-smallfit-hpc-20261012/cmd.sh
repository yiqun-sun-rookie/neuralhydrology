#!/bin/bash
set -eo pipefail
export PYTHONDONTWRITEBYTECODE=1
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -B -c 'import subprocess,json,os
from datetime import datetime,timezone
queries=[['"'"'squeue'"'"','"'"'--start'"'"','"'"'--jobs=242770'"'"'],['"'"'scontrol'"'"','"'"'show'"'"','"'"'job'"'"','"'"'242770'"'"','"'"'--oneliner'"'"'],['"'"'sprio'"'"','"'"'--jobs=242770'"'"','"'"'--long'"'"']]
rows=[]
for args in queries:
    started=datetime.now(timezone.utc).isoformat()
    try:
        result=subprocess.run(args,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=30)
        rows.append({'"'"'args'"'"':args,'"'"'started_utc'"'"':started,'"'"'returncode'"'"':result.returncode,'"'"'text'"'"':result.stdout.decode('"'"'utf-8'"'"','"'"'replace'"'"')})
    except subprocess.TimeoutExpired as exc:
        output=exc.output or b'"'"''"'"'
        rows.append({'"'"'args'"'"':args,'"'"'started_utc'"'"':started,'"'"'error'"'"':'"'"'TimeoutExpired'"'"','"'"'timeout_seconds'"'"':30,'"'"'text'"'"':output.decode('"'"'utf-8'"'"','"'"'replace'"'"') if isinstance(output,bytes) else output})
    except OSError as exc:
        rows.append({'"'"'args'"'"':args,'"'"'started_utc'"'"':started,'"'"'error'"'"':type(exc).__name__,'"'"'message'"'"':str(exc)})
print('"'"'SMALLFIT_QUEUE_ESTIMATE_V01='"'"'+json.dumps({'"'"'job_id'"'"':242770,'"'"'nonce'"'"':'"'"'26ac3faff4e34c7ba4eea6e485377376'"'"','"'"'observed_utc'"'"':datetime.now(timezone.utc).isoformat(),'"'"'timezone_environment'"'"':os.environ.get('"'"'TZ'"'"'),'"'"'scheduler_queries'"'"':rows},sort_keys=True))
'
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -B /data1/home/sunyiq/precip_smallfit_hpc_20261012_v01/20261015T062534Z_26ac3faf_v03/payload/code/src/precip_input_assimilation/hpc/precip_smallfit_return_v01.py --root /data1/home/sunyiq/precip_smallfit_hpc_20261012_v01/20261015T062534Z_26ac3faf_v03 --nonce 26ac3faff4e34c7ba4eea6e485377376
