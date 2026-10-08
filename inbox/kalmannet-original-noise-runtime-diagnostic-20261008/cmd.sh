#!/bin/bash
set -eo pipefail
/data1/home/sunyiq/miniconda3/envs/knet_clean/bin/python -X utf8 -B - <<'INSTALLATION_DIAGNOSIS'
import json, subprocess
from pathlib import Path
phase=Path('/data1/home/sunyiq/kalmannet_original_noise_multiday_evaluation_20261008_recovery2')
record={'mode':'read-only installation failure diagnosis','scientific_model_runs':0,'scientific_submissions':0,'modified_files':0,'phase_exists':phase.exists(),'files':[]}
for name in ['runtime/installation_intent.json','runtime/base_environment_before.json','runtime/base_environment_after.json','runtime/wheels/numpy-1.26.4-cp311-cp311-manylinux_2_17_x86_64.manylinux2014_x86_64.whl','runtime/venv/pyvenv.cfg','runtime/pip_stdout.log','runtime/pip_stderr.log','runtime/runtime_identity.json']:
    path=phase/name
    item={'name':name,'exists':path.exists()}
    if path.is_file():
        item.update(bytes=path.stat().st_size,modified=path.stat().st_mtime)
        if name.endswith(('.log','pyvenv.cfg','installation_intent.json')):
            item['tail']=path.read_text(encoding='utf-8',errors='replace').splitlines()[-20:]
    record['files'].append(item)
processes=subprocess.run(['ps','-eo','pid,ppid,etimes,stat,args'],check=True,capture_output=True,text=True,timeout=20).stdout.splitlines()
record['installation_processes']=[line for line in processes if str(phase) in line and 'INSTALLATION_DIAGNOSIS' not in line]
record['scientific_queue']=subprocess.run(['squeue','--user=sunyiq','--name=original-noise-multiday','--noheader','--format=%i %t %M %R'],check=True,capture_output=True,text=True,timeout=45).stdout.strip()
staged=Path.home()/'.hpc_mailbox_staging/kalmannet-original-noise-multiday-20261007/result_15.txt'
record['main_receipt_staged_exists']=staged.is_file()
if staged.is_file():
    record['main_receipt_staged_bytes']=staged.stat().st_size
print('INSTALLATION_DIAGNOSIS_JSON='+json.dumps(record),flush=True)
INSTALLATION_DIAGNOSIS
