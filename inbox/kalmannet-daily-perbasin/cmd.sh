#!/bin/bash
set -uo pipefail
task_sequence=82
task_failure=0
printf 'channel=kalmannet-daily-perbasin sequence=%s purpose=readonly-resource-refresh-and-run-absence\n' "$task_sequence"
printf '%s\n' 'CURRENT_SHARED_A800_CAPACITY_BEGIN'
timeout 20s sinfo -N -p hgpu8 -h -O NodeHost,Gres,GresUsed,CPUsState,StateLong
task_rc=$?
printf 'CURRENT_SHARED_A800_CAPACITY_EXIT=%s\n' "$task_rc"
if [ "$task_rc" -ne 0 ]; then task_failure=1; fi
printf '%s\n' 'A800_QUEUE_ESTIMATES_BEGIN'
timeout 20s squeue -p hgpu8 -h -o '%i|%T|%D|%C|%b|%S|%e|%R'
task_rc=$?
printf 'A800_QUEUE_ESTIMATES_EXIT=%s\n' "$task_rc"
if [ "$task_rc" -ne 0 ]; then task_failure=1; fi
printf '%s\n' 'CURRENT_OWN_QUEUE_BEGIN'
timeout 20s squeue -r -u sunyiq -h -o '%i|%j|%T|%P|%D|%C|%b|%Z|%R'
task_rc=$?
printf 'CURRENT_OWN_QUEUE_EXIT=%s\n' "$task_rc"
if [ "$task_rc" -ne 0 ]; then task_failure=1; fi
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -I -B - <<'READ_ONLY_TARGETS'
import json,pathlib
root=pathlib.Path('/data1/home/sunyiq/kalmannet_daily_camels_per_basin_21_development_20260908')
request=root/'runtime/train_08190500_entryrepair_seq81'
run=root/'runs/DAILY_CAMELS_KNET_PER_BASIN_21_DEVELOPMENT_V2_20260908_BASIN_08190500_A800_TRAIN1_SEQ81'
for p in (root,request,run.parent):
    if p.resolve(strict=True)!=p or any(x.is_symlink() for x in (p,*p.parents)):
        raise ValueError('noncanonical metadata parent')
targets=[request/name for name in ('admission.json','execution_ownership.json','submission_seq81.attempt','submission_seq81.stdout','submission_seq81.stderr','submission_seq81.exit','submission_seq81.receipt.json','evidence','precheck_gate')]+[run]
for p in targets:
    print('EXECUTION_TARGET_STATE='+json.dumps({'path':str(p),'exists':p.exists(),'is_symlink':p.is_symlink()},sort_keys=True))
print('READ_ONLY_TARGETS_COMPLETE count='+str(len(targets)))
READ_ONLY_TARGETS
task_rc=$?
printf 'TARGETS_EXIT=%s\n' "$task_rc"
if [ "$task_rc" -ne 0 ]; then task_failure=1; fi
printf 'READ_ONLY_REFRESH_COMPLETE exit=%s submissions=0\n' "$task_failure"
exit "$task_failure"
