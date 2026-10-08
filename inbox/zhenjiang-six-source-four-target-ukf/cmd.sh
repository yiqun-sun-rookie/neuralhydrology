#!/usr/bin/env bash
set -euo pipefail
python3 - <<'PY'
import pathlib,json,subprocess,re,hashlib
root=pathlib.Path('/data1/home/sunyiq/zhenjiang_complete_comparison_20261006_002')
folder=root/'records/monitoring_3h';folder.mkdir(exist_ok=True)
script=root/'hpc/gpu_compatibility_20261008_007.slurm';program=root/'hpc/gpu_compatibility_20261008.py'
if hashlib.sha256(script.read_bytes()).hexdigest()!='e43fae1156c0cbb69d71f5b474b63d0eaa3630fa11afa9dfc9c24bd4a6f2e5b7' or hashlib.sha256(program.read_bytes()).hexdigest()!='b960fa98723c9b50950532ee4dd4e83cf3e205502a2427d2c2dc9416e966731c':raise ValueError('partial compatibility preparation changed')
q=subprocess.run(['squeue','-h','-u','sunyiq','-o','%i|%j|%T'],capture_output=True,text=True,check=True)
if any('zj_gpu_compatibility_261008_007' in row for row in q.stdout.splitlines()):raise ValueError('compatibility probe already queued; do not duplicate')
p=folder/'gpu_compatibility_submission_007_attempt.json'
if (folder/'gpu_compatibility_submission_007_response.json').exists():raise ValueError('prior response exists; do not resubmit')
with p.open('x') as f:json.dump({'status':'reserved_after_repair_of_missing_record_directory','script':str(script),'script_sha256':'e43fae1156c0cbb69d71f5b474b63d0eaa3630fa11afa9dfc9c24bd4a6f2e5b7','original_preparation_receipt':186,'original_preparation_failed_before_submission':True},f,indent=2)
r=subprocess.run(['/usr/local/globle/softs/slurm/19.05.4.1/bin/xbatch',str(script)],capture_output=True,text=True,timeout=45);report={'returncode':r.returncode,'stdout':r.stdout,'stderr':r.stderr,'real_training_started':False}
with (folder/'gpu_compatibility_submission_007_response.json').open('x') as f:json.dump(report,f,indent=2)
m=re.fullmatch(r'Submitted batch job ([0-9]+)\s*',r.stdout)
if r.returncode or not m:raise RuntimeError('compatibility probe submission uncertain; do not repeat')
report['job_id']=m.group(1);print(json.dumps(report,ensure_ascii=True))
PY
