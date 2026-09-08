#!/bin/bash
# Read-only diagnosis of failed receiver basins; never executes the model.
set -eo pipefail
TASK_ROOT=/data1/home/sunyiq/id29_xinanjiang_transfer_20260907_v01
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -B - <<'PY'
import hashlib,json,pathlib
root=pathlib.Path('/data1/home/sunyiq/id29_xinanjiang_transfer_20260907_v01')
stage=root/'receiver/evaluation'
failed=[]
for directory in sorted(stage.iterdir()):
    if not directory.is_dir(): continue
    result=directory/'result.json'
    if not result.exists():
        failed.append({'basin_id':directory.name,'status':'missing_result','files':sorted(p.name for p in directory.iterdir())})
        continue
    value=json.loads(result.read_text())
    if value.get('status')!='success':
        arms=[{'arm':a.get('arm'),'status':a.get('status'),'error':a.get('error')} for a in value.get('arms',[])]
        failed.append({'basin_id':directory.name,'status':value.get('status'),'error':value.get('error'),
                       'traceback':value.get('traceback'),'arms':arms,
                       'files':sorted(p.name for p in directory.iterdir())})
print('FAILED_BASIN_COUNT',len(failed))
print('FAILED_BASINS_JSON',json.dumps(failed,sort_keys=True))
print('SUMMARY_SHA256',hashlib.sha256((root/'receiver/summary.json').read_bytes()).hexdigest())
print('TRANSFER_SHA256',hashlib.sha256((root/'development/frozen_transfer.json').read_bytes()).hexdigest())
print('BUNDLE_MANIFEST_SHA256',hashlib.sha256((root/'bundle/MANIFEST.json').read_bytes()).hexdigest())
print('RECEIVER_JOB_ID',(root/'receiver_job_id.txt').read_text().strip())
print('RECEIVER_APPROVAL_SHA256',hashlib.sha256((root/'approve_receiver.json').read_bytes()).hexdigest())
print('RECEIVER_SUBMISSION_RECEIPT', (root/'receiver_submission_receipt.json').read_text())
PY
sacct -j 223833 --format=JobID,State,ExitCode,Elapsed,AllocCPUS,MaxRSS,NodeList -P
printf 'ERR_LOG_BYTES '; wc -c < "$TASK_ROOT/logs/id29-xaj-receive_223833.err"
printf 'OUT_LOG_TAIL\n'; tail -n 25 "$TASK_ROOT/logs/id29-xaj-receive_223833.out"
