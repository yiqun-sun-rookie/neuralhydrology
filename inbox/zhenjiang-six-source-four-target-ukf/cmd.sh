#!/usr/bin/env bash
set -eo pipefail
source /data1/home/sunyiq/miniconda3/etc/profile.d/conda.sh
conda activate nh_final
set -u
export PYTHONDONTWRITEBYTECODE=1
export CUDA_VISIBLE_DEVICES=""
python -B - <<'PY'
import datetime, hashlib, json, pathlib, subprocess
import torch

ROOT=pathlib.Path('/data1/home/sunyiq/zhenjiang_validation_covariance_diagnostic_20261015_001')
SOURCE=pathlib.Path('/data1/home/sunyiq/zhenjiang_complete_comparison_20261015_recovery_004')
EVIDENCE=ROOT/'evidence'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def read(p):return json.loads(p.read_bytes())
def finite_tree(value):
    if isinstance(value,torch.Tensor):return bool(torch.isfinite(value).all())
    if isinstance(value,dict):return all(finite_tree(x) for x in value.values())
    if isinstance(value,(tuple,list)):return all(finite_tree(x) for x in value)
    return True
assert not torch.cuda.is_available()
queue=subprocess.run(['squeue','-h','-u','sunyiq','-o','%i|%T'],capture_output=True,text=True,check=True)
assert not any(l.startswith('242633|') or l.startswith('242609|') for l in queue.stdout.splitlines())
acct=subprocess.run(['sacct','-n','-X','-j','242633,242609','--format=JobID,State,ExitCode,Start,End','-P'],capture_output=True,text=True,check=True)
rows={p[0]:p for l in acct.stdout.splitlines() if (p:=l.split('|')) and p[0] in ('242633','242609')}
assert rows['242633'][1:3]==['COMPLETED','0:0'] and rows['242609'][1:3]==['FAILED','1:0']
operands_path=EVIDENCE/'covariance_failure_operands.pt';start_path=EVIDENCE/'before_validation_model_adam_rng.pt'
assert sha(operands_path)=='2b23d69d1f4d8ccc323a70854ce4fc90405173ed27d41aaaaa6b88b774c65d57'
assert sha(start_path)=='3670f5d59ff11f4df3817e687d19f6e2969be6908c38f375163b3fc713da1da6'
result=read(EVIDENCE/'diagnostic_result.json');spec=read(ROOT/'diagnostic_spec.json')
assert result['status']=='validation_covariance_failure_captured' and result['formal_training_epochs_added']==0
assert result['source_code_sha256']==spec['source_code_hash']=='0a5820033841bb4274dab7be44719992e21cd31546bf45bc079becf0d8464cb7'
binding=result['source_file_sha256']
assert all(sha(pathlib.Path(p))==s for p,s in binding.items())
source_files=sorted([*SOURCE.joinpath('src').glob('*.py'),*SOURCE.joinpath('scripts').glob('*.py'),*SOURCE.joinpath('vendor/pytides').glob('*.py')])
source_hashes={p.relative_to(SOURCE).as_posix():sha(p) for p in source_files}
code_hash=hashlib.sha256(json.dumps(source_hashes,sort_keys=True,separators=(',',':'),allow_nan=False).encode()).hexdigest()
assert code_hash==result['source_code_sha256']
operand=torch.load(operands_path,map_location='cpu',weights_only=True)
start=torch.load(start_path,map_location='cpu',weights_only=True)
assert finite_tree(start['model']) and finite_tree(start['optimizer'])
steps=sorted(set(float(s['step']) for s in start['optimizer']['state'].values()))
assert steps==[6906.0] and operand['original_jitters']==[0.,1e-10,1e-9,1e-8,1e-7,1e-6,1e-5,1e-4]
inputs=operand['original_predict_inputs'];mean=inputs['mean'];cov=inputs['covariance'];saved=operand['original_sigma_points']
assert cov.dtype==torch.float64 and cov.shape==(16,128,128) and bool(torch.isfinite(cov).all())
assert mean.dtype==torch.float64 and bool(torch.isfinite(mean).all())
sym=(cov+cov.transpose(-1,-2))*.5
nan_indices=torch.nonzero(~torch.isfinite(saved),as_tuple=False).tolist()
failed_members=sorted(set(v[0] for v in nan_indices))
cpu=[]
for index,matrix in enumerate(sym):
    eigen=torch.linalg.eigvalsh(matrix)
    checks=[]
    for jitter in operand['original_jitters']:
        factor,info=torch.linalg.cholesky_ex(matrix+jitter*torch.eye(128,dtype=torch.float64))
        good=bool(torch.isfinite(factor).all());positive=bool((factor.diagonal()>0).all())
        checks.append({'jitter':jitter,'info':int(info),'finite_factor':good,'positive_diagonal':positive,
                       'minimum_factor_diagonal':float(factor.diagonal().min()) if good else None})
        if int(info)==0 and good:
            delta=factor.T*(128**.5)
            replay=torch.cat((mean[index:index+1],mean[index:index+1]+delta,mean[index:index+1]-delta),0)
            assert bool(torch.isfinite(replay).all())
            checks[-1]['cpu_sigma_all_finite']=True
            checks[-1]['max_finite_saved_sigma_difference']=float((replay-saved[index]).abs()[torch.isfinite(saved[index])].max())
        # Diagnose every permitted value without accepting a new jitter.
    cpu.append({'member_index':index,'stored_sigma_nonfinite':index in failed_members,
                'minimum_eigenvalue_float64_estimate':float(eigen.min()),'maximum_eigenvalue_float64_estimate':float(eigen.max()),
                'entry_scale':float(matrix.abs().max()),'minimum_diagonal':float(matrix.diagonal().min()),'cpu_jitter_attempts':checks})
assert all(sha(pathlib.Path(p))==s for p,s in binding.items()) and sha(operands_path)=='2b23d69d1f4d8ccc323a70854ce4fc90405173ed27d41aaaaa6b88b774c65d57'
at=datetime.datetime.now(datetime.timezone(datetime.timedelta(hours=8)))
record={'status':'validation_sigma_points_cpu_audit_preserved','checked_at_beijing':at.isoformat(),
        'root':str(ROOT),'source_root':str(SOURCE),'source_code_hash':code_hash,'source_file_count':len(source_hashes),
        'source_identity_count':len(binding),'all_source_bytes_unchanged':True,'all_twelve_failed_members_preserved':True,
        'operands_sha256':sha(operands_path),'before_validation_model_adam_rng_sha256':sha(start_path),
        'model_and_adam_all_finite':True,'diagnostic_in_memory_optimizer_steps':steps,'rng_keys':sorted(start['rng']),
        'original_context':operand['context'],'original_sigma_nonfinite_indices':nan_indices,
        'cpu_factor_attempts':cpu,'actual_accounting':rows,'gpu_work_performed':False,'training_data_values_read':False,
        'selection_data_values_read':False,'evaluation_values_read':False,'formal_training_epochs_added':0,
        'scheduler_mutated':False,'science_rules_changed':False,'technical_recovery_admitted':False,
        'historical_rng_equality_established':False,'stored_covariance_spd_not_established_by_float64_eigen_estimate':True}
path=EVIDENCE/('sigma_points_cpu_audit_'+at.strftime('%Y%m%d_%H%M%S_%f')+'.json')
with path.open('x',encoding='utf-8') as f:json.dump(record,f,sort_keys=True,allow_nan=False);f.write('\n')
record['immutable_record']=str(path);record['immutable_record_sha256']=sha(path)
print(json.dumps(record,sort_keys=True,allow_nan=False))
PY
