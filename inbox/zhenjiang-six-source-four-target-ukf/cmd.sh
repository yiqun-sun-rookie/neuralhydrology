#!/usr/bin/env bash
set -euo pipefail
python3 - <<'PY'
import pathlib,subprocess,re
root=pathlib.Path('/data1/home/sunyiq/zhenjiang_complete_comparison_20261006_002')
allowed=[root,pathlib.Path('/data1/home/sunyiq/zhenjiang_complete_comparison_20261006_001')]
for args in [['scontrol','show','job','-o','236699'],
             ['sacct','-j','236699','-n','-P','--format=JobID,State,ExitCode,NodeList,WorkDir%120,SubmitLine%200']]:
    result=subprocess.run(args,capture_output=True,text=True); print(result.stdout); print(result.stderr[:1000])
    for value in re.findall(r'(?:StdOut|StdErr)=([^ ]+)',result.stdout):
        path=pathlib.Path(value)
        if path.is_absolute() and any(a==path or a in path.parents for a in allowed) and path.is_file():
            print('JOB_LOG',str(path),path.read_text(errors='replace')[-16000:])
p=root/'hpc/recovery_preparation.slurm'; print('JOB_SCRIPT',p.read_text())
for a in allowed:
    for p in sorted((a/'logs').glob('*236699*')): print('RELATED_LOG',str(p),p.read_text(errors='replace')[-16000:])
PY
