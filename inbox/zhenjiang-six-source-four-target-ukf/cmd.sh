#!/usr/bin/env bash
set -eo pipefail
source /data1/home/sunyiq/miniconda3/etc/profile.d/conda.sh
conda activate nh_final
set -u
export PYTHONDONTWRITEBYTECODE=1
export CUDA_VISIBLE_DEVICES=""
export OMP_NUM_THREADS=1
export MKL_NUM_THREADS=1
python -B - <<'PY'
"""Bounded CPU reference audit of one authenticated stored failure; no training."""
import datetime, hashlib, json, pathlib, subprocess
import mpmath as mp
import torch

ROOT=pathlib.Path('/data1/home/sunyiq/zhenjiang_validation_posterior_diagnostic_20261015_001')
SOURCE=pathlib.Path('/data1/home/sunyiq/zhenjiang_complete_comparison_20261015_recovery_004')
EXPECTED='59bfa304af91eab58ebb9396fab4ff0a4ea9477c12cc9f7bfde3e0a0a2f30187'
def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def read(path):return json.loads(path.read_bytes())
assert not torch.cuda.is_available()
torch.set_num_threads(1)
queue=subprocess.run(['squeue','-h','-u','sunyiq','-o','%i|%T'],capture_output=True,text=True,check=True)
assert not any(line.split('|')[0] in ('242609','242731') for line in queue.stdout.splitlines())
acct=subprocess.run(['sacct','-n','-X','-j','242609,242731','--format=JobID,State,ExitCode,Start,End','-P'],capture_output=True,text=True,check=True)
rows={v[0]:v for line in acct.stdout.splitlines() if (v:=line.split('|'))[0] in ('242609','242731')}
assert rows['242609'][1:3]==['FAILED','1:0'] and rows['242731'][1:3]==['COMPLETED','0:0']
spec_path=ROOT/'diagnostic_spec.json'
assert sha(spec_path)=='5b813e474a6de0b53155ea6ee7efb2188b254bc72be6c892850f71edf50d59eb'
spec=read(spec_path);pinned=spec['pinned_source_files'];assert len(pinned)==58
assert all(sha(pathlib.Path(p))==s for p,s in pinned.items())
code_files=sorted([*SOURCE.joinpath('src').glob('*.py'),*SOURCE.joinpath('scripts').glob('*.py'),*SOURCE.joinpath('vendor/pytides').glob('*.py')])
code={p.relative_to(SOURCE).as_posix():sha(p) for p in code_files}
code_hash=hashlib.sha256(json.dumps(code,sort_keys=True,separators=(',',':')).encode()).hexdigest()
assert code_hash==spec['source_code_hash']=='0a5820033841bb4274dab7be44719992e21cd31546bf45bc079becf0d8464cb7'
result_path=ROOT/'evidence/posterior_diagnostic_result.json'
assert sha(result_path)=='535a1a62807f1daac167a0aa4ea3de849f01f381602d96823595e591ac972b2b'
prior=read(result_path)
assert prior['status']=='posterior_covariance_original_failure_captured' and prior['all_source_bytes_unchanged']
assert prior['optimizer_updates']==prior['formal_training_epochs_added']==0
raw_path=ROOT/'evidence/posterior_covariance_original_operands.pt';assert sha(raw_path)==EXPECTED
raw=torch.load(raw_path,map_location='cpu',weights_only=True)
values=raw['actual_linear_update_locals'];assert raw['context']['analysis_step']==24
assert raw['context']['validation_batch_index']==93 and raw['context']['window_indices']==list(range(1472,1488))
assert raw['original_jitters']==[0.,1e-10,1e-9,1e-8,1e-7,1e-6,1e-5,1e-4]
assert all(v.dtype==torch.float64 and bool(torch.isfinite(v).all()) for v in values.values())
assert values['p'].shape==values['covariance'].shape==(16,128,128)
assert bool((values['r_diagonal']>0).all())

def sym(t):return (t+t.transpose(-1,-2))*.5
cpu=[]
for index in range(16):
    entry={'member_index':index}
    for name in ('covariance','innovation_cov','p'):
        matrix=sym(values[name][index]);attempts=[]
        for jitter in raw['original_jitters']:
            factor,info=torch.linalg.cholesky_ex(matrix+jitter*torch.eye(matrix.shape[-1],dtype=torch.float64))
            attempts.append({'jitter':jitter,'info':int(info),'finite_factor':bool(torch.isfinite(factor).all())})
        entry[name]={'entry_scale':float(matrix.abs().max()),'attempts':attempts,
                     'stored_symmetric':torch.equal(values[name][index],values[name][index].T)}
    cpu.append(entry)

