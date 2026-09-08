#!/bin/bash
set -eo pipefail
printf '%s\n' 'channel=kalmannet-daily-perbasin sequence=79 purpose=read-only-job224117-terminal-evidence-supplement'
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -I -B - <<'KNET_FAILED_JOB_METADATA_ONLY'
import base64,hashlib,json,os,pathlib,stat
root=pathlib.Path('/data1/home/sunyiq/kalmannet_daily_camels_per_basin_21_development_20260908')
request=root/'runtime/train_08190500_seq77'
run=root/'runs/DAILY_CAMELS_KNET_PER_BASIN_21_DEVELOPMENT_V2_20260908_BASIN_08190500_A800_TRAIN1_SEQ77'
def directory(path):
    for parent in (path,*path.parents):
        info=parent.lstat()
        if not stat.S_ISDIR(info.st_mode) or stat.S_ISLNK(info.st_mode):
            raise ValueError('unsafe directory')
    if path.resolve(strict=True)!=path: raise ValueError('noncanonical directory')
directory(request);directory(run)
total=0
for path in (request/'slurm-224117.stdout',request/'submission_livecheck_seq77/raw-evidence.json'):
    directory(path.parent)
    info=path.lstat()
    if not stat.S_ISREG(info.st_mode) or stat.S_ISLNK(info.st_mode) or info.st_size>300000:
        raise ValueError('unsafe or excessive metadata')
    with path.open('rb') as stream:
        before=os.fstat(stream.fileno());raw=stream.read(300001);after=os.fstat(stream.fileno())
    if (before.st_size,before.st_mtime_ns)!=(after.st_size,after.st_mtime_ns) or len(raw)!=after.st_size:
        raise ValueError('metadata changed while reading')
    total+=len(raw)
    if len(raw)>300000 or total>400000: raise ValueError('metadata budget exceeded')
    print(f'METADATA_FILE bytes={len(raw)} sha256_and_path={hashlib.sha256(raw).hexdigest()}  {path}',flush=True)
    print('METADATA_BASE64_BEGIN '+str(path),flush=True)
    print(base64.b64encode(raw).decode('ascii'),flush=True)
    print('METADATA_BASE64_END '+str(path),flush=True)
entries=[]
for item in sorted(run.iterdir()):
    info=item.lstat()
    entries.append({'name':item.name,'type':'file' if stat.S_ISREG(info.st_mode) else 'directory' if stat.S_ISDIR(info.st_mode) else 'other','bytes':info.st_size})
print(json.dumps({'schema_version':'daily_camels_readonly_run_entry_inventory_v1','path':str(run),'entries':entries,'contents_read':False},sort_keys=True),flush=True)
print(f'READ_ONLY_SUPPLEMENT_COMPLETE metadata_bytes={total} submissions=0 checkpoints_read=0 scientific_arrays_read=0',flush=True)
KNET_FAILED_JOB_METADATA_ONLY
