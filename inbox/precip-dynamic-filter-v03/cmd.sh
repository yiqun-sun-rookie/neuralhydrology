#!/usr/bin/env bash
set -eo pipefail
task_run="$HOME/precip_dynamic_eight_basins_20261003/eight_basin_fixed_recipe_v01_20261003_230000_d5028d71"
test -d "$task_run"
task_run=$(readlink -f "$task_run")
case "$task_run" in "$HOME/precip_dynamic_eight_basins_20261003/"*) ;; *) exit 30 ;; esac
task_job=$(sed -n 's/^Submitted batch job \([0-9][0-9]*\)$/\1/p' "$task_run/submission_receipt.txt")
[[ "$task_job" =~ ^[0-9]+$ ]]
date -u '+SNAPSHOT_UTC=%Y-%m-%dT%H:%M:%SZ'
printf 'JOB_ID=%s\n' "$task_job"
sacct -j "$task_job" --noheader --parsable2 --format=JobIDRaw,State,ExitCode,ElapsedRaw,AllocTRES
squeue -j "$task_job" --noheader -o '%i|%T|%M|%L|%R' || true
"/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python" -B - "$task_run" <<'PY'
import sys,json,hashlib
from pathlib import Path
root=Path(sys.argv[1]).resolve()
keys=('success','kind','exit_code','index','error','type','mode','job_id','job_elapsed_seconds','parent_elapsed_seconds','requested_gpu_seconds','tests','seconds','resources','probe_seconds','pytest_summary','score_values_read','score_observations_read','runoff_model_forward_executed','contract_sha256')
files=['runtime/stage_0.json','runtime/stage_1.json','runtime/stage_2.json','runtime/stage_3.json','runtime/stage_4.json','runtime/stage_5.json','runtime/failure.json','runtime/job_complete.json','runtime/budget_runtime.json','runtime/budget_parent_exit.json','runtime/synthetic/technical_gate.json','runtime/synthetic/failure.json','runtime/preflight/preflight_gate.json','runtime/preflight/complete.json','runtime/preflight/failure.json','runtime/probe/probe_gate.json','runtime/probe/failure.json','runtime/probe/child_failure.json','runtime/probe/probe_process.json','runtime/training/complete.json','runtime/training/failure.json','runtime/locked/complete.json','runtime/locked/failure.json','runtime/scoring/complete.json','runtime/scoring/failure.json']
for relative in files:
 p=root/relative
 if p.is_file():
  assert not p.is_symlink() and p.resolve().is_relative_to(root)
  assert p.stat().st_size<=524288
  raw=p.read_bytes();v=json.loads(raw)
  record={k:v[k] for k in keys if k in v}
  if 'numeric_runtime' in v:record['numeric_runtime']={k:v['numeric_runtime'].get(k) for k in ('torch_version','cuda_version','gpu_name','torch_threads','device')}
  print(json.dumps({'file':relative,'sha256':hashlib.sha256(raw).hexdigest(),'bytes':len(raw),'record':record},sort_keys=True))
for p in sorted((root/'runtime/probe').glob('*/resource_measurement.json')):
 raw=p.read_bytes();assert len(raw)<=1048576;v=json.loads(raw)
 print(json.dumps({'file':str(p.relative_to(root)),'sha256':hashlib.sha256(raw).hexdigest(),'record':{k:v.get(k) for k in ('basin','epoch_seconds','replay_seconds_per_day','occupied_probe_seconds','peak_cuda_bytes','peak_system_bytes')}},sort_keys=True))
fitted=list((root/'runtime/training/basins').glob('*/fits/*/seed_*/fit_summary.json'))
locked=list((root/'runtime/training/basins').glob('*/selection_locked.json'))
epoch_files=list((root/'runtime/training/basins').glob('*/fits/*/seed_*/epoch_*.json'))
print(json.dumps({'written_training_epochs':len(epoch_files),'finished_fits':len(fitted),'station_selection_locks':len(locked),'training_directory_exists':(root/'runtime/training').is_dir(),'scoring_directory_exists':(root/'runtime/scoring').is_dir()}))
for p in [root/'logs'/('eight-'+root.joinpath('submission_receipt.txt').read_text().strip().split()[-1]+'.err')]:
 if p.is_file():
  with p.open('rb') as h:h.seek(max(0,p.stat().st_size-4096));raw=h.read(4096)
  print('LOG_TAIL='+json.dumps(raw.decode('utf-8',errors='replace')))
PY

"/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python" -B - "$task_run" <<'TRAINING_METADATA'
import sys,json,hashlib,base64,stat
from pathlib import Path
root=Path(sys.argv[1]).resolve(strict=True)
basins=('01487000','12040500','09312600','08198500','03078000','05362000','08267500','07145700')
methods=('rain','flow','historical')
names=['runtime/stage_3.json','runtime/stage_4.json','runtime/training/complete.json','runtime/locked/complete.json','runtime/locked/global_selection_locked.json','runtime/training/stage_manifest.json']
for basin in basins:
 names.extend(['runtime/training/basins/'+basin+'/selection_locked.json','runtime/training/basins/'+basin+'/input_gate.json'])
 for method in methods:
  for seed in (1001,1002,1003):names.append(f'runtime/training/basins/{basin}/fits/{method}/seed_{seed}/fit_summary.json')
for name in ('runtime/locked/stage_manifest.json',):
 if (root/name).is_file():names.append(name)
assert len(names)==len(set(names))
total=0
records=[]
for name in names:
 p=root/name
 for q in (p,*p.parents):
  if q==root.parent:break
  assert not q.is_symlink()
 assert p.resolve(strict=True).is_relative_to(root) and stat.S_ISREG(p.stat().st_mode)
 before=p.stat()
 assert before.st_size<=1048576
 raw=p.read_bytes()
 after=p.stat()
 assert (before.st_size,before.st_mtime_ns,before.st_ctime_ns,before.st_dev,before.st_ino)==(after.st_size,after.st_mtime_ns,after.st_ctime_ns,after.st_dev,after.st_ino)
 json.loads(raw)
 total+=len(raw)
 assert total<=4194304
 records.append({'file':name,'bytes':len(raw),'sha256':hashlib.sha256(raw).hexdigest(),'base64':base64.b64encode(raw).decode()})
print('EIGHT_TRAINING_METADATA_BEGIN')
print(json.dumps({'files':records,'count':len(records),'raw_bytes':total},sort_keys=True))
print('EIGHT_TRAINING_METADATA_END')
TRAINING_METADATA