def matrix(t):return mp.matrix([[mp.mpf(float(v)) for v in row] for row in t.tolist()])
def factor_pivots(a):
    n=a.rows;lower=mp.matrix(n);minimum=None
    for j in range(n):
        pivot=a[j,j]-mp.fsum(lower[j,k]*lower[j,k] for k in range(j))
        minimum=pivot if minimum is None else min(minimum,pivot)
        if pivot<=0:return {'positive':False,'first_nonpositive_index':j,'pivot':mp.nstr(pivot,55),'minimum_pivot':mp.nstr(minimum,55)}
        lower[j,j]=mp.sqrt(pivot)
        for i in range(j+1,n):
            lower[i,j]=(a[i,j]-mp.fsum(lower[i,k]*lower[j,k] for k in range(j)))/lower[j,j]
    return {'positive':True,'first_nonpositive_index':None,'minimum_pivot':mp.nstr(minimum,55)}

# Member11 was the original GPU exception. Two diagnostic precisions distinguish
# a stored indefinite matrix from roundoff introduced by the Joseph products.
member=11;references=[];rounded=[]
for digits in (80,120):
    with mp.workdps(digits):
        cov=matrix(sym(values['covariance'][member]));stored=matrix(sym(values['p'][member]))
        complement=matrix(values['complement'][member]);gain=matrix(values['gain'][member]);noise=matrix(values['r'][member])
        joseph=complement*cov*complement.T+gain*noise*gain.T
        joseph=(joseph+joseph.T)/2
        nearest=torch.tensor([[float(joseph[i,j]) for j in range(128)] for i in range(128)],dtype=torch.float64)
        reference={'decimal_digits':digits,'member_index':member,'stored_prior':factor_pivots(cov),
                   'stored_posterior':factor_pivots(stored),'same_joseph_from_stored_operands':factor_pivots(joseph),
                   'maximum_stored_posterior_difference':mp.nstr(max(abs(stored[i,j]-joseph[i,j]) for i in range(128) for j in range(128)),55),
                   'reference_uses_stored_gain_complement_prior_noise':True,
                   'nearest_float64_reference_sha256':hashlib.sha256(nearest.numpy().tobytes()).hexdigest()}
        f,info=torch.linalg.cholesky_ex(nearest)
        reference['nearest_float64_reference_cpu_cholesky']={'info':int(info),'finite_factor':bool(torch.isfinite(f).all())}
        references.append(reference);rounded.append(nearest)
assert torch.equal(rounded[0],rounded[1])
assert all(references[0][key]['positive']==references[1][key]['positive'] for key in ('stored_prior','stored_posterior','same_joseph_from_stored_operands'))
assert all(sha(pathlib.Path(p))==s for p,s in pinned.items()) and sha(raw_path)==EXPECTED
at=datetime.datetime.now(datetime.timezone(datetime.timedelta(hours=8)))
record={'status':'posterior_stored_operands_cpu_audit_preserved','checked_at_beijing':at.isoformat(),
    'root':str(ROOT),'source_root':str(SOURCE),'source_code_hash':code_hash,'source_identity_count':len(pinned),
    'all_source_bytes_unchanged':True,'all_twelve_failed_members_preserved':True,'operands_sha256':EXPECTED,
    'posterior_result_sha256':sha(result_path),'original_context':raw['context'],
    'original_linear_update_source':raw['linear_update_source'],'original_jitters':raw['original_jitters'],
    'all_original_operands_finite':True,'all_observation_noise_diagonals_positive':True,'cpu_attempts':cpu,
    'high_precision_diagnostic_references':references,'two_precision_nearest_float64_reference_equal':True,
    'diagnostic_precision_not_applied_to_training':True,'historical_rng_equality_established':False,
    'actual_accounting':rows,'gpu_work_performed':False,'training_data_values_read':False,
    'selection_data_values_read':False,'evaluation_values_read':False,'formal_training_epochs_added':0,
    'optimizer_updates':0,'scheduler_mutated':False,'scientific_rules_changed':False,'formal_recovery_admitted':False}
path=ROOT/'evidence'/('posterior_stored_cpu_audit_'+at.strftime('%Y%m%d_%H%M%S_%f')+'.json')
with path.open('x',encoding='utf-8') as f:json.dump(record,f,sort_keys=True,allow_nan=False);f.write('\n')
record.update(immutable_record=str(path),immutable_record_sha256=sha(path))
print(json.dumps(record,sort_keys=True,allow_nan=False))
PY
