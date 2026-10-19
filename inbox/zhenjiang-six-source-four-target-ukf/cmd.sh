#!/usr/bin/env bash
set -eo pipefail
source /data1/home/sunyiq/miniconda3/etc/profile.d/conda.sh
conda activate nh_final
set -u
export CUDA_VISIBLE_DEVICES=""
export PYTHONDONTWRITEBYTECODE=1
export OMP_NUM_THREADS=2
python -B - <<'PRESERVE_003'
import datetime, hashlib, io, json, os, pathlib, subprocess
import torch

HOME_ROOT=pathlib.Path('/data1/home/sunyiq')
DEST=HOME_ROOT/'zhenjiang_fixed200_003_sources_20261019_001'
assert not DEST.exists(), 'preserved archive already exists; reconcile instead of replay'
DEST.mkdir()
ROOTS={
 'explicit_gru__small':HOME_ROOT/'zhenjiang_complete_comparison_20261006_002',
 'legacy_lstm__historical_capacity':HOME_ROOT/'zhenjiang_complete_comparison_20261006_002',
 'legacy_lstm__small':HOME_ROOT/'zhenjiang_complete_comparison_20261008_recovery_002',
 'explicit_gru__historical_capacity':HOME_ROOT/'zhenjiang_complete_comparison_20261017_sqrt_recovery_001'}

def digest(raw): return hashlib.sha256(raw).hexdigest()
def stable(path):
 for attempt in range(3):
  before=path.stat(); raw=path.read_bytes(); after=path.stat()
  if (before.st_size,before.st_mtime_ns)==(after.st_size,after.st_mtime_ns) and len(raw)==after.st_size:return raw
 raise ValueError('concurrent input replacement: '+str(path))
def preserve(path, relative):
 raw=stable(path); target=DEST/relative; target.parent.mkdir(parents=True,exist_ok=True)
 with target.open('xb') as stream:stream.write(raw)
 return raw,{'source':str(path),'preserved':str(target),'bytes':len(raw),'sha256':digest(raw)}
def tensors(value):
 if isinstance(value,torch.Tensor):yield value
 elif isinstance(value,dict):
  for child in value.values():yield from tensors(child)
 elif isinstance(value,(tuple,list)):
  for child in value:yield from tensors(child)

report={'schema':'fixed200-source-preservation-v1','started_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),
 'archive_root':str(DEST),'source_writes':False,'training_performed':False,'evaluation_data_read':False,'cases':{},'errors':[]}
for case,root in ROOTS.items():
 registry=json.loads(stable(root/'configs/registry-v3.json'))
 runs=[r for r in registry['runs'] if r['case']==case and r['type']=='tune_branch' and r['status']!='alias']
 rows=[]
 for run in runs:
  rid=run['exp_id']; folder=root/'runs'/rid; row={'run_id':rid,'files':{},'scientific_source_admitted':False}
  try:
   config_raw,entry=preserve(folder/'config.json',case+'/'+rid+'/config.json');row['files']['config.json']=entry
   raw,entry=preserve(folder/'continuation.pt',case+'/'+rid+'/continuation.pt');row['files']['continuation.pt']=entry
   state=torch.load(io.BytesIO(raw),map_location='cpu',weights_only=True)
   assert state['config_sha256']==digest(config_raw),'configuration binding differs'
   values=state['values'];n=len(values);assert n and len(state['train_metrics'])==n and len(state['shuffle_hashes'])==n
   assert all(torch.isfinite(t).all().item() for t in tensors(state)),'nonfinite tensor'
   best=values.index(min(values))+1;prefix=values[:200];best200=prefix.index(min(prefix))+1
   steps=[float(v['step']) for v in state['optimizer']['state'].values()]
   row.update(completed_epochs=n,best_epoch=best,first200_best_epoch=best200,inline_best_matches_first200=best==best200,
    optimizer_step_min=min(steps),optimizer_step_max=max(steps),completed_batch_count=sum(map(len,state['train_metrics'])),
    all_saved_tensors_finite=True,configuration_binding_verified=True,source_code_hash=json.loads(config_raw)['effective_config']['code_hash'])
   for name in ('epoch_100.pt','epoch_200.pt','best.pt','failure.json','recovery_from_failure.json','first_optimizer_step.json'):
    path=folder/name
    if path.is_file(): _,entry=preserve(path,case+'/'+rid+'/'+name);row['files'][name]=entry
  except Exception as error:
   row['error']=type(error).__name__+': '+str(error);report['errors'].append({'run_id':rid,'error':row['error']})
  rows.append(row)
 for sub in ('src','scripts','configs'):
  for path in (root/sub).glob('*.py' if sub!='configs' else '*-v3.json'):
   _,entry=preserve(path,case+'/runtime_source/'+sub+'/'+path.name)
 for name in ('scheduler_jobs.json','authorization.json','data_preparation_complete.json'):
  path=root/'records'/name
  if path.exists():preserve(path,case+'/records/'+name)
 report['cases'][case]=rows

# Search only known Zhenjiang comparison/recovery/archive roots, excluding data.
search_roots=sorted(p for p in HOME_ROOT.glob('zhenjiang_complete_comparison*') if p.is_dir() and 'fixed200_20261019_003' not in p.name)
targets={r['run_id'] for rows in report['cases'].values() for r in rows}
found=[]
for root in search_roots:
 for path,dirs,files in os.walk(root):
  dirs[:]=[d for d in dirs if d not in ('data','prepared','logs','.git','__pycache__','vendor','third_party')]
  base=pathlib.Path(path)
  for name in files:
   if name.endswith(('.pt','.pth','.tar.gz','.zip')) and (name in ('continuation.pt','best.pt','epoch_200.pt') or any(k in name.lower() for k in ('best','backup','checkpoint','archive'))):
    if any(rid in str(base) for rid in targets) or name.endswith(('.tar.gz','.zip')):
     st=(base/name).stat();found.append({'path':str(base/name),'bytes':st.st_size,'mtime_ns':st.st_mtime_ns})
report['bounded_archive_search']={'roots':list(map(str,search_roots)),'candidates':found}
queries=[]
for command in (['squeue','-h','-u','sunyiq','-o','%i|%j|%T|%R|%M|%N'],['sacct','-n','-X','-j','236706,236707,237928,244445','--format=JobID,State,ExitCode,Elapsed,NodeList','-P']):
 result=subprocess.run(command,capture_output=True,text=True,timeout=30);queries.append({'command':command,'returncode':result.returncode,'stdout':result.stdout,'stderr':result.stderr})
report['scheduler_queries']=queries
report['finished_utc']=datetime.datetime.now(datetime.timezone.utc).isoformat()
report['summary']={'members':sum(map(len,report['cases'].values())),'errors':len(report['errors']),
 'below200':sum(r.get('completed_epochs',999)<200 for rows in report['cases'].values() for r in rows),
 'at200':sum(r.get('completed_epochs')==200 for rows in report['cases'].values() for r in rows),
 'over200':sum(r.get('completed_epochs',0)>200 for rows in report['cases'].values() for r in rows)}
raw=(json.dumps(report,sort_keys=True,indent=2)+'\n').encode();(DEST/'preservation_report.json').write_bytes(raw)
print(json.dumps(report,sort_keys=True))
print(json.dumps({'preservation_report_sha256':digest(raw),'archive_root':str(DEST)}))
PRESERVE_003
