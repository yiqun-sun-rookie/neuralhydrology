#!/usr/bin/env bash
set -euo pipefail
cd /data1/home/sunyiq/zhenjiang_complete_comparison_20261006_001
python3 - <<'PY'
import hashlib,json,pathlib,re,subprocess
root=pathlib.Path.cwd()
manifest=json.loads((root/'release_manifest.json').read_text())
for name in ('hpc/prepare_data.sbatch','hpc/train_case.sbatch'):
    if hashlib.sha256((root/name).read_bytes()).hexdigest()!=manifest['files'][name]['sha256']:
        raise ValueError('released job template changed')
query=subprocess.run(['squeue','-u','sunyiq','-h','-o','%i|%j'],capture_output=True,text=True,check=True)
if any('zj_' in line and '261006' in line for line in query.stdout.splitlines()):
    raise ValueError('an own job already exists; inspect instead of resubmitting')
old=(root/'records/preparation_scheduler_receipt.txt').read_text()
if 'EXAMPLE FOR CPU QUEUE' not in old or 'Submitted batch job' in old:
    raise ValueError('earlier wrapper response is not a confirmed help-only call')
jobs={}
def submit(key,content):
    script=root/'hpc'/('submit_v3_'+key+'.slurm')
    with script.open('x') as f: f.write(content)
    record=root/'records'/('submission_v3_'+key+'_attempt.json')
    with record.open('x') as f: json.dump({'status':'reserved','script':str(script),
        'script_sha256':hashlib.sha256(script.read_bytes()).hexdigest()},f)
    result=subprocess.run(['/usr/local/globle/softs/slurm/19.05.4.1/bin/xbatch',str(script)],
                          capture_output=True,text=True,timeout=60)
    with (root/'records'/('submission_v3_'+key+'_response.json')).open('x') as f:
        json.dump({'returncode':result.returncode,'stdout':result.stdout,'stderr':result.stderr},f,indent=2)
    match=re.fullmatch(r'Submitted batch job ([0-9]+)\s*',result.stdout)
    if result.returncode!=0 or not match:
        print('UNRECOGNIZED_SCHEDULER_RESPONSE',key,result.returncode,result.stdout,result.stderr,flush=True)
        raise RuntimeError('scheduler response unconfirmed; preserve and inspect before retry')
    job=match.group(1); jobs[key]=job
    temp=root/'records/scheduler_jobs.json.tmp'; temp.write_text(json.dumps(jobs,indent=2)+'\n')
    temp.replace(root/'records/scheduler_jobs.json')
    print(json.dumps({'status':'submitted','key':key,'job_id':job}),flush=True)
    return job
prep=submit('preparation',(root/'hpc/prepare_data.sbatch').read_text().replace('#SBATCH --partition=hgpu2p','#SBATCH -p hgpu2p'))
base=(root/'hpc/train_case.sbatch').read_text().replace('#SBATCH --partition=hgpu2p','#SBATCH -p hgpu2p')
for case in ('legacy_lstm__small','explicit_gru__small','legacy_lstm__historical_capacity','explicit_gru__historical_capacity'):
    content=base.replace('#SBATCH --job-name=zj_train_261006',
        '#SBATCH --job-name=zj_'+case+'_261006\n#SBATCH --dependency=afterok:'+prep)
    content=content.replace('case_name="$1"','case_name="'+case+'"')
    submit(case,content)
result=subprocess.run(['squeue','-h','-j',','.join(jobs.values()),'-o','%i|%j|%T|%R'],capture_output=True,text=True)
print(result.stdout)
PY
