#!/usr/bin/env bash
set -o pipefail
export PYTHONDONTWRITEBYTECODE=1
printf '%s\n' 'channel=kalmannet-daily-perbasin sequence=38 purpose=readonly-alternate-gpu-node-and-isolated-directory-inventory'
date -Is
hostname
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -B - <<'PY'
import json, os, pathlib, subprocess
root = pathlib.Path('/data1/home/sunyiq/kalmannet_daily_camels_per_basin_pilots_20260901')
def query(label,args):
    r=subprocess.run(args,capture_output=True,text=True,timeout=40,check=False)
    print(json.dumps(dict(query=label,exit_code=r.returncode,stdout=r.stdout,stderr=r.stderr)),flush=True)
    return r
results=[]
results.append(query('GPU_NODE_OCCUPANCY',['sinfo','-N','-p','hgpu8,hgpu4,hgpu2p,hgpu2','-o','%N|%P|%T|%G|%C|%m|%E']))
for partition in ('hgpu8','hgpu4','hgpu2p','hgpu2'):
    results.append(query('GPU_PARTITION_'+partition,['scontrol','show','partition',partition]))
for node in ('ngu201','ngu203'):
    results.append(query('A800_CANDIDATE_'+node,['scontrol','show','node',node]))
results.append(query('CURRENT_USER_JOBS_ONLY',['squeue','-h','-u',str(os.getuid()),'-o','%i|%200j|%T|%P|%N|%R']))
results.append(query('GPU_RESERVATIONS',['scontrol','-o','show','reservation']))
cfg=subprocess.run(['scontrol','show','config'],capture_output=True,text=True,timeout=40,check=False)
print(json.dumps(dict(query='SCHEDULER_PREEMPTION_AND_PRIVACY',exit_code=cfg.returncode,fields=[x.strip() for x in cfg.stdout.splitlines() if any(x.strip().startswith(k) for k in ('PreemptMode','PreemptType','PrivateData','SelectType'))],stderr=cfg.stderr)),flush=True)
results.append(cfg)
query('PROJECT_STORAGE',['df','-Pk',str(root)])
assert root.is_dir() and not root.is_symlink() and root.resolve()==root, 'project root changed'
for relative in ('deployments/DAILY_CAMELS_KNET_PER_BASIN_V2_BUNDLE_DEPLOY1_SEQ34/source','runtime_gate_audits','runs','status','status/locks','node_recovery_20260907'):
    p=root/relative
    assert not p.is_symlink() and p.resolve()==p, 'linked or escaped project path'
    info=dict(relative_path=relative,exists=p.exists(),is_directory=p.is_dir())
    if p.is_dir() and relative!='deployments/DAILY_CAMELS_KNET_PER_BASIN_V2_BUNDLE_DEPLOY1_SEQ34/source':
        children=list(p.iterdir())
        assert len(children)<=250, 'bounded project metadata inventory exceeded'
        info['direct_children']=[dict(name=q.name,is_directory=q.is_dir(),is_link=q.is_symlink(),size_bytes=q.lstat().st_size) for q in sorted(children)]
    print(json.dumps(info),flush=True)
print('training_submissions=0 runtime_submissions=0 task_file_writes=0 signals_sent=0 formal_evaluation_access=0')
assert all(x.returncode==0 for x in results), 'one or more required read-only queries failed'
print('READONLY_ALTERNATE_NODE_AND_DIRECTORY_INVENTORY_COMPLETE')
PY
