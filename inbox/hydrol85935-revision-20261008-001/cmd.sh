#!/bin/bash
set -eo pipefail
export PYTHONDONTWRITEBYTECODE=1
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python - <<'CAPACITY'
"""Read-only capacity, QOS and fair-share assessment. No mutation."""
import json, subprocess, datetime
def emit(k, v): print(k + ' ' + json.dumps(v), flush=True)
def q(label, args):
    try:
        r = subprocess.run(args, capture_output=True, text=True, timeout=40)
        emit(label, dict(args=args, returncode=r.returncode, stdout=r.stdout[:60000], stderr=r.stderr[:2000]))
    except Exception as ex:
        emit(label, dict(args=args, error=type(ex).__name__ + ': ' + str(ex)))
emit('CAP_TIME', dict(utc=datetime.datetime.now(datetime.timezone.utc).isoformat()))
q('CAP_NODES', ['sinfo', '-N', '-h', '-p', 'hgpu2p,hgpu2,hgpu4,hgpu8', '-O', 'nodelist:12,partition:10,statelong:12,gres:10,gresused:26,cpusstate:18'])
q('CAP_ACCOUNT_JOBS', ['squeue', '-h', '-r', '-u', 'sunyiq', '-O', 'jobid:16,partition:10,state:10,reason:26,numcpus:6,tres-per-node:14,nodelist:10,timeused:12,starttime:22'])
q('CAP_QOS', ['sacctmgr', '-n', '-P', 'show', 'qos', 'qos_sunyiq'])
q('CAP_QOS_FIELDS', ['sacctmgr', '-n', '-P', 'show', 'qos', 'qos_sunyiq', 'format=Name,Priority,GrpTRES,GrpJobs,MaxTRESPU,MaxJobsPU,MaxSubmitPU,MaxTRESPerUser,MaxTRESPA,MaxJobsPA,MaxWall'])
q('CAP_ASSOC', ['sacctmgr', '-n', '-P', 'show', 'assoc', 'where', 'user=sunyiq', 'format=Account,User,Partition,QOS,GrpTRES,MaxTRES,MaxJobs,MaxSubmit,Fairshare,GrpJobs'])
q('CAP_SSHARE', ['sshare', '-n', '-P', '-a', '-u', 'sunyiq'])
q('CAP_SSHARE_ACCOUNT', ['sshare', '-n', '-P', '-A', 'g_sunyiq'])
q('CAP_SPRIO_WEIGHTS', ['sprio', '-w'])
q('CAP_SPRIO_MAIN', ['sprio', '-h', '-j', '241336'])
q('CAP_START_MAIN', ['squeue', '--start', '-h', '-j', '241336', '-O', 'jobid:16,state:10,starttime:22,reason:26'])
q('CAP_MAIN_JOB', ['scontrol', 'show', 'job', '-o', '241336'])
q('CAP_PARTITIONS', ['scontrol', 'show', 'partition', '-o', 'hgpu2p', 'hgpu2'])
q('CAP_OTHER_PENDING_PRIORITY', ['sprio', '-h', '-u', 'sunyiq', '-o', '%i %Y %A %F %J %P %Q'])
CAPACITY
