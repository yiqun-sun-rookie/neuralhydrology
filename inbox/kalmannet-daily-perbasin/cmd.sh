#!/bin/bash
set -uo pipefail
task_sequence=81
printf 'channel=kalmannet-daily-perbasin sequence=%s purpose=read-only-capacity-and-failed-deployment-proof\n' "$task_sequence"
printf '%s\n' 'CURRENT_SHARED_A800_CAPACITY_BEGIN'
timeout 20s sinfo -N -p hgpu8 -h -O NodeHost,Gres,GresUsed,CPUsState,StateLong
printf 'CURRENT_SHARED_A800_CAPACITY_EXIT=%s\n' "$?"
printf '%s\n' 'CURRENT_PARTITION_BEGIN'
timeout 20s scontrol show partition hgpu8
printf 'CURRENT_PARTITION_EXIT=%s\n' "$?"
for task_node in ngu201 ngu202 ngu203; do
  printf 'NODE_DETAIL_BEGIN %s\n' "$task_node"
  timeout 20s scontrol show node "$task_node"
  printf 'NODE_DETAIL_EXIT=%s\n' "$?"
done
printf '%s\n' 'CURRENT_ALL_GPU_PARTITIONS_BEGIN'
timeout 20s sinfo -N -h -O Partition,NodeHost,Gres,GresUsed,CPUsState,StateLong
printf 'CURRENT_ALL_GPU_PARTITIONS_EXIT=%s\n' "$?"
printf '%s\n' 'CURRENT_OWN_QUEUE_BEGIN'
timeout 20s squeue -r -u sunyiq -h -o '%i|%j|%T|%P|%D|%C|%b|%Z|%R'
printf 'CURRENT_OWN_QUEUE_EXIT=%s\n' "$?"
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -I -B - <<'READ_ONLY_FAILURE_EVIDENCE'
import base64,hashlib,json,pathlib,stat
root=pathlib.Path('/data1/home/sunyiq/kalmannet_daily_camels_per_basin_21_development_20260908')
request=root/'runtime/train_08190500_entryrepair_seq81'
for p in (root,request):
    if p.resolve(strict=True)!=p or any(x.is_symlink() for x in (p,*p.parents)):
        raise ValueError('noncanonical request')
paths=[request/'candidate-files.json',request/'request.json']
evidence=request/'deployment_livecheck_seq80'
if evidence.is_dir() and not evidence.is_symlink():
    paths += sorted(evidence.glob('query-*'))
total=0
for p in paths:
    if not p.is_relative_to(request) or '..' in p.parts:
        raise ValueError('foreign evidence path')
    info=p.lstat()
    if not stat.S_ISREG(info.st_mode) or any(x.is_symlink() for x in (p,*p.parents)):
        raise ValueError('unsafe metadata')
    if info.st_size>131072 or total+info.st_size>300000:
        print('EVIDENCE_OMITTED_SIZE '+str(p));continue
    raw=p.read_bytes()
    after=p.stat()
    if (info.st_size,info.st_mtime_ns)!=(after.st_size,after.st_mtime_ns) or len(raw)!=info.st_size:
        print('EVIDENCE_CHANGED_DURING_READ '+str(p));continue
    total+=len(raw)
    print('FAILED_DEPLOYMENT_FILE='+json.dumps({'path':str(p),'bytes':len(raw),'sha256':hashlib.sha256(raw).hexdigest(),'base64':base64.b64encode(raw).decode()},sort_keys=True))
for name in ('admission.json','execution_ownership.json','submission_seq81.attempt','submission_seq81.stdout','submission_seq81.stderr','submission_seq81.exit','submission_seq81.receipt.json','evidence','precheck_gate'):
    p=request/name
    print('EXECUTION_TARGET_STATE='+json.dumps({'path':str(p),'exists':p.exists(),'is_symlink':p.is_symlink()},sort_keys=True))
print('READ_ONLY_RESOURCE_AUDIT_COMPLETE submissions=0 checkpoints_read=0 scientific_arrays_read=0')
READ_ONLY_FAILURE_EVIDENCE
