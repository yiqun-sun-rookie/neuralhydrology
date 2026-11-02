#!/usr/bin/env bash
set -eo pipefail
python3 - <<'PRESERVE_GRU_GRADIENT_FAILURE'
import datetime,fcntl,hashlib,json,socket,subprocess,traceback
from pathlib import Path
root=Path('/data1/home/sunyiq/zhenjiang_complete_comparison_fixed200_20261019_003/sqrt_gru_recovery');case='explicit_gru__historical_capacity';job='254778';expected=json.loads('{"explicit_gru__historical_capacity__tune_branch__encoder_fixed__s101__lr0p0003": {"anchor_sha256": "5550be2ad8d7db9b3cae78bed3f29d0ff1f312528a298b3b30d3090bd370d11c", "checkpoint_sha256": "108e6874fc4cbf2fcd39b8c4f849b110893628e29baacea35486338ec49360e4", "completed_epochs": 142, "event": {"anchor_sha256": "5550be2ad8d7db9b3cae78bed3f29d0ff1f312528a298b3b30d3090bd370d11c", "checkpoint_sha256": "108e6874fc4cbf2fcd39b8c4f849b110893628e29baacea35486338ec49360e4", "completed_epochs": 142, "history_sha256": "a4409407d741a7c1bbdd6145dfde3e3fdfc9e57e5645e0b37b5a39bffcaee7a6", "previous_checkpoint_sha256": "0b57b13e1e3e07efcf5510c87e6eb43659fb4d13f6f8cac84279a60f5aaab619", "previous_epochs": 141, "previous_event_sha256": "29b19da4d3d91a53d42e3d7d57d319c381ec8d00fd4abaedcbd1c283e69fabc8", "schema": "complete-epoch-transition-v1"}, "failure": {"epochs_completed": 142, "evidence": {}, "reason": "zero or subnormal gradient needs separate underflow diagnosis", "status": "failed", "type": "FloatingPointError"}}, "explicit_gru__historical_capacity__tune_branch__encoder_fixed__s101__lr0p001": {"anchor_sha256": "4ade17fd33699559371783b0c24aaceab612365c441379816b8c3400940307e1", "checkpoint_sha256": "a92d8100c60de91bd398343897e38565340418d6ac51f14797025a08ac24961d", "completed_epochs": 142, "event": {"anchor_sha256": "4ade17fd33699559371783b0c24aaceab612365c441379816b8c3400940307e1", "checkpoint_sha256": "a92d8100c60de91bd398343897e38565340418d6ac51f14797025a08ac24961d", "completed_epochs": 142, "history_sha256": "6e2253f71c894f1d07e811c002bd0ef2defa2ada699ee429b22bf19f8201a5ce", "previous_checkpoint_sha256": "020d343e1269611a80446c3c7c45802f2ca351a67fca702cb7d3c9ddc370aeb5", "previous_epochs": 141, "previous_event_sha256": "b1f6b85b150cb64a2f0364c95c0d87bd7ef84b3511c5f737257eaa30d82b86f1", "schema": "complete-epoch-transition-v1"}, "failure": {"epochs_completed": 142, "evidence": {}, "reason": "zero or subnormal gradient needs separate underflow diagnosis", "status": "failed", "type": "FloatingPointError"}}, "explicit_gru__historical_capacity__tune_branch__encoder_fixed__s101__lr0p003": {"anchor_sha256": "11856601a76b3eb8c78665ea07880d1ea9756c81e452abbc10b8f0941ca26205", "checkpoint_sha256": "deb038ce18d40a64871336aa892f322143716f759fb5cf4bb03bf008cae67faf", "completed_epochs": 142, "event": {"anchor_sha256": "11856601a76b3eb8c78665ea07880d1ea9756c81e452abbc10b8f0941ca26205", "checkpoint_sha256": "deb038ce18d40a64871336aa892f322143716f759fb5cf4bb03bf008cae67faf", "completed_epochs": 142, "history_sha256": "a242fec65317f33e2dc53d693b75888e678a19f093af1a9199b8eec4a704e826", "previous_checkpoint_sha256": "604ca59650ff05510ab7c2a66b884ed7b876eeb3bb9570d768ff63a2dc8afb19", "previous_epochs": 141, "previous_event_sha256": "190cfb1c24b416ddc82ba722a17473f789e64bade48f75a4585d61ca9bb8d743", "schema": "complete-epoch-transition-v1"}, "failure": {"epochs_completed": 142, "evidence": {}, "reason": "zero or subnormal gradient needs separate underflow diagnosis", "status": "failed", "type": "FloatingPointError"}}, "explicit_gru__historical_capacity__tune_branch__encoder_joint__s101__lr0p0003": {"anchor_sha256": "99e8daef9c657b6bfff7de2ba00e2422d9fe3775c637f478f1f8ff46b36896e3", "checkpoint_sha256": "e5fafbf7696d134173353c50fe2ee0820eb6fced0e4913e04f4971749c746482", "completed_epochs": 142, "event": {"anchor_sha256": "99e8daef9c657b6bfff7de2ba00e2422d9fe3775c637f478f1f8ff46b36896e3", "checkpoint_sha256": "e5fafbf7696d134173353c50fe2ee0820eb6fced0e4913e04f4971749c746482", "completed_epochs": 142, "history_sha256": "95bcd4076d0120d0772ca72056ad2537de72e09ac908ea7d07447a29655eeb20", "previous_checkpoint_sha256": "ca97c039e2186d6648a12f1c90c76f3b27d3678cd47ca27fa83a2fd02d4f5d59", "previous_epochs": 141, "previous_event_sha256": "52217c3905b47f0314e2c4986fd9a74af1e9b7d93999f87ab34aa7419840e2f0", "schema": "complete-epoch-transition-v1"}, "failure": {"epochs_completed": 142, "evidence": {}, "reason": "zero or subnormal gradient needs separate underflow diagnosis", "status": "failed", "type": "FloatingPointError"}}, "explicit_gru__historical_capacity__tune_branch__encoder_joint__s101__lr0p001": {"anchor_sha256": "1099ad456f0a933885265d94a5dd60ec81b5b0de26a01835f257966d33f55610", "checkpoint_sha256": "0feee13d770c5dce7ed7ea67d651530480444c327d85ce952840db10675a0562", "completed_epochs": 142, "event": {"anchor_sha256": "1099ad456f0a933885265d94a5dd60ec81b5b0de26a01835f257966d33f55610", "checkpoint_sha256": "0feee13d770c5dce7ed7ea67d651530480444c327d85ce952840db10675a0562", "completed_epochs": 142, "history_sha256": "1852867b4d30781e783a358027e7aa02e86a37b66fa5e1db42f2bf017fd1fd81", "previous_checkpoint_sha256": "34d689f7f6839fa12409371e5f518c0d91ef29414fcc34b88913ee5e6013d53c", "previous_epochs": 141, "previous_event_sha256": "ec0aaf0a8a262e1931931a4ce3cbefc9c5d12cde47858dbe2f8cf5bd357a231a", "schema": "complete-epoch-transition-v1"}, "failure": {"epochs_completed": 142, "evidence": {}, "reason": "zero or subnormal gradient needs separate underflow diagnosis", "status": "failed", "type": "FloatingPointError"}}, "explicit_gru__historical_capacity__tune_branch__encoder_joint__s101__lr0p003": {"anchor_sha256": "7f913119608a215f93c79f6a8f4954dc23d67f265bd566b0fa911747e27d2b57", "checkpoint_sha256": "53b80be8634a2c77c6dcbad0ddefb2585efa49cda40359d8ae493c6bedc2cd13", "completed_epochs": 142, "event": {"anchor_sha256": "7f913119608a215f93c79f6a8f4954dc23d67f265bd566b0fa911747e27d2b57", "checkpoint_sha256": "53b80be8634a2c77c6dcbad0ddefb2585efa49cda40359d8ae493c6bedc2cd13", "completed_epochs": 142, "history_sha256": "a7683c8630d587e7e3e7303e84e8870b9337ebf25bd0a847261d9cbf31f5d13a", "previous_checkpoint_sha256": "0a38629ef26e5ea352c2b6c6f51886cad44b4adcf1b5c686e5a9356cbe04c7e2", "previous_epochs": 141, "previous_event_sha256": "07f450609ffdd85997bce0854271c31a6fc33e67cf45db847a069b975875e83c", "schema": "complete-epoch-transition-v1"}, "failure": {"epochs_completed": 142, "evidence": {}, "reason": "zero or subnormal gradient needs separate underflow diagnosis", "status": "failed", "type": "FloatingPointError"}}, "explicit_gru__historical_capacity__tune_branch__filter_fixed__s101__lr0p0003": {"anchor_sha256": "a448485c3d5c76a48f2423a9780edc21bc27bbed466c4529adb8d7f47500d15b", "checkpoint_sha256": "60acb0a174a2b8bdc10644c3fbe5861c8e6a4def313f43ff9540fa37e39fb3b0", "completed_epochs": 142, "event": {"anchor_sha256": "a448485c3d5c76a48f2423a9780edc21bc27bbed466c4529adb8d7f47500d15b", "checkpoint_sha256": "60acb0a174a2b8bdc10644c3fbe5861c8e6a4def313f43ff9540fa37e39fb3b0", "completed_epochs": 142, "history_sha256": "39d6f3248597b3bf5f19839b659209020366963512c07e8b69d9d32003392c28", "previous_checkpoint_sha256": "20a826b0ea8cfa3bd316870abba74bd263aa67e876a4d065697bc04f90a28c0a", "previous_epochs": 141, "previous_event_sha256": "ad726beaf70f551ca92a136a76fc302ec39d5ec3f83304720223604d4f29ad6f", "schema": "complete-epoch-transition-v1"}, "failure": {"epochs_completed": 142, "evidence": {}, "reason": "zero or subnormal gradient needs separate underflow diagnosis", "status": "failed", "type": "FloatingPointError"}}, "explicit_gru__historical_capacity__tune_branch__filter_fixed__s101__lr0p001": {"anchor_sha256": "b61be87a8a2c48cdb472ead2faefaf5536522b13959665e4ce079adf3cbd8778", "checkpoint_sha256": "8f175479ca7e867fef9a1ee7012ec35eb1ca37693dd7d242aac0b3c42170efa1", "completed_epochs": 142, "event": {"anchor_sha256": "b61be87a8a2c48cdb472ead2faefaf5536522b13959665e4ce079adf3cbd8778", "checkpoint_sha256": "8f175479ca7e867fef9a1ee7012ec35eb1ca37693dd7d242aac0b3c42170efa1", "completed_epochs": 142, "history_sha256": "db6a0fad8c0049bb20acdcd67d3804204a6d3f4baed7b9e17526671ff7739d1e", "previous_checkpoint_sha256": "312fe0edacc7495cd34f176e7b4485c0dac33c0f20b24b68b5262d910d23538d", "previous_epochs": 141, "previous_event_sha256": "e6b95c2602e4ef1539b6a97a95f33185178956ffd1a4a0e85d49bb5b6a83e0b5", "schema": "complete-epoch-transition-v1"}, "failure": {"epochs_completed": 142, "evidence": {}, "reason": "zero or subnormal gradient needs separate underflow diagnosis", "status": "failed", "type": "FloatingPointError"}}, "explicit_gru__historical_capacity__tune_branch__filter_fixed__s101__lr0p003": {"anchor_sha256": "377845e59485972ab455bde9d5f4175e88650ce631f5f95830ace82c837d85fb", "checkpoint_sha256": "9c50ba03a3375a4e346fc3c01c4f6b2e6d3d58a5a79231a45cb94696c58afd13", "completed_epochs": 142, "event": {"anchor_sha256": "377845e59485972ab455bde9d5f4175e88650ce631f5f95830ace82c837d85fb", "checkpoint_sha256": "9c50ba03a3375a4e346fc3c01c4f6b2e6d3d58a5a79231a45cb94696c58afd13", "completed_epochs": 142, "history_sha256": "38d4ea5e1f47bfded687eabd2b75fce3c9b76d43550508b3175b73b49b76917a", "previous_checkpoint_sha256": "cee6ded5fde1047441ea317b5587586469a074ca74fb86af68a0562b95c2a9ef", "previous_epochs": 141, "previous_event_sha256": "ece10417a02c05cdc009a9935e1618e702e24e20dce8c3d5dedaffc02048b5c6", "schema": "complete-epoch-transition-v1"}, "failure": {"epochs_completed": 142, "evidence": {}, "reason": "zero or subnormal gradient needs separate underflow diagnosis", "status": "failed", "type": "FloatingPointError"}}, "explicit_gru__historical_capacity__tune_branch__filter_joint__s101__lr0p0003": {"anchor_sha256": "668a0e2bce5d56d2ba74fb0c131cb5e03c187fd0f101667042ac7402a0059e23", "checkpoint_sha256": "71a17cd4ccb9669ef86f02bd9a0869ccdf07c0c782cd0e06ab0b4a9708e42580", "completed_epochs": 142, "event": {"anchor_sha256": "668a0e2bce5d56d2ba74fb0c131cb5e03c187fd0f101667042ac7402a0059e23", "checkpoint_sha256": "71a17cd4ccb9669ef86f02bd9a0869ccdf07c0c782cd0e06ab0b4a9708e42580", "completed_epochs": 142, "history_sha256": "5f07a9b2790715166b5f1863b48bc4ef9b1c51f6397dce4036c169fbfb9d9bc9", "previous_checkpoint_sha256": "952340f6aacec6af6cac80938b11cc42379a21870475a1963cf75e4b1535a2c1", "previous_epochs": 141, "previous_event_sha256": "2de9b5f9ab751b4eb1220c44c453100a32d6b4e750bcc058b211f8d9c4ebd5d3", "schema": "complete-epoch-transition-v1"}, "failure": {"epochs_completed": 142, "evidence": {}, "reason": "zero or subnormal gradient needs separate underflow diagnosis", "status": "failed", "type": "FloatingPointError"}}, "explicit_gru__historical_capacity__tune_branch__filter_joint__s101__lr0p001": {"anchor_sha256": "36ceefea026683c616149164178c8f91ecfc1bb6a312a60949310c0de5ada8cb", "checkpoint_sha256": "b0a61eb8cd84f576380c96cec7bd89c05e3a18ec9e3e02c600d7717b4cd6ef40", "completed_epochs": 142, "event": {"anchor_sha256": "36ceefea026683c616149164178c8f91ecfc1bb6a312a60949310c0de5ada8cb", "checkpoint_sha256": "b0a61eb8cd84f576380c96cec7bd89c05e3a18ec9e3e02c600d7717b4cd6ef40", "completed_epochs": 142, "history_sha256": "a913ca05c16a9707bbdf98198d7f37169052ea51190d30e7167cff6556e8bc6e", "previous_checkpoint_sha256": "14c259389ca687bd8c63c82d7e83873ad30eef174a34bb7d4c22ad29048d689d", "previous_epochs": 141, "previous_event_sha256": "1620439f76487fccd0706055081345ef2a904f67099f1e676a68b5760dfd68d3", "schema": "complete-epoch-transition-v1"}, "failure": {"epochs_completed": 142, "evidence": {}, "reason": "zero or subnormal gradient needs separate underflow diagnosis", "status": "failed", "type": "FloatingPointError"}}, "explicit_gru__historical_capacity__tune_branch__filter_joint__s101__lr0p003": {"anchor_sha256": "aa98f6aa23ba4cdfc9b77a681c19acc1985a4ffd8226eb10ab7da9783a167ee7", "checkpoint_sha256": "cf6826ddeb1779633d0154f4fbc779de94b880d9e1a83464b9b469a7cf11a4fe", "completed_epochs": 141, "event": {"anchor_sha256": "aa98f6aa23ba4cdfc9b77a681c19acc1985a4ffd8226eb10ab7da9783a167ee7", "checkpoint_sha256": "cf6826ddeb1779633d0154f4fbc779de94b880d9e1a83464b9b469a7cf11a4fe", "completed_epochs": 141, "history_sha256": "a054642519436c54d6c2dca6bbc69cee6a5a4d64803f4029ebbe6d287c03a35b", "previous_checkpoint_sha256": "91eb68534a8ace8e7f7a9965d92765b8a6e35fac7d3a6d63e96163b606d4e352", "previous_epochs": 140, "previous_event_sha256": "9624ce1eaf7ac1ad52b3597455af869c9a92e9d8068e0b6bfc90ffec53b5400e", "schema": "complete-epoch-transition-v1"}, "failure": {"epochs_completed": 141, "evidence": {}, "reason": "zero or subnormal gradient needs separate underflow diagnosis", "status": "failed", "type": "FloatingPointError"}}}')
record=root/'records'/case;folder=record/'repairs'/('gradient_zero_subnormal_'+job+'_20261102_001')
slurm=Path('/usr/local/globle/softs/slurm/19.05.4.1/bin')
report={'schema':'003-native-gradient-failure-preservation-v1','case':case,'job_id':job,'at_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'host':socket.gethostname(),'root':str(root),'preservation_directory':str(folder),'status':'preservation_not_completed','errors':[],'files':{},'members':{},'training_submitted':False,'scientific_files_changed':False,'failure_markers_removed':False,'checkpoint_tensors_loaded':False,'optimizer_steps':0,'underflow_root_cause_proved':False}
def digest(path):
 h=hashlib.sha256()
 with path.open('rb') as handle:
  for chunk in iter(lambda:handle.read(1024*1024),b''):h.update(chunk)
 return h.hexdigest()
def query(args):
 p=subprocess.run([str(x) for x in args],capture_output=True,text=True,timeout=45)
 value={'command':[str(x) for x in args],'returncode':p.returncode,'stdout':p.stdout,'stderr':p.stderr}
 if p.returncode:raise RuntimeError(json.dumps(value))
 return value
def preserve(source,dest):
 if not source.is_file():return {'source':str(source),'exists':False}
 dest.parent.mkdir(parents=True,exist_ok=True);h=hashlib.sha256();count=0
 with source.open('rb') as inp,dest.open('xb') as out:
  for chunk in iter(lambda:inp.read(1024*1024),b''):out.write(chunk);h.update(chunk);count+=len(chunk)
 assert dest.stat().st_size==source.stat().st_size==count and digest(dest)==h.hexdigest()
 return {'source':str(source),'preserved_copy':str(dest),'bytes':count,'sha256':h.hexdigest(),'copy_verified':True,'exists':True}
created=False
try:
 folder.mkdir(parents=True,exist_ok=False);created=True
 report['queue']=query([slurm/'squeue','-h','-u','sunyiq','-o','%i|%j|%T|%Z|%o'])
 report['same_case_queue_rows']=[line for line in report['queue']['stdout'].splitlines() if case in line or str(root) in line or line.startswith(job+'|')]
 report['accounting']=query([slurm/'sacct','-n','-X','-j',job,'--format=JobID,State,ExitCode,Start,End,NodeList','-P'])
 rows=[line.split('|') for line in report['accounting']['stdout'].splitlines() if line.startswith(job+'|')]
 assert len(rows)==1 and rows[0][1:3]==['FAILED','1:0'] and not report['same_case_queue_rows']
 assert str(json.loads((root/'records/scheduler_jobs.json').read_bytes())[case])==job
 with (record/'writer.lock').open('rb') as writer:
  fcntl.flock(writer,fcntl.LOCK_EX|fcntl.LOCK_NB);report['writer_lock_exclusively_held_during_preservation']=True
  auth=root/'records/authorization.json';assert digest(auth)=='1b38567991e550ac530f3dbef148b3e347db81a8f1eb71272aa47a9fd8937902'
  assert digest(root/'hpc/run_fixed200_case.py')=='4157613be568d36e5dc322b2f39da81434d30dd7eba9c7491252e209244168ba'
  assert digest(root/'configs/protocol-v3.json')=='ca41a57d0d19c97090f7a25a55f09bf733429a027024b00e07ca9ab7caa4f90a'
  for exp,old in expected.items():
   run=root/'runs'/exp;head=json.loads((run/'checkpoint_head.json').read_bytes());anchor=run/'continuation_anchor.json';event=run/'checkpoint_events'/(head['checkpoint_sha256'][:16]+'.json')
   assert head['completed_epochs']==old['completed_epochs'] and head['checkpoint_sha256']==old['checkpoint_sha256'] and head['anchor_sha256']==old['anchor_sha256']==digest(anchor)
   assert json.loads(event.read_bytes())==old['event'] and json.loads((run/'failure.json').read_bytes())==old['failure']
   entries={}
   for name in ['continuation.pt','checkpoint_head.json','continuation_anchor.json','config.json','migration_source.json','metrics.json','failure.json','first_optimizer_step.json']:
    entries[name]=preserve(run/name,folder/'members'/exp/name)
   entries['latest_checkpoint_event']=preserve(event,folder/'members'/exp/'latest_checkpoint_event.json')
   assert entries['continuation.pt']['exists'] and entries['continuation.pt']['sha256']==head['checkpoint_sha256']
   report['members'][exp]={'head':head,'anchor_sha256':old['anchor_sha256'],'failure':old['failure'],'files':entries,'complete_model_Adam_history_and_config_preserved_as_opaque_original_bytes':True}
  sources={'job_log':root/('logs/zj003_'+case+'_'+job+'.out'),'authorization':auth,'scheduler_jobs':root/'records/scheduler_jobs.json','runtime_binding':record/('runtime_binding_'+job+'.json'),'progress':record/'progress.json','migration_manifest':record/'migration_manifest.json','activation_starting_members':record/'activation_starting_members.json','tune_branch_configs':record/'tune_branch_group_configs.json','foundation_outcome':record/'final_foundation_group_outcome.json','external_foundation_reservation':record/'external_final_foundation_20261028.json','protocol':root/'configs/protocol-v3.json','registry':root/'configs/registry-v3.json','wrapper':root/'hpc/run_fixed200_case.py','submitter':root/'hpc/submit_fixed200_continuation.py','scheduler_template':root/'hpc/fixed200_case.slurm','training_source':root/'src/training.py','gradient_recovery_source':root/'src/gradient_recovery.py','runtime_source':root/'src/runtime.py','case_entry':root/'scripts/train_supercomputer_case.py'}
  for label,path in sources.items():report['files'][label]=preserve(path,folder/'original_files'/(label+'.preserved'))
  assert report['files']['training_source']['sha256']=='a7e62dc2aafb87c45a98b4062f90133c554985d3e9185401df8f07d8e24e335c' and report['files']['gradient_recovery_source']['sha256']=='7dffed576f32d91d51d8457d1315fa26d57c096946802091271e7d516646421e'
  report['all_12_committed_heads_unchanged_from_native_failure_snapshot']=len(report['members'])==len(expected)==12
  report['all_12_complete_checkpoint_copies_match_committed_head_sha256']=True
  report['status']='native_failure_and_complete_model_Adam_checkpoint_bytes_preserved_no_training_or_gate_change'
except Exception as exc:
 report['errors'].append({'type':type(exc).__name__,'message':str(exc),'traceback':traceback.format_exc()});report['status']='preservation_incomplete_requires_readonly_reconciliation_no_replay'
finally:
 if created:
  with (folder/'DIAGNOSIS.json').open('x',encoding='utf-8') as out:json.dump(report,out,sort_keys=True,indent=2);out.write(chr(10))
 print('GRU_GRADIENT_FAILURE_PRESERVATION_JSON '+json.dumps(report,sort_keys=True),flush=True)

PRESERVE_GRU_GRADIENT_FAILURE

#!/usr/bin/env bash
set -eo pipefail
python3 - <<'READ_FIXED200_003'
"""Read fixed-200 allocation and committed-epoch evidence without loading tensors.

Example on HPC: python -B read_status.py
Reads the two activated cases, checkpoint heads/events and small record files.
Prints a status snapshot only; no scheduler submission or source writes.
"""
import datetime
import hashlib
import json
from pathlib import Path
import subprocess

ROOT = Path('/data1/home/sunyiq/zhenjiang_complete_comparison_fixed200_20261019_003')
SLURM = Path('/usr/local/globle/softs/slurm/19.05.4.1/bin')
CASES = {'legacy_lstm__historical_capacity': 'base',
         'explicit_gru__historical_capacity': 'sqrt_gru_recovery'}


def read(path):
    return json.loads(path.read_bytes())


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def query(command):
    result = subprocess.run(list(map(str, command)), capture_output=True, text=True, timeout=45)
    return {'command': list(map(str, command)), 'returncode': result.returncode,
            'stdout': result.stdout, 'stderr': result.stderr}


def final_stage_metadata(runtime, record, case, row):
    """Read bounded final-stage records and committed heads; never load tensors."""
    result = {'group_outcomes': {}, 'physical_members': {}, 'aliases': {},
              'checkpoints_loaded': False, 'scientific_files_changed': False}
    for suffix in ('tune_branch_group', 'final_foundation_group', 'all_final_branches_group'):
        path = record / (suffix + '_outcome.json')
        if not path.exists():
            continue
        outcome = read(path)
        seal = outcome['seal']
        result['group_outcomes'][suffix] = {
            'path': str(path), 'sha256': sha(path),
            'seal': {key: seal[key] for key in ('group_id', 'member_ids', 'epochs',
                     'checkpoint_hashes', 'status', 'budget_final', 'evidence_sha256')},
            'members': {name: {key: value.get(key) for key in ('case', 'seed', 'method',
                'type', 'epochs', 'budget_final', 'best_epoch', 'checkpoint_sha256',
                'checkpoint_path', 'learning_rate', 'normalization_hash', 'whitening_hash',
                'initializer_hash', 'device_identity')} for name, value in outcome['members'].items()}}
    path = record / 'aliases_before_final_training.json'
    if path.exists():
        aliases = read(path)
        result['alias_record_sha256'] = sha(path)
        result['effective_configs_sha256_before_aliases'] = aliases['effective_configs_sha256']
        result['aliases'] = {name: target for name, target in aliases['aliases'].items()
                             if name.startswith(case + '__')}
    path = record / 'all_final_branches_group_configs.json'
    if not path.exists():
        return result
    configs = read(path)
    result['physical_configs_sha256'] = sha(path)
    for name, config in configs.items():
        assert name.startswith(case + '__') and name not in result['aliases']
        run = config['registration']
        effective = config['effective_config']
        folder = runtime / 'runs' / name
        item = {'method': run['method'], 'type': run['type'], 'seed': run['seed'],
                'learning_rate': effective['learning_rate'],
                'parent_run_id': effective['parent_run_id'], 'parent_hash': effective['parent_hash'],
                'folder_exists': folder.exists(), 'continuation_file_exists': (folder / 'continuation.pt').is_file()}
        config_path = folder / 'config.json'
        if config_path.exists():
            item['config_sha256'] = sha(config_path)
            item['frozen_config_matches'] = read(config_path) == config
        head_path = folder / 'checkpoint_head.json'
        if head_path.exists():
            head = read(head_path)
            assert 0 <= head['completed_epochs'] <= 200
            item['head'] = head
            event_path = folder / 'checkpoint_events' / (head['checkpoint_sha256'][:16] + '.json')
            if head['completed_epochs'] > 0 and event_path.exists():
                event = read(event_path)
                assert event['completed_epochs'] == head['completed_epochs']
                assert event['checkpoint_sha256'] == head['checkpoint_sha256']
                assert event['previous_epochs'] == head['completed_epochs'] - 1
                item['latest_complete_epoch_event'] = event
            anchor_path = folder / 'continuation_anchor.json'
            if anchor_path.exists():
                item['anchor_sha256'] = sha(anchor_path)
                item['anchor'] = read(anchor_path)
                item['head_anchor_matches'] = head.get('anchor_sha256') == item['anchor_sha256']
        step_path = folder / 'first_optimizer_step.json'
        if step_path.exists():
            step = read(step_path)
            item['first_optimizer_step'] = {key: step.get(key) for key in
                ('status', 'epoch', 'training_batch_size', 'method', 'device_identity')}
        failure_path = folder / 'failure.json'
        if failure_path.exists():
            row['failure_records'][name] = read(failure_path)
        result['physical_members'][name] = item
    result['physical_member_count'] = len(configs)
    result['logical_member_count'] = len(configs) + len(result['aliases'])
    result['complete200_physical_members'] = sum(
        value.get('head', {}).get('completed_epochs') == 200 for value in result['physical_members'].values())
    result['complete_member_epochs'] = sum(
        value.get('head', {}).get('completed_epochs', 0) for value in result['physical_members'].values())
    result['all_alias_targets_are_physical'] = all(target in configs for target in result['aliases'].values())
    return result


report = {'schema': 'fixed200-activation-status-v1', 'root': str(ROOT),
          'checked_at_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
          'checkpoints_loaded': False, 'evaluation_values_read': False, 'cases': {}, 'errors': []}
report['queue'] = query([SLURM / 'squeue', '-h', '-u', 'sunyiq', '-o', '%i|%j|%T|%Z|%e|%l|%N|%R'])
for case, variant in CASES.items():
    runtime = ROOT / variant
    record = runtime / 'records' / case
    try:
        initial = read(record / 'activation_starting_members.json')
        job = str(read(runtime / 'records/scheduler_jobs.json')[case])
        auth = read(runtime / 'records/authorization.json')
        row = {'case': case, 'root': str(runtime), 'job_id': job,
               'authorization_sha256': sha(runtime / 'records/authorization.json'),
               'authorization': auth, 'migration_manifest': read(record / 'migration_manifest.json'),
               'data_preparation_complete': read(runtime / 'records/data_preparation_complete.json'),
               'scheduler_script': (runtime / 'hpc/fixed200_case.slurm').read_text(),
               'device_identity': auth['device_identity'], 'members': {},
               'queue_rows': [line for line in report['queue']['stdout'].splitlines() if line.startswith(job + '|')],
               'failure_records': {}}
        allocation = record / ('runtime_binding_' + job + '.json')
        if allocation.exists():
            row['runtime_binding'] = read(allocation)
            assert row['runtime_binding']['device_identity'] == auth['device_identity']
        for name in ('progress.json', 'training_complete.json', 'selected_rates_2021.json',
                     'scheduler_slice_end_' + job + '.json', 'startup_path_recovery_' + job + '.json',
                     'submission_context_repair.confirmed.json'):
            if (record / name).exists():
                row[name] = read(record / name)
        source_outcome = record / 'tune_foundation_group_outcome.json'
        if source_outcome.exists():
            source = read(source_outcome)
            row['tuning_foundation_source'] = {'seal_epochs': source['seal']['epochs'],
                'members': {name: {'epochs': value['epochs'], 'best_epoch': value['best_epoch'],
                           'checkpoint_sha256': value['checkpoint_sha256']}
                            for name, value in source['members'].items()}}
            assert row['tuning_foundation_source']['seal_epochs'] == 400
        for member, start in initial.items():
            folder = runtime / 'runs' / member
            head = read(folder / 'checkpoint_head.json')
            anchor = read(folder / 'continuation_anchor.json')
            assert anchor['initial_checkpoint_sha256'] == start['checkpoint_sha256']
            assert anchor['initial_epochs'] == start['completed_epochs']
            assert sha(folder / 'config.json') == start['config_sha256']
            assert sha(folder / 'migration_source.json') == start['receipt_sha256']
            n = head['completed_epochs']
            assert start['completed_epochs'] <= n <= 200
            item = {'initial_epochs': start['completed_epochs'], 'completed_epochs': n,
                    'new_complete_epochs': n - start['completed_epochs'],
                    'checkpoint_sha256_from_committed_head': head['checkpoint_sha256'],
                    'initial_identity_and_config_preserved': True}
            if n > start['completed_epochs']:
                event = read(folder / 'checkpoint_events' / (head['checkpoint_sha256'][:16] + '.json'))
                assert event['checkpoint_sha256'] == head['checkpoint_sha256']
                assert event['completed_epochs'] == n and event['previous_epochs'] == n - 1
                assert event['anchor_sha256'] == head['anchor_sha256'] == sha(folder / 'continuation_anchor.json')
                item['new_epoch_event'] = event
            if (folder / 'failure.json').exists():
                row['failure_records'][member] = read(folder / 'failure.json')
            row['members'][member] = item
        row['new_complete_member_epochs'] = sum(v['new_complete_epochs'] for v in row['members'].values())
        row['members_with_new_complete_epoch'] = sum(v['new_complete_epochs'] > 0 for v in row['members'].values())
        row['tune_branch_200_complete_members'] = sum(v['completed_epochs'] == 200 for v in row['members'].values())
        row['actual_training_progress_confirmed'] = bool(row.get('runtime_binding') and row['new_complete_member_epochs'] > 0)
        try:
            row['final_stage'] = final_stage_metadata(runtime, record, case, row)
        except Exception as error:
            row['final_stage_metadata_error'] = {'type': type(error).__name__, 'message': str(error)}
        row['logs'] = []
        for path in (runtime / 'logs').glob('*_' + job + '.out'):
            with path.open('rb') as handle:
                handle.seek(max(0, path.stat().st_size - 7000))
                row['logs'].append({'path': str(path), 'tail': handle.read().decode('utf-8', errors='replace')})
        report['cases'][case] = row
    except Exception as error:
        report['errors'].append({'case': case, 'type': type(error).__name__, 'message': str(error)})
jobs = [v['job_id'] for v in report['cases'].values()]
if jobs:
    report['accounting'] = query([SLURM / 'sacct', '-n', '-X', '-j', ','.join(jobs),
                                  '--format=JobID,State,ExitCode,Start,End,NodeList', '-P'])
report['summary'] = {'cases': len(report['cases']),
    'cases_with_new_complete_epoch': sum(v['actual_training_progress_confirmed'] for v in report['cases'].values()),
    'new_complete_member_epochs': sum(v['new_complete_member_epochs'] for v in report['cases'].values()),
    'members_with_new_complete_epoch': sum(v['members_with_new_complete_epoch'] for v in report['cases'].values()),
    'tune_branch_200_complete_members': sum(v['tune_branch_200_complete_members'] for v in report['cases'].values()),
    'failure_files': sum(len(v['failure_records']) for v in report['cases'].values())}
print(json.dumps(report, sort_keys=True), flush=True)

READ_FIXED200_003
