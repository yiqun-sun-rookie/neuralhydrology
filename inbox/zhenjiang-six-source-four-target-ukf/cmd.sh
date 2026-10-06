#!/usr/bin/env bash
set -euo pipefail
cd /data1/home/sunyiq/zhenjiang_complete_comparison_20261006_002
python3 - <<'PY'
import hashlib,json,pathlib,re,subprocess
root=pathlib.Path.cwd()
bad='/data1/home/sunyiq/zhenjiang_complete_comparison_20261006_r2_002'
manifest=json.loads((root/'release_manifest.json').read_text())
for name,spec in manifest['files'].items():
    if hashlib.sha256((root/name).read_bytes()).hexdigest()!=spec['sha256']:
        raise ValueError('released source changed')
if (root/'prepared').exists(): raise ValueError('preparation evidence already exists; preserve and inspect')
old_ids={'236700','236701','236702','236703'}
result=subprocess.run(['squeue','-u','sunyiq','-h','-o','%i|%j|%T|%R'],capture_output=True,text=True,check=True)
old=[]
for line in result.stdout.splitlines():
    fields=line.split('|')
    if fields[0] in old_ids:
        if fields[2]!='PENDING' or 'DependencyNeverSatisfied' not in fields[3]: raise ValueError('old job state changed')
        old.append(fields[0])
    if 'pathfix' in fields[1]: raise ValueError('path-fix job already exists')
with (root/'records/scheduler_jobs_before_path_fix.json').open('x') as f:
    f.write((root/'records/scheduler_jobs.json').read_text())
jobs={}
def submit(key,body):
    body=body.replace(bad,str(root))
    assert bad not in body
    output=next(line.split('=',1)[1] for line in body.splitlines() if line.startswith('#SBATCH --output='))
    directory=next(line[3:] for line in body.splitlines() if line.startswith('cd '))
    if pathlib.Path(output).parent!=root/'logs' or pathlib.Path(directory)!=root:
        raise ValueError('generated scheduler paths escape exact released root')
    path=root/'hpc'/('pathfix_'+key+'.slurm')
    with path.open('x') as f: f.write(body)
    with (root/'records'/('pathfix_'+key+'_attempt.json')).open('x') as f:
        json.dump({'script':str(path),'sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'status':'reserved'},f)
    result=subprocess.run(['/usr/local/globle/softs/slurm/19.05.4.1/bin/xbatch',str(path)],capture_output=True,text=True,timeout=60)
    with (root/'records'/('pathfix_'+key+'_response.json')).open('x') as f:
        json.dump({'returncode':result.returncode,'stdout':result.stdout,'stderr':result.stderr},f,indent=2)
    matched=re.fullmatch(r'Submitted batch job ([0-9]+)\s*',result.stdout)
    if result.returncode or not matched:
        print(result.stdout,result.stderr,flush=True); raise RuntimeError('unconfirmed scheduler attempt; inspect, do not repeat')
    job=matched.group(1); jobs[key]=job
    temp=root/'records/scheduler_jobs.json.tmp'; temp.write_text(json.dumps(jobs,indent=2)+'\n')
    temp.replace(root/'records/scheduler_jobs.json')
    print(json.dumps({'status':'submitted','key':key,'job_id':job}),flush=True)
    return job
body=(root/'hpc/prepare_data.sbatch').read_text().replace('#SBATCH --job-name=zj_prepare_261006_r2',
    '#SBATCH --job-name=zj_prepare_261006_pathfix')
prep=submit('preparation',body)
base=(root/'hpc/train_case.sbatch').read_text()
for case in ('legacy_lstm__small','explicit_gru__small','legacy_lstm__historical_capacity','explicit_gru__historical_capacity'):
    body=base.replace('#SBATCH --job-name=zj_train_261006_r2',
        '#SBATCH --job-name=zj_'+case+'_261006_pathfix\n#SBATCH --dependency=afterok:'+prep)
    body=body.replace('case_name="$1"','case_name="'+case+'"')
    submit(case,body)
if old:
    result=subprocess.run(['scancel',*old],capture_output=True,text=True)
    with (root/'records/old_path_failed_jobs_cancelled.json').open('x') as f:
        json.dump({'jobs':old,'returncode':result.returncode,'failed_preparation_236699_preserved':True},f)
    if result.returncode: raise RuntimeError('old jobs cancellation failed')
result=subprocess.run(['squeue','-h','-j',','.join(jobs.values()),'-o','%i|%j|%T|%R'],capture_output=True,text=True)
print(result.stdout)
PY
