#!/bin/bash
set -euo pipefail
root=/data1/home/sunyiq/id25_regional_regionmean_rds04_20261021_001
stage="$root/resource_compatibility_v002"
mkdir -p "$stage"
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python - "$root" <<'PYFIX'
import hashlib,json,re,subprocess,sys
from datetime import datetime,timezone
from pathlib import Path
root=Path(sys.argv[1]); stage=root/'resource_compatibility_v002'
assert str(root)=='/data1/home/sunyiq/id25_regional_regionmean_rds04_20261021_001'
result_path=stage/'clear_exclusivity_attempt.json'
assert not result_path.exists(),'Attempt exists; do not repeat'
def call(args):
    return subprocess.run(args,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=35)
def job():
    r=call(['scontrol','-o','show','job','246090'])
    assert r.returncode==0,r.stdout
    d=dict(re.findall(r'(\S+?)=(.*?)(?= \S+?=|$)',r.stdout.strip()))
    return d,r.stdout
before,raw=job()
assert before['JobId']=='246090' and before['JobName']=='id25_rds04_261021' and before['UserId'].startswith('sunyiq(')
(stage/'job_before.txt').write_text(raw)
manifest=json.loads((root/'source_manifest.json').read_text())
paths=['config.json','source_manifest.json','submissions.tsv','job_id.txt']
for p in (root/'code').rglob('*.py'):
    paths.append(str(p.relative_to(root)))
def hashes():
    return {p:hashlib.sha256((root/p).read_bytes()).hexdigest() for p in paths}
protected=hashes()
if before['JobState']=='PENDING' and before.get('OverSubscribe')=='NO':
    cfg=call(['scontrol','show','config']).stdout
    assert re.search(r'SelectType\s*=\s*select/cons_res',cfg)
    part=call(['scontrol','-o','show','partition','hcpu48y'])
    assert part.returncode==0 and 'OverSubscribe=NO' in part.stdout and 'State=UP' in part.stdout
    command=['scontrol','update','JobId=246090','Partition=hcpu48y','OverSubscribe=YES']
    attempted=call(command)
    (stage/'update_output.txt').write_text(attempted.stdout)
    after,afterraw=job()
    state='NODE_SHARING_ENABLED' if attempted.returncode==0 else 'UPDATE_DENIED_OR_FAILED'
    if attempted.returncode!=0 and after['JobState']=='PENDING' and after['Partition']!=before['Partition']:
        restored=call(['scontrol','update','JobId=246090','Partition='+before['Partition']])
        assert restored.returncode==0,restored.stdout
        after,afterraw=job()
else:
    command=[]; attempted=None; after,afterraw=job(); state='NO_CHANGE_JOB_NO_LONGER_PENDING_OR_ALREADY_SHAREABLE'
(stage/'job_after.txt').write_text(afterraw)
for key in ['JobId','SubmitTime','TimeLimit','NumTasks','CPUs/Task','Command','WorkDir']:
    assert after.get(key)==before.get(key),(key,before.get(key),after.get(key))
assert hashes()==protected,'Protected inputs/code/ledger changed'
result={'state':state,'job_id':'246090','command':command,'command_exit_code':None if attempted is None else attempted.returncode,'command_output':None if attempted is None else attempted.stdout,'before':before,'after':after,'protected_sha256':protected,'new_submissions':0,'cancellations':0,'preflights_repeated':0,'other_jobs_modified':[],'recorded_at':datetime.now(timezone.utc).isoformat()}
result_path.write_text(json.dumps(result,indent=2)+'\n')
print(json.dumps(result))
PYFIX
printf 'GPU_PARTITIONS_CPU_ONLY_CANDIDATES\n'
for part in hgpu2p hgpu2 hgpu4 hgpu8; do timeout 30 scontrol -o show partition "$part" || true; done
printf 'GPU_NODE_CPU_INVENTORY\n'
timeout 30 sinfo -N -p hgpu2p,hgpu2,hgpu4,hgpu8 -o '%N|%P|%t|%C|%m|%E'
timeout 30 scontrol -o show node 'ngu[001-004,009,101-104,201-203]'
printf 'START_AND_NATIVE_JOB\n'
timeout 30 scontrol -o show job 246090
timeout 30 squeue --start -j 246090 -o '%i|%T|%r|%S|%Q|%R' || true
printf 'NO_NEW_SUBMISSION_NO_OTHER_JOB_OPERATION\n'
