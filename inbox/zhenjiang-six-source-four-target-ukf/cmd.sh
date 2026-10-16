#!/usr/bin/env bash
set -eo pipefail
source /data1/home/sunyiq/miniconda3/etc/profile.d/conda.sh
conda activate nh_final
set -u
export PYTHONDONTWRITEBYTECODE=1
export CUDA_VISIBLE_DEVICES=""
python -B - <<'FAILED_SOURCE'
import hashlib,json,pathlib,subprocess,sys
root=pathlib.Path('/data1/home/sunyiq/zhenjiang_complete_comparison_20261015_recovery_005')
job='242937';case='explicit_gru__historical_capacity'
assert json.loads((root/'records/scheduler_jobs.json').read_text())[case]==job
queries=[]
for command in (['squeue','-h','-u','sunyiq','-o','%i|%j|%T|%Z'],
                ['sacct','-n','-X','-j',job,'--format=JobID,State,ExitCode,Start,End,NodeList','-P']):
    p=subprocess.run(command,capture_output=True,text=True,timeout=30)
    assert p.returncode==0,p.stderr
    queries.append({'command':command,'returncode':p.returncode,'stdout':p.stdout,'stderr':p.stderr})
rows=[line.split('|') for line in queries[0]['stdout'].splitlines() if line.strip()]
assert not any(row[0]==job or row[3]==str(root) or row[1].startswith(('zj_gru_cov_','zj_gru_covariance_','zj_gru_val_')) for row in rows)
accounting=[line.split('|') for line in queries[1]['stdout'].splitlines() if line.startswith(job+'|')]
assert len(accounting)==1 and accounting[0][1:3]==['FAILED','1:0']
assert accounting[0][3:5]==['2026-10-15T17:34:02','2026-10-15T19:30:36']
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
manifest_path=root/'release_manifest.json'
assert sha(manifest_path)=='daa4706da7c6f8f353536f6c3640ade9931a32e0f08fff6fb9d11473a5b729af'
manifest=json.loads(manifest_path.read_bytes());path=root/'hpc/audit_covariance_continuation_20261015.py'
assert sha(path)==manifest['files']['hpc/audit_covariance_continuation_20261015.py']['sha256']
text=path.read_text()
old="        assert not (target/'failure.json').exists(), 'new fit failure requires diagnosis'"
assert text.count(old)==1
# This is a diagnostic-only copy of the audit; failure presence never admits continuation.
text=text.replace(old,"""        failure=h.read(target/'failure.json')
        assert failure['status']=='failed' and failure['epochs_completed']==count
        assert failure['reason']=='covariance not positive definite after permitted jitter'
        metric=h.read(target/'metrics.json')
        assert all(metric[k]==new[v] for k,v in [('validation_mae_cm','values'),('train_metrics','train_metrics'),('shuffle_hashes','shuffle_hashes')])
        expected_steps=sum(len(batch_metrics) for batch_metrics in new['train_metrics'])
        assert all(step==expected_steps for step in after)""")
needle="'checkpoint_bytes':len(raw),";assert text.count(needle)==1
text=text.replace(needle,needle+" 'failure':failure,'failure_sha256':h.sha(target/'failure.json'),'metrics_equal_saved_checkpoint':True,'current_optimizer_steps':sorted(set(after)),'expected_optimizer_steps':expected_steps,")
text=text.replace("'status':'covariance_recovery_continuation_checkpoint_audit_passed'", "'status':'read_only_joseph_failed_checkpoint_source_audit'")
text=text.replace("'any_new_failure_file':False", "'any_new_failure_file':True, 'continuation_admitted':False, 'data_inputs_read':False")
begin=text.index("    path = ROOT/'records'/('covariance_checkpoint_audit_")
end=text.index('    print(json.dumps(audit',begin)
extra="""    def identity(p):
        b=p.read_bytes();return {'path':str(p),'bytes':len(b),'sha256':hashlib.sha256(b).hexdigest()}
    code_files=sorted([*ROOT.joinpath('src').glob('*.py'),*ROOT.joinpath('scripts').glob('*.py'),*ROOT.joinpath('vendor/pytides').glob('*.py')])
    code_hashes={p.relative_to(ROOT).as_posix():h.sha(p) for p in code_files}
    assert hashlib.sha256(json.dumps(code_hashes,sort_keys=True,separators=(',',':'),allow_nan=False).encode()).hexdigest()==auth['code_hash']
    group=h.read(ROOT/'records'/CASE/'tune_branch_group_configs.json');assert len(group)==12
    audit.update(source_code_file_hashes=code_hashes,
        all_member_source_files={rid:{name:identity(ROOT/'runs'/rid/name) for name in ['config.json','continuation.pt','failure.json','metrics.json']} for rid in group},
        files={name:identity(ROOT/name) for name in ['configs/protocol-v3.json','configs/registry-v3.json','records/authorization.json','records/data_preparation_complete.json','prepared/tuning/manifest.json','records/'+CASE+'/tune_branch_group_configs.json','records/'+CASE+'/tune_foundation_group_outcome.json']},
        queries=EXACT_QUERIES,source_root=str(ROOT),source_job=EXACT_JOB,
        checkpoints_loaded_on_cpu_only=True,scientific_or_scheduler_mutations=False,
        formal_training_restarted=False,formal_epochs_added=0)
"""
text=text[:begin]+extra+text[end:]
sys.path.insert(0,str(root/'hpc'))
namespace={'__name__':'read_only_failed_source_copy','__file__':str(path),'EXACT_QUERIES':queries,'EXACT_JOB':job}
exec(compile(text,str(path)+':diagnostic_failed_source_copy','exec'),namespace)
namespace['main']()
FAILED_SOURCE
