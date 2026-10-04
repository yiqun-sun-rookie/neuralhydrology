#!/bin/bash
set -eo pipefail
export PYTHONNOUSERSITE=1 PYTHONDONTWRITEBYTECODE=1
/data1/home/sunyiq/miniconda3/envs/knet_clean/bin/python -B - <<'PY'
from pathlib import Path
PHASE=Path('/data1/home/sunyiq/kalmannet_tukf09_four_failed_basins_20261003_attempt1')
EXPECTED_MANIFEST='590981edde63612507d2d18468baf1585fd0bafc825b44a7030778391c9e8b37'
EXPECTED_ARCHIVE='e8fd8432106756d907e20cd1819c7e94a1637b5551c6f45ebd98da0dea9608d9'
BASIN='all'

import importlib.util, json, re
from pathlib import Path
spec=importlib.util.spec_from_file_location('saved_stage', PHASE/'remote_stage.py')
s=importlib.util.module_from_spec(spec); spec.loader.exec_module(s)
s.adapter()
manifest=s.sha(PHASE/'payload_manifest.json')
if manifest != EXPECTED_MANIFEST: raise RuntimeError('manifest binding changed')
rows=[]; jobs=[]
known={'deployment.json','submission_attempt.json','submission.json','runtime_gate.json','job_terminal.json','terminal_capture.json','independent_admission.json'}
for basin in s.BASINS:
 root=PHASE/f'basin_{basin}'; control=root/'control'
 if not control.is_dir() or control.is_symlink(): raise RuntimeError('missing or linked control')
 files=list(control.iterdir())
 if any(p.is_symlink() or not p.is_file() or p.name not in known for p in files): raise RuntimeError('unexpected control evidence')
 data={p.name:json.loads(p.read_text(encoding='utf-8')) for p in files}
 deployed=data.get('deployment.json',{})
 if deployed.get('basin_id')!=basin or deployed.get('manifest_sha256')!=manifest or deployed.get('archive_sha256')!=EXPECTED_ARCHIVE: raise RuntimeError('deployment binding changed')
 record={'basin_id':basin,'control':data,'accounting':None,'archive_sha256':None}
 if 'submission.json' in data:
  _,submitted=s.submitted_record(basin); jobs.append(submitted['job_id'])
  if 'submission_attempt.json' not in data: raise RuntimeError('submission without attempt')
  if submitted.get('script_sha256') != s.sha(PHASE/f'basin_{basin}.slurm'): raise RuntimeError('submission script changed')
  record['accounting']=s.accounting(submitted['job_id'])
 if 'submission_attempt.json' in data:
  attempt=data['submission_attempt.json']
  if attempt.get('basin_id')!=basin or attempt.get('manifest_sha256')!=manifest or attempt.get('script_sha256')!=s.sha(PHASE/f'basin_{basin}.slurm') or attempt.get('wall_seconds')!=28800 or attempt.get('requested_cpus')!=1: raise RuntimeError('attempt identity/resources changed')
 archive=PHASE/f'exports/terminal_{basin}.zip'
 if archive.exists():
  if archive.is_symlink() or not archive.is_file(): raise RuntimeError('linked archive')
  record['archive_sha256']=s.sha(archive)
 rows.append(record)
if len(jobs)!=len(set(jobs)): raise RuntimeError('duplicate job identities')
queue=s.run(['squeue','-u','sunyiq','-h','-o','%i|%j|%T|%R'])
scaled=[line.split('|')[0] for line in queue.splitlines() if '|tukf09-noise-' in line]
if any(job not in jobs for job in scaled) or len(scaled)>1: raise RuntimeError('other in-flight scaled-noise job')
print('FOUR_FAILED_RECONCILIATION '+json.dumps({'manifest_sha256':manifest,'basins':rows,'scaled_queue_job_ids':scaled},sort_keys=True),flush=True)

PY
