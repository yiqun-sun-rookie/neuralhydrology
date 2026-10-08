#!/usr/bin/env bash
set -euo pipefail
python3 - <<'PY'
import pathlib,subprocess,json,hashlib
root=pathlib.Path('/data1/home/sunyiq/zhenjiang_complete_comparison_20261006_002')
job=str(json.loads((root/'records/scheduler_jobs.json').read_text())['legacy_lstm__small'])
report={'read_only':True,'job':job,'commands':[]}
for cmd in (['sinfo','-N','-h','-p','hgpu2p','-o','%n|%t|%G|%C'],['scontrol','show','job','-o',job],['sacct','-n','-X','-j',job,'--format=JobID,State,ExitCode','-P']):
 r=subprocess.run(cmd,capture_output=True,text=True,timeout=20);report['commands'].append({'command':cmd,'returncode':r.returncode,'stdout':r.stdout,'stderr':r.stderr})
p=root/'hpc/pathfix_legacy_lstm__small.slurm';raw=p.read_bytes();report['source_pathfix']={'path':str(p),'sha256':hashlib.sha256(raw).hexdigest(),'content':raw.decode()}
for host in ('ngu001','ngu011'):
 cmd=['ssh','-o','BatchMode=yes','-o','ConnectTimeout=10',host,'nvidia-smi --query-gpu=index,name,memory.total,utilization.gpu,uuid --format=csv; nvidia-smi --query-compute-apps=pid,gpu_uuid --format=csv']
 r=subprocess.run(cmd,capture_output=True,text=True,timeout=20);report['commands'].append({'command':cmd,'returncode':r.returncode,'stdout':r.stdout,'stderr':r.stderr})
print(json.dumps(report,ensure_ascii=True))
PY
