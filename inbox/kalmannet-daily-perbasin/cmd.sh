#!/bin/bash
set -uo pipefail
task_sequence=87
task_failure=0
printf 'channel=kalmannet-daily-perbasin sequence=%s purpose=readonly-three-hour-resource-wait-refresh\n' "$task_sequence"
printf '%s\n' 'CURRENT_PARTITION_BEGIN'
timeout 20s scontrol show partition hgpu8
task_rc=$?
printf 'CURRENT_PARTITION_EXIT=%s\n' "$task_rc"
if [ "$task_rc" -ne 0 ]; then task_failure=1; fi
printf '%s\n' 'CURRENT_SHARED_A800_CAPACITY_BEGIN'
timeout 20s sinfo -N -p hgpu8 -h -O NodeHost,Gres,GresUsed,CPUsState,StateLong
task_rc=$?
printf 'CURRENT_SHARED_A800_CAPACITY_EXIT=%s\n' "$task_rc"
if [ "$task_rc" -ne 0 ]; then task_failure=1; fi
printf '%s\n' 'CURRENT_OWN_QUEUE_BEGIN'
timeout 20s squeue -r -u sunyiq -h -o '%i|%j|%T|%P|%D|%C|%b|%Z|%R'
task_rc=$?
printf 'CURRENT_OWN_QUEUE_EXIT=%s\n' "$task_rc"
if [ "$task_rc" -ne 0 ]; then task_failure=1; fi
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -I -B - <<'READ_ONLY_TARGETS'
import json,pathlib
root=pathlib.Path('/data1/home/sunyiq/kalmannet_daily_camels_per_basin_21_development_20260908')
old_request=root/'runtime/train_08190500_entryrepair_seq81'
old_run=root/'runs/DAILY_CAMELS_KNET_PER_BASIN_21_DEVELOPMENT_V2_20260908_BASIN_08190500_A800_TRAIN1_SEQ81'
next_request=root/'runtime/train_08190500_entryrepair_seq89'
next_run=root/'runs/DAILY_CAMELS_KNET_PER_BASIN_21_DEVELOPMENT_V2_20260908_BASIN_08190500_A800_TRAIN1_SEQ89'
for p in (root,old_request,old_run.parent):
    if p.resolve(strict=True)!=p or any(x.is_symlink() for x in (p,*p.parents)):
        raise ValueError('noncanonical metadata parent')
targets=[old_request/name for name in ('admission.json','execution_ownership.json','submission_seq81.attempt','submission_seq81.stdout','submission_seq81.stderr','submission_seq81.exit','submission_seq81.receipt.json','evidence','precheck_gate')]+[old_run,next_request,next_run]
for p in targets:
    print('EXECUTION_TARGET_STATE='+json.dumps({'path':str(p),'exists':p.exists(),'is_symlink':p.is_symlink()},sort_keys=True))
print('READ_ONLY_TARGETS_COMPLETE count='+str(len(targets)))
READ_ONLY_TARGETS
task_rc=$?
printf 'TARGETS_EXIT=%s\n' "$task_rc"
if [ "$task_rc" -ne 0 ]; then task_failure=1; fi
printf 'READ_ONLY_REFRESH_COMPLETE exit=%s submissions=0 checkpoints_read=0 scientific_arrays_read=0\n' "$task_failure"
exit "$task_failure"
