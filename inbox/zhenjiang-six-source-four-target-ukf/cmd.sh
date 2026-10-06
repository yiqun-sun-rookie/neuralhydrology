#!/usr/bin/env bash
set -euo pipefail
python3 - <<'PY'
import pathlib,subprocess,json
root=pathlib.Path('/data1/home/sunyiq/zhenjiang_complete_comparison_20261006_001')
wrapper=pathlib.Path('/usr/local/globle/softs/slurm/19.05.4.1/bin/xbatch')
r=subprocess.run(['file',str(wrapper)],capture_output=True,text=True); print(r.stdout)
raw=wrapper.read_bytes()
if b'\x00' not in raw:
    lines=raw.decode(errors='replace').splitlines()
    for i,line in enumerate(lines):
        if any(word in line for word in ('sbatch','SBATCH','/bin/bash','argv','$#','awk','grep','exit','cat ','sed ')):
            if any(word in line.lower() for word in ('password','token','secret','authorization')): continue
            print('WRAPPER_LINE',i+1,line[:1000])
for args in [['squeue','-u','sunyiq','-h','-o','%i|%j|%T|%R'],
             ['sacct','-S','2026-10-06T10:38:00','-u','sunyiq','-X','-n','--format=JobID,JobName%80,State,ExitCode','-P']]:
    result=subprocess.run(args,capture_output=True,text=True)
    for line in result.stdout.splitlines():
        if 'zj_' in line: print('OWN_JOB',line)
    if result.returncode: print('STATUS_ERROR',result.stderr[:1000])
for p in sorted((root/'records').glob('submission_v2_*_response.json')): print('RESPONSE',p.name,p.read_text())
for p in sorted((root/'logs').glob('*.out')): print('LOG',p.name,p.read_text(errors='replace')[-5000:])
source=pathlib.Path('/data1/home/sunyiq/zhenjiang_5s5t_stage_a_20260905_recovery_001/inputs/2017_2022')
print(json.dumps({'isolated_source_root_is_exact_resolved_directory':source.resolve()==source,
    'roles_are_exact_resolved_directories':all((source/role).resolve()==source/role for role in ('realtime_features','retrospective_targets'))}))
PY
