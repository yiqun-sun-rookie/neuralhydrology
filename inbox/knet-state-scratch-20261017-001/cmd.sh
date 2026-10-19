#!/bin/bash
set -eo pipefail
cd /data1/home/sunyiq/knet_camels_hpc_20261012_001/attempts/state_channel_scratch_20261017_001
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -u -B -c '"""Small read-only live-status query, separate from large artifact collection."""
import sys,json,datetime,subprocess,re,time,socket,hashlib
from pathlib import Path
import safe_io as s
base=Path(sys.argv[1]);job=sys.argv[2];token=sys.argv[3]
assert job.isdigit() and base.name=='"'"'state_channel_scratch_20261017_001'"'"'
identity=json.loads(s.read_checked(base/'"'"'submission.json'"'"'));assert identity['"'"'job_id'"'"']==job
def command(args):
    try:
        p=subprocess.run(args,capture_output=True,text=True,timeout=20)
        return dict(returncode=p.returncode,stdout=p.stdout,stderr=p.stderr)
    except subprocess.TimeoutExpired:
        return dict(returncode=124,stdout='"'"''"'"',stderr='"'"'read-only scheduler query timed out'"'"')
def load(path):return json.loads(s.read_checked(path)) if path.is_file() else None
def result_summary(path):
    if not path.is_file():return None
    raw=s.read_checked(path);result=json.loads(raw)
    return dict(status=result.get('"'"'status'"'"'),total_optimizer_calls=result.get('"'"'total_optimizer_calls'"'"'),
        final_network_equals_initial=result.get('"'"'final_network_equals_initial'"'"'),optimizer_states_empty=result.get('"'"'optimizer_states_empty'"'"'),
        counts=result.get('"'"'counts'"'"'),arms={k:dict(optimizer_calls=v['"'"'optimizer_calls'"'"'],effective_nonzero_steps=v['"'"'effective_nonzero_steps'"'"'],last_step=None if v.get('"'"'last'"'"') is None else v['"'"'last'"'"']['"'"'step'"'"']) for k,v in result.get('"'"'arms'"'"',{}).items()},
        bytes=len(raw),sha256=hashlib.sha256(raw).hexdigest())
def tail(path):
    s.checked_path(path,False)
    if not path.is_file():return dict(exists=False,events=[],tail=[])
    with path.open('"'"'rb'"'"') as f:
        f.seek(max(0,path.stat().st_size-131072));raw=f.read()
    lines=raw.decode('"'"'utf-8'"'"',errors='"'"'replace'"'"').splitlines();events=[]
    for line in lines:
        try:item=json.loads(line)
        except ValueError:continue
        if isinstance(item,dict) and '"'"'event'"'"' in item:events.append(item)
    resources=[x for x in events if x['"'"'event'"'"']=='"'"'resource_sample'"'"']
    return dict(exists=True,bytes=path.stat().st_size,mtime_age_seconds=max(0,time.time()-path.stat().st_mtime),events=events[-8:],resource_sample=resources[-1] if resources else None,tail=lines[-8:])
queue=command(['"'"'squeue'"'"','"'"'-j'"'"',job,'"'"'-h'"'"','"'"'-o'"'"','"'"'%i|%j|%T|%M|%R'"'"'])
accounting=command(['"'"'sacct'"'"','"'"'-j'"'"',job,'"'"'--noheader'"'"','"'"'--parsable2'"'"','"'"'--format=JobID,JobName,State,ExitCode,Elapsed,AllocCPUS,Partition,NodeList,Start,End'"'"'])
terminal_states={'"'"'COMPLETED'"'"','"'"'FAILED'"'"','"'"'CANCELLED'"'"','"'"'TIMEOUT'"'"','"'"'NODE_FAIL'"'"','"'"'OUT_OF_MEMORY'"'"','"'"'PREEMPTED'"'"','"'"'BOOT_FAIL'"'"','"'"'DEADLINE'"'"','"'"'REVOKED'"'"'}
def includes(identifier,index):
    if identifier==job+'"'"'_'"'"'+str(index):return True
    if not identifier.startswith(job+'"'"'_['"'"') or not identifier.endswith('"'"']'"'"'):return False
    for part in identifier[len(job)+2:-1].split('"'"'%'"'"')[0].split('"'"','"'"'):
        if '"'"'-'"'"' in part:
            a,b=map(int,part.split('"'"'-'"'"'))
            if a<=index<=b:return True
        elif part.isdigit() and int(part)==index:return True
    return False
