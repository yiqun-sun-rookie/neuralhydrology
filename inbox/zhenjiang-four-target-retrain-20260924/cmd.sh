#!/bin/bash
set -euo pipefail
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -I -B - <<'FOUR_TARGET_STATUS'

from pathlib import Path
import json,subprocess,hashlib
root=Path('/data1/home/sunyiq/zhenjiang_four_target_retrain_20260924_001')
job='227612'
def small(relative,limit=262144):
    p=root/relative
    if not p.exists(): return None
    if p.is_symlink() or not p.is_file() or p.stat().st_size>limit:
        raise ValueError('status metadata type or size differs: '+relative)
    return json.loads(p.read_bytes())
submission=small('submission/submitted.json',8192)
if (submission is None or submission['job_id']!=job or
    submission['protocol_sha256']!='e1bcbe3aaaae9d427d06588317d402a4c04532811673edad318dffbadf7b90d6' or
    submission['attempt_sha256']!='06254f7226d11e8180972341444a2242eff471a0acfc54ac31384fdc29efc387'):
    raise ValueError('status job differs from registered one-time submission')
commands={}
for name,args in (
    ('squeue',['squeue','-j',job,'-h','-o','%i|%T|%M|%R']),
    ('sacct',['sacct','-j',job,'-n','-P','--format=JobID,State,ExitCode,Elapsed,AllocTRES'])):
    p=subprocess.run(args,capture_output=True,text=True,timeout=15,check=False)
    if len(p.stdout)+len(p.stderr)>16384: raise ValueError('scheduler status exceeds bound')
    commands[name]={'returncode':p.returncode,'stdout':p.stdout,'stderr':p.stderr}
inputs=small('run/input_identity.json')
preflight=small('run/preflight/result.json')
stages=[]
for seed in (17,29,43):
    for stage in ('common_process','rolling_encoder','differentiable_filter'):
        directory=root/'run'/('seed_'+str(seed))/stage
        files=[p for p in directory.glob('epoch_*.json') if p.stem[6:].isdigit()]
        latest=max(files,key=lambda p:int(p.stem[6:])) if files else None
        record=small(latest.relative_to(root).as_posix(),16384) if latest else None
        selection=small((directory/'selection.json').relative_to(root).as_posix(),16384)
        stages.append({'seed':seed,'stage':stage,'epoch_record_count':len(files),
                       'latest_epoch_record':record,'selection':selection})
failure=small('run/failure.json',8192)
complete=small('run/complete.json',16384)
out={'job_id':job,'scheduler':commands,'complete':complete,'failure':failure,
     'stages':stages,'input_summary':None,'preflight_summary':None}
if inputs:
    out['input_summary']={key:inputs[key] for key in ('train_windows','validate_windows','formal_reads','old_model_weight_reads','scale','preparation_seconds')}
    out['input_summary']['year_window_counts']={year: value['accepted_windows'] for year,value in inputs['identity']['years'].items()}
if preflight:
    out['preflight_summary']={key:preflight[key] for key in ('status','estimated_training_seconds','elapsed_seconds','train_windows','validate_windows','scale','preflight_weights_must_not_initialize_training')}
if complete:
    out['training_result']=small('run/result.json')
if failure:
    log=root/'slurm'/('job_'+job+'.log')
    if log.is_file() and not log.is_symlink() and log.stat().st_size<65536:
        out['failure_log']=log.read_text(errors='replace')[-8192:]
print(json.dumps(out,sort_keys=True))

FOUR_TARGET_STATUS
