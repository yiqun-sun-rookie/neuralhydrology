#!/usr/bin/env bash
set -eo pipefail
source /data1/home/sunyiq/miniconda3/etc/profile.d/conda.sh
conda activate nh_final
set -u
export PYTHONDONTWRITEBYTECODE=1
python -B - <<'PY'
import datetime,hashlib,json,pathlib,subprocess
root=pathlib.Path('/data1/home/sunyiq/zhenjiang_validation_joseph_factorization_audit_20261016_002')
old=pathlib.Path('/data1/home/sunyiq/zhenjiang_validation_joseph_factorization_audit_20261016_001')
source=pathlib.Path('/data1/home/sunyiq/zhenjiang_complete_comparison_20261015_recovery_005')
def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def query(args):
 p=subprocess.run(args,capture_output=True,text=True,timeout=30)
 assert p.returncode==0,{'args':args,'stdout':p.stdout,'stderr':p.stderr}
 return {'command':args,'returncode':p.returncode,'stdout':p.stdout,'stderr':p.stderr}
queue=query(['squeue','-h','-u','sunyiq','-o','%i|%j|%T|%Z'])
rows=[line.split('|') for line in queue['stdout'].splitlines() if line.strip()]
assert all(len(row)==4 for row in rows)
matching=[row for row in rows if row[0]=='243308' or row[1].startswith('zj_gru_') or row[3] in (str(root),str(old),str(source))]
accounting=query(['sacct','-n','-X','-j','243308','--format=JobID,State,ExitCode,Start,End','-P'])
terminal=[line.split('|') for line in accounting['stdout'].splitlines() if line.startswith('243308|')]
assert len(terminal)==1 and terminal[0][:5]==['243308','FAILED','1:0','2026-10-16T01:04:31','2026-10-16T01:04:48']
error_path=old/'evidence/joseph_gpu_factorization_audit_technical_error.json'
error=json.loads(error_path.read_bytes())
assert error['error_type']=='AssertionError' and 'assert torch.equal(original[index:index+1], candidate)' in error['traceback']
checkpoint=source/'runs/explicit_gru__historical_capacity__tune_branch__filter_joint__s101__lr0p003/continuation.pt'
assert sha(checkpoint)=='fa1993331b1ae4c35328ba7c3c928045452f0d4755ac35461450f287720f9589'
record={'status':'corrected_factor_deployment_no_submission_read_only_probe','checked_at_beijing':datetime.datetime.now(datetime.timezone(datetime.timedelta(hours=8))).isoformat(),
 'root':str(root),'prior_root':str(old),'root_exists':root.exists(),'submission_attempt_exists':(root/'records/diagnostic_submission_attempt.json').exists(),
 'submission_response_exists':(root/'records/diagnostic_submission_response.json').exists(),'scheduler_jobs_exists':(root/'records/scheduler_jobs.json').exists(),
 'matching_active_jobs':matching,'actual_prior_accounting':terminal[0],'prior_error':error,'prior_error_sha256':sha(error_path),
 'source_checkpoint_sha256':sha(checkpoint),'no_corrected_submission_proven':not root.exists() and not matching,
 'queue':queue,'accounting':accounting,'new_jobs_submitted':0,'scheduler_mutated':False,'evaluation_values_read':False,'formal_epochs_added':0}
print(json.dumps(record,sort_keys=True))
PY
