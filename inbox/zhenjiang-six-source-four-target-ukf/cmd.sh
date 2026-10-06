#!/usr/bin/env bash
set -euo pipefail
cd /data1/home/sunyiq/zhenjiang_complete_comparison_20261006_001
python3 - <<'PY'
import pathlib,subprocess,json
root=pathlib.Path.cwd()
p=root/'records/preparation_scheduler_receipt.txt'
if p.exists(): print('PREPARATION_RECEIPT',p.read_text())
for args in [['squeue','-u','sunyiq','-h','-o','%i|%j|%T|%R'],
             ['sacct','-S','2026-10-06T10:38:00','-u','sunyiq','-X','-n','--format=JobID,JobName%80,State,ExitCode','-P']]:
    result=subprocess.run(args,capture_output=True,text=True)
    for line in result.stdout.splitlines():
        if 'zj_' in line: print('OWN_JOB',line)
    if result.returncode: print('STATUS_COMMAND_FAILED',result.stderr[:1000])
for p in sorted((root/'logs').glob('*.out')):
    print('LOG',p.name,p.read_text(errors='replace')[-12000:])
PY
