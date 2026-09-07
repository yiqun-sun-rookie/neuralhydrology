#!/usr/bin/env bash
set -eo pipefail
export PYTHONDONTWRITEBYTECODE=1 PYTHONOPTIMIZE=0
printf '%s\n' 'channel=kalmannet-daily-perbasin sequence=48 purpose=read-only-GPU-allocation-and-isolation'
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -B - <<'PY_READONLY'
import datetime, hashlib, json, os, pathlib, re, shutil, socket, subprocess
def query(label,args):
    try:
        r=subprocess.run(args,stdout=subprocess.PIPE,stderr=subprocess.PIPE,timeout=40)
        if len(r.stdout)>262144 or len(r.stderr)>32768: raise RuntimeError('query exceeds bounded output')
        out={'stage':label,'argv':args,'returncode':r.returncode,'stdout':r.stdout.decode('utf-8'),'stderr':r.stderr.decode('utf-8')}
    except Exception as exc:
        out={'stage':label,'argv':args,'query_error_type':type(exc).__name__,'query_error':str(exc)}
    return out
print(json.dumps({'stage':'SNAPSHOT_START','observed_at_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'host':socket.gethostname(),'request_sequence':48,'purpose':'read-only detailed GPU allocation and scheduler device isolation; no compute submission'}),flush=True)
items=[]
def emit(item):
    items.append(item);print(json.dumps(item,sort_keys=True),flush=True);return item
for node in ('ngu201','ngu202','ngu203'):
    emit(query('DETAILED_NODE_'+node,['scontrol','-d','show','node',node]))
emit(query('GPU_PARTITIONS',['sinfo','-N','-h','-p','hgpu8,hgpu4,hgpu2,hgpu2p','-o','%N|%P|%T|%G|%C']))
emit(query('HARDWARE_MATCHED_PARTITION',['scontrol','show','partition','hgpu8']))
emit(query('CURRENT_RESERVATIONS',['scontrol','-o','show','reservation']))
emit(query('OWN_QUEUE_PRIVATE_DATA_LIMIT_APPLIES',['squeue','-h','-u',str(os.getuid()),'-o','%i|%200j|%T|%N|%C|%b']))
cfg=query('SCHEDULER_CONFIG_SAFE_FIELDS',['scontrol','show','config'])
raw_cfg=cfg.pop('stdout','')
fields={k.strip():v.strip() for line in raw_cfg.splitlines() if '=' in line for k,v in [line.split('=',1)]}
keep=('SLURM_VERSION','SLURM_CONF','SelectType','SelectTypeParameters','TaskPlugin','TaskPluginParam','ProctrackType','GresTypes','AccountingStorageTRES','JobAcctGatherType','JobAcctGatherParams','SchedulerType','SchedulerParameters','PreemptType','PreemptMode','PrivateData','Prolog','Epilog','TaskProlog','TaskEpilog','JobSubmitPlugins','PlugStackConfig')
cfg['fields']={k:fields.get(k) for k in keep}
cfg['raw_config_stdout_sha256']=hashlib.sha256(raw_cfg.encode()).hexdigest()
emit(cfg)
commands={name:shutil.which(name) for name in ('scontrol','sbatch','srun','nvidia-smi')}
emit({'stage':'COMMAND_LOCATIONS_NOT_EXECUTED','commands':commands})
conf_paths=[]
for value in (os.environ.get('SLURM_CONF'),fields.get('SLURM_CONF')):
    if value and value.startswith('/'):conf_paths.append(pathlib.Path(value))
if commands['scontrol']:
    binary=pathlib.Path(commands['scontrol'])
    conf_paths.extend([binary.parent.parent/'etc/slurm.conf',binary.resolve().parent.parent/'etc/slurm.conf'])
seen=set()
allowed_keys={'cgroup.conf':{'CgroupAutomount','CgroupMountpoint','CgroupPlugin','ConstrainDevices','ConstrainCores','ConstrainRAMSpace','ConstrainSwapSpace','AllowedRAMSpace','AllowedSwapSpace','MaxRAMPercent','MaxSwapPercent','TaskAffinity'},'gres.conf':{'NodeName','Name','Type','Count','File','Cores','CPUs','Flags','AutoDetect','Links'}}
for conf in conf_paths:
    if str(conf) in seen:continue
    seen.add(str(conf))
    emit({'stage':'CONFIG_LOCATION','path':str(conf),'exists':conf.exists(),'is_symlink':conf.is_symlink(),'exists_does_not_prove_compute_node_configuration':True})
    for member,keys in allowed_keys.items():
        p=conf.parent/member
        if str(p) in seen:continue
        seen.add(str(p))
        info={'stage':'LOGIN_VISIBLE_RESOURCE_CONFIG','kind':member,'path':str(p),'exists':p.exists(),'is_symlink':p.is_symlink(),'scope_caveat':'Login-visible file is not proof of runtime device enforcement on a compute node'}
        try:
            if p.is_file():
                st=p.stat();info.update(bytes=st.st_size,mtime_ns=st.st_mtime_ns,resolved_path=str(p.resolve()))
                if st.st_size>65536:info['not_read']='size exceeds diagnostic bound'
                else:
                    data=p.read_bytes();info['sha256']=hashlib.sha256(data).hexdigest()
                    lines=[]
                    for line in data.decode('utf-8').splitlines():
                        active=line.split('#',1)[0].strip()
                        tokens={key:value for token in active.split() if '=' in token for key,value in [token.split('=',1)] if key.lower() in {k.lower() for k in keys}}
                        if tokens:lines.append(tokens)
                    info['resource_fields']=lines
        except Exception as exc:
            info.update(read_error_type=type(exc).__name__,read_error=str(exc))
        emit(info)
probe_root=pathlib.Path('/data1/home/sunyiq/kalmannet_daily_camels_per_basin_pilots_20260901/node_recovery_20260907')
emit({'stage':'RECOVERY_STILL_UNSTARTED_PATH_CHECK','paths':[{'path':str(p),'exists':p.exists(),'is_symlink':p.is_symlink()} for p in (probe_root/'historyfix1_runtime_recovery1_seq46',probe_root/'historyfix1_runtime_recovery_once.json')]})
print(json.dumps({'status':'GPU_ALLOCATION_READ_ONLY_SNAPSHOT_NOT_TRAINING_QUALIFICATION','observed_at_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'request_sequence':48,'new_jobs_submitted':0,'remote_task_files_written':0,'nvidia_smi_on_compute_node_executed':False,'idle_gpu_process_and_memory_not_yet_measured':True,'scientific_training_updates':0,'formal_evaluation_accesses':0,'checkpoint_downloads':0,'query_failures':[i['stage'] for i in items if i.get('returncode',0)!=0 or 'query_error' in i]},sort_keys=True),flush=True)
PY_READONLY
