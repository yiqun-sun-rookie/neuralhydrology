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