rows=[x.split('"'"'|'"'"') for x in accounting['"'"'stdout'"'"'].splitlines() if x];elements=[]
for i,basin in enumerate(['"'"'02092500'"'"','"'"'04105700'"'"']):
    folder=base/'"'"'runs'"'"'/basin/'"'"'attempt_001'"'"';exact=job+'"'"'_'"'"'+str(i)
    qrows=[x.split('"'"'|'"'"') for x in queue['"'"'stdout'"'"'].splitlines() if includes(x.split('"'"'|'"'"')[0],i)]
    arows=[x for x in rows if includes(x[0],i)]
    details=command(['"'"'scontrol'"'"','"'"'-o'"'"','"'"'show'"'"','"'"'job'"'"',exact])
    fields=dict(re.findall(r'"'"'(\w+)=([^\s]+)'"'"',details['"'"'stdout'"'"']))
    physical_job=fields.get('"'"'JobId'"'"','"'"''"'"')
    stat=command(['"'"'sstat'"'"','"'"'-j'"'"',physical_job+'"'"'.batch'"'"','"'"'--noheader'"'"','"'"'--parsable2'"'"','"'"'--format=JobID,AveCPU,MaxRSS'"'"']) if physical_job.isdigit() and any(x[2]=='"'"'RUNNING'"'"' for x in qrows) else None
    arm_progress={}
    for arm in ['"'"'original'"'"','"'"'state_constrained'"'"']:
        d=folder/arm
        epochs=sorted(d.glob('"'"'epoch_*.json'"'"')) if d.is_dir() else []
        calls=sorted(d.glob('"'"'optimizer_call_*.json'"'"')) if d.is_dir() else []
        row=load(epochs[-1]) if epochs else None;call=load(calls[-1]) if calls else None
        arm_progress[arm]=dict(step=0 if row is None else row['"'"'step'"'"'],optimizer_calls=0 if call is None else call['"'"'optimizer_calls'"'"'],effective_nonzero_steps=0 if row is None else row['"'"'effective_nonzero_steps'"'"'],parameter_changed=None if row is None else row['"'"'parameter_changed'"'"'],inflight_proposal=bool(call and (row is None or call['"'"'step'"'"']>row['"'"'step'"'"'])))
    elements.append(dict(index=i,basin=basin,queue=qrows,accounting=arows,per_arm_progress=arm_progress,
        terminal=any(x[2].split()[0].rstrip('"'"'+'"'"') in terminal_states for x in arows),
        scheduler=details,scheduler_fields=fields,resource_usage=stat,
        controller=load(folder/'"'"'controller_started.json'"'"'),scientific=load(folder/'"'"'scientific_started.json'"'"'),receipt=load(folder/'"'"'receipt.json'"'"'),scientific_result=result_summary(folder/'"'"'result.json'"'"'),
        stdout=tail(base/'"'"'logs'"'"'/('"'"'diagnostic-'"'"'+exact+'"'"'.out'"'"')),stderr=tail(base/'"'"'logs'"'"'/('"'"'diagnostic-'"'"'+exact+'"'"'.err'"'"'))))
print('"'"'JOB_STATUS_JSON='"'"'+json.dumps(dict(schema='"'"'strict_monitor_v1'"'"',monitor_round_id=token,job_id=job,identity=identity,
    queried_utc=datetime.datetime.now(datetime.timezone.utc).isoformat(),query_host=socket.gethostname(),
    queue_returncode=queue['"'"'returncode'"'"'],queue=queue['"'"'stdout'"'"'].splitlines(),queue_stderr=queue['"'"'stderr'"'"'],
    accounting_returncode=accounting['"'"'returncode'"'"'],accounting=accounting['"'"'stdout'"'"'].splitlines(),
    all_array_elements_terminal=all(x['"'"'terminal'"'"'] for x in elements),elements=elements)),flush=True)
' /data1/home/sunyiq/knet_camels_hpc_20261012_001/attempts/state_channel_scratch_20261017_001 244228 84752a25f8c6460c99016d8bcc31ed98
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -u -B -c 'import subprocess,sys,json,datetime
root=sys.argv[1].rstrip('"'"'/'"'"')
q=subprocess.run(['"'"'squeue'"'"','"'"'-h'"'"','"'"'-r'"'"','"'"'-u'"'"','"'"'sunyiq'"'"','"'"'-n'"'"','"'"'knet_scratch_pair'"'"','"'"'-o'"'"','"'"'%i|%T|%N|%j'"'"'],capture_output=True,text=True,timeout=30)
matched=[];errors=[];examined=0
for line in q.stdout.splitlines():
 p=line.split('"'"'|'"'"')
 if len(p)<4:continue
 examined+=1
 c=subprocess.run(['"'"'scontrol'"'"','"'"'show'"'"','"'"'job'"'"',p[0]],capture_output=True,text=True,timeout=30)
 if c.returncode:errors.append({'"'"'job_id'"'"':p[0],'"'"'returncode'"'"':c.returncode});continue
 fields={part.split('"'"'='"'"',1)[0]:part.split('"'"'='"'"',1)[1] for part in c.stdout.split() if '"'"'='"'"' in part}
 if fields.get('"'"'Command'"'"','"'"''"'"').startswith(root+'"'"'/'"'"'):
  matched.append({'"'"'job_id'"'"':p[0],'"'"'state'"'"':p[1],'"'"'node'"'"':p[2],'"'"'job_name'"'"':p[3],'"'"'command'"'"':fields.get('"'"'Command'"'"'),'"'"'workdir'"'"':fields.get('"'"'WorkDir'"'"')})
print('"'"'KNET_ROOT_JOB_PRESENCE_JSON='"'"'+json.dumps({'"'"'queried_utc'"'"':datetime.datetime.now(datetime.timezone.utc).isoformat(),'"'"'scope_root'"'"':root,'"'"'scope_job_name'"'"':'"'"'knet_scratch_pair'"'"','"'"'squeue_returncode'"'"':q.returncode,'"'"'squeue_error'"'"':q.stderr[-300:],'"'"'matching_name_jobs_examined'"'"':examined,'"'"'control_read_errors'"'"':errors,'"'"'probe_success'"'"':q.returncode==0 and not errors,'"'"'matched_live_jobs'"'"':matched}),flush=True)
' /data1/home/sunyiq/knet_camels_hpc_20261012_001/attempts/state_channel_scratch_20261017_001
