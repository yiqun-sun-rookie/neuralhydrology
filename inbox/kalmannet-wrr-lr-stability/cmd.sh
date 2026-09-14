#!/usr/bin/env bash
set -euo pipefail
python3 -I -B - <<'PY'
import hashlib,json,os,shutil,subprocess
from datetime import datetime,timezone
from pathlib import Path
root=Path('/data1/home/sunyiq/kalmannet_wrr_lr_stability_20260914')
old=Path('/data1/home/sunyiq/kalmannet_wrr_hp_extension_20260902/repo')
source=old/'knet/pipelines/train_clean_based_on_11.py'
expected='8aef76e4462754337f2d0b1bb35f1dde7141293175dfbb78c756f3356ec009ff'
actual=hashlib.sha256(source.read_bytes()).hexdigest()
data={s:old/'data/processed/high_flow_aug'/n for s,n in {
 'train':'train_win800_19990101_01-20070527_03.pt',
 'val':'val_win800_20070527_04-20090314_13.pt'}.items()}
report={'time_utc':datetime.now(timezone.utc).isoformat(),'new_root_absent':not os.path.lexists(root),
 'original_training_sha256':actual,'source_matches_frozen':actual==expected,
 'data_metadata':{s:{'path':str(p),'exists':p.is_file(),'bytes':p.stat().st_size if p.is_file() else None} for s,p in data.items()},
 'environment_interpreter_exists':Path('/data1/home/sunyiq/miniconda3/envs/knet_clean/bin/python').is_file(),
 'free_bytes':shutil.disk_usage(root.parent).free,'training_started':False,'data_tensors_loaded':False}
print(json.dumps(report,sort_keys=True),flush=True)
assert report['new_root_absent'] and report['source_matches_frozen'] and report['environment_interpreter_exists']
assert all(d['exists'] for d in report['data_metadata'].values())
assert report['free_bytes']>10*1024**3
subprocess.run(['sinfo','-N','-p','hgpu2p','-o','%N|%G|%t'],check=True)
print('LR_STUDY_PREFLIGHT_PASS',flush=True)
PY
