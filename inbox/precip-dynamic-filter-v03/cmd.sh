#!/usr/bin/env bash
set -eo pipefail
task_run="$HOME/precip_dynamic_eight_basins_20261003/eight_basin_fixed_recipe_v01_20261003_230000_d5028d71"
test -d "$task_run"
task_run=$(readlink -f "$task_run")
case "$task_run" in "$HOME/precip_dynamic_eight_basins_20261003/"*) ;; *) exit 30 ;; esac
"/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python" -B - "$task_run" <<'PY'
import sys,json,hashlib,base64
from pathlib import Path
root=Path(sys.argv[1]).resolve()
files=['runtime/stage_2.json','runtime/probe/probe_gate.json','runtime/probe/probe_process.json','runtime/training/stage_manifest.json']
files += ['runtime/probe/'+b+'/'+n for b in ('01487000','12040500','09312600','08198500','03078000','05362000','08267500','07145700') for n in ('resource_measurement.json','probe_record.json','adapter_isolation.json','isolation_reference_process.json')]
total=0
for relative in files:
 p=root/relative
 assert p.is_file() and not p.is_symlink() and p.resolve().is_relative_to(root)
 before=p.stat()
 assert before.st_size<=1048576
 total+=before.st_size
 assert total<=4*1024*1024
 raw=p.read_bytes();after=p.stat()
 assert (before.st_size,before.st_mtime_ns,before.st_ino)==(after.st_size,after.st_mtime_ns,after.st_ino)
 print('METADATA_JSON='+json.dumps({'relative_path':relative,'bytes':len(raw),'sha256':hashlib.sha256(raw).hexdigest(),'base64':base64.b64encode(raw).decode()},sort_keys=True))
print('METADATA_COMPLETE='+json.dumps({'files':len(files),'bytes':total,'scope':'completed resource and adapter-isolation metadata only; no raw daily data; no model execution'}))
PY
