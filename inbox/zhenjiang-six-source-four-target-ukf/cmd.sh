#!/usr/bin/env bash
set -euo pipefail
python3 - <<'PY'
import pathlib,json,subprocess,re
root=pathlib.Path('/data1/home/sunyiq/zhenjiang_complete_comparison_20261006_002');response=json.loads((root/'records/monitoring_3h/gpu_compatibility_submission_007_response.json').read_text());match=re.fullmatch(r'Submitted batch job ([0-9]+)\s*',response['stdout'])
if response['returncode'] or not match:raise ValueError('unique synthetic compatibility job receipt missing')
job=match.group(1);report={'job_id':job,'commands':[]}
for c in (['squeue','-h','-j',job,'-o','%i|%T|%R|%N'],['sacct','-n','-X','-j',job,'--format=JobID,State,ExitCode,NodeList','-P']):
 r=subprocess.run(c,capture_output=True,text=True,timeout=15);report['commands'].append({'command':c,'returncode':r.returncode,'stdout':r.stdout,'stderr':r.stderr})
p=root/'records/monitoring_3h'/('gpu_compatibility_'+job+'.json');report['compatibility_result']=json.loads(p.read_text()) if p.exists() else None
report['logs']=[{'path':str(p),'tail':p.read_text(errors='replace')[-7000:]} for p in (root/'logs').glob('*_'+job+'.out')]
print(json.dumps(report,ensure_ascii=True))
PY
