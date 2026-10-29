#!/usr/bin/env bash
set -eo pipefail
source /data1/home/sunyiq/miniconda3/etc/profile.d/conda.sh
conda activate nh_final
cd /data1/home/sunyiq/zhenjiang_complete_comparison_fixed200_20261019_003/sqrt_gru_recovery
python -B - <<'ONE_SCOPED_STARTUP_PATH_RECOVERY'
EXPECTED = {'explicit_gru__historical_capacity__tune_branch__encoder_fixed__s101__lr0p0003': {'completed_epochs': 114, 'checkpoint_sha256': 'a3d6114438379fa6bb8bb9a3d6d601348d489f030115a6562e90d7241b41e02e', 'anchor_sha256': '5550be2ad8d7db9b3cae78bed3f29d0ff1f312528a298b3b30d3090bd370d11c'}, 'explicit_gru__historical_capacity__tune_branch__encoder_fixed__s101__lr0p001': {'completed_epochs': 114, 'checkpoint_sha256': '26e4d2865461bba244e60101e5ab925dd40bb5cb8716284e565aa4425bca87af', 'anchor_sha256': '4ade17fd33699559371783b0c24aaceab612365c441379816b8c3400940307e1'}, 'explicit_gru__historical_capacity__tune_branch__encoder_fixed__s101__lr0p003': {'completed_epochs': 114, 'checkpoint_sha256': '3e3b075174c434f0079495d1b0a841c552c38b650407a7c1a49679e3e6003889', 'anchor_sha256': '11856601a76b3eb8c78665ea07880d1ea9756c81e452abbc10b8f0941ca26205'}, 'explicit_gru__historical_capacity__tune_branch__encoder_joint__s101__lr0p0003': {'completed_epochs': 114, 'checkpoint_sha256': '6798e9c1cef0a9b686b51db6b27e58b82d4dc314efc90f25c50558f30e7a6d48', 'anchor_sha256': '99e8daef9c657b6bfff7de2ba00e2422d9fe3775c637f478f1f8ff46b36896e3'}, 'explicit_gru__historical_capacity__tune_branch__encoder_joint__s101__lr0p001': {'completed_epochs': 114, 'checkpoint_sha256': '1e841b45f1d448bd458396bd65d111b454f1757d687970f6f6edd299cb85025c', 'anchor_sha256': '1099ad456f0a933885265d94a5dd60ec81b5b0de26a01835f257966d33f55610'}, 'explicit_gru__historical_capacity__tune_branch__encoder_joint__s101__lr0p003': {'completed_epochs': 114, 'checkpoint_sha256': '902e04390ad7ed30978f7dbaee547772a3451e7bf03658f405afad9ebeda07ab', 'anchor_sha256': '7f913119608a215f93c79f6a8f4954dc23d67f265bd566b0fa911747e27d2b57'}, 'explicit_gru__historical_capacity__tune_branch__filter_fixed__s101__lr0p0003': {'completed_epochs': 114, 'checkpoint_sha256': 'be8f6dccfb37040ec9394123b864476999ad1d47effd4aed6f4ad6bf910622e8', 'anchor_sha256': 'a448485c3d5c76a48f2423a9780edc21bc27bbed466c4529adb8d7f47500d15b'}, 'explicit_gru__historical_capacity__tune_branch__filter_fixed__s101__lr0p001': {'completed_epochs': 114, 'checkpoint_sha256': '65e7b9c5c0ca5854651a34d0c34bc56bb7fc6054250b1e4112ccf16f87773a1f', 'anchor_sha256': 'b61be87a8a2c48cdb472ead2faefaf5536522b13959665e4ce079adf3cbd8778'}, 'explicit_gru__historical_capacity__tune_branch__filter_fixed__s101__lr0p003': {'completed_epochs': 113, 'checkpoint_sha256': 'ed9c2452dc68aed0fa065db8883e71703a896b04ab90ad44049924681ff704c1', 'anchor_sha256': '377845e59485972ab455bde9d5f4175e88650ce631f5f95830ace82c837d85fb'}, 'explicit_gru__historical_capacity__tune_branch__filter_joint__s101__lr0p0003': {'completed_epochs': 113, 'checkpoint_sha256': 'eb5df930b6df782f0c0db6c6474db23b893c5e9c5acfb6de244f3edeae447a84', 'anchor_sha256': '668a0e2bce5d56d2ba74fb0c131cb5e03c187fd0f101667042ac7402a0059e23'}, 'explicit_gru__historical_capacity__tune_branch__filter_joint__s101__lr0p001': {'completed_epochs': 113, 'checkpoint_sha256': 'b7049cd727db7b651c7a2244aeb1304804847e341d33f8ed3e98c27371e9b694', 'anchor_sha256': '36ceefea026683c616149164178c8f91ecfc1bb6a312a60949310c0de5ada8cb'}, 'explicit_gru__historical_capacity__tune_branch__filter_joint__s101__lr0p003': {'completed_epochs': 113, 'checkpoint_sha256': 'b6daabecf1d1920e45e79ac85c07c3e9a178e83ae7ab807e39f3982a4408598b', 'anchor_sha256': 'aa98f6aa23ba4cdfc9b77a681c19acc1985a4ffd8226eb10ab7da9783a167ee7'}}
BOOTSTRAP = '"""Check the original GRU guard path on its allocated node before execution.\n\nEmbedded once in a versioned recovery batch script. Payload constants are\ninserted by the original-channel recovery helper. No model or Adam is loaded.\n"""\nimport base64\nimport datetime\nimport fcntl\nimport hashlib\nimport json\nimport os\nfrom pathlib import Path\nimport subprocess\n\n\ndef main():\n    root = Path(\'/data1/home/sunyiq/zhenjiang_complete_comparison_fixed200_20261019_003/sqrt_gru_recovery\')\n    case = \'explicit_gru__historical_capacity\'\n    record = root / \'records\' / case\n    job = os.environ[\'SLURM_JOB_ID\']\n    wrapper = root / \'hpc/run_fixed200_case.py\'\n    expected_sha = \'4157613be568d36e5dc322b2f39da81434d30dd7eba9c7491252e209244168ba\'\n    payload = base64.b64decode(GUARD_B64)\n    assert hashlib.sha256(payload).hexdigest() == expected_sha\n    value = {\'at_utc\': datetime.datetime.now(datetime.timezone.utc).isoformat(),\n             \'case\': case, \'job_id\': job, \'previous_job\': \'252379\',\n             \'wrapper_path\': str(wrapper), \'wrapper_existed_before\': wrapper.exists(),\n             \'scientific_code_changed\': False, \'checkpoint_tensors_loaded\': False}\n    print(\'GRU_STARTUP_PATH_PREFLIGHT_JSON \' + json.dumps(value), flush=True)\n    queue = subprocess.run([\n        \'/usr/local/globle/softs/slurm/19.05.4.1/bin/squeue\', \'-h\', \'-u\', \'sunyiq\',\n        \'-o\', \'%i|%T|%Z|%j\'], capture_output=True, text=True, check=True, timeout=45)\n    own = [row.split(\'|\') for row in queue.stdout.splitlines()\n           if case in row or str(root) in row or row.startswith(job + \'|\')]\n    assert len(own) == 1 and own[0][0] == job and own[0][1] == \'RUNNING\'\n    with (record / \'writer.lock\').open(\'a\') as lock:\n        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)\n        for member, old in EXPECTED.items():\n            run = root / \'runs\' / member\n            head = json.loads((run / \'checkpoint_head.json\').read_bytes())\n            assert head[\'completed_epochs\'] == old[\'completed_epochs\']\n            assert head[\'checkpoint_sha256\'] == old[\'checkpoint_sha256\']\n            assert head[\'anchor_sha256\'] == old[\'anchor_sha256\']\n            assert hashlib.sha256((run / \'continuation_anchor.json\').read_bytes()).hexdigest() == old[\'anchor_sha256\']\n            assert (run / \'continuation.pt\').is_file() and not (run / \'failure.json\').exists()\n        assert not wrapper.is_symlink()\n        restored = False\n        if not wrapper.exists():\n            # Exclusive creation keeps any concurrently visible original intact.\n            try:\n                with wrapper.open(\'xb\') as handle:\n                    handle.write(payload)\n                    handle.flush()\n                    os.fsync(handle.fileno())\n                restored = True\n            except FileExistsError:\n                pass\n        assert hashlib.sha256(wrapper.read_bytes()).hexdigest() == expected_sha\n        value.update(status=\'original_guard_path_verified_on_allocated_node\',\n                     wrapper_sha256=expected_sha, exact_guard_restored_if_absent=restored,\n                     all_12_checkpoint_heads_unchanged=True, model_or_Adam_reset=False)\n        path = record / (\'startup_path_recovery_\' + job + \'.json\')\n        with path.open(\'x\') as handle:\n            json.dump(value, handle, sort_keys=True, indent=2)\n            handle.write(\'\\n\')\n        print(\'GRU_STARTUP_PATH_VERIFIED_JSON \' + json.dumps(value), flush=True)\n\n\nif __name__ == \'__main__\':\n    main()\n'
"""Submit one scoped recovery for the proven pre-Python path failure.

Run only through the generated original-channel shell command. Its frozen
EXPECTED and BOOTSTRAP constants are inserted before main is called. Preserves
the original scheduler template and healthy-continuation submitter unchanged.
"""
import base64
import datetime
import fcntl
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path('/data1/home/sunyiq/zhenjiang_complete_comparison_fixed200_20261019_003/sqrt_gru_recovery')
CASE = 'explicit_gru__historical_capacity'
PREVIOUS = '252379'
KEY = 'startup_path_recovery_after_252379_20261029_001'
SLURM = Path('/usr/local/globle/softs/slurm/19.05.4.1/bin')
GUARD_SHA = '4157613be568d36e5dc322b2f39da81434d30dd7eba9c7491252e209244168ba'


def read(path):
    return json.loads(path.read_bytes())


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def new(path, value):
    with path.open('x') as handle:
        json.dump(value, handle, sort_keys=True, indent=2)
        handle.write('\n')


def query(command):
    result = subprocess.run([str(x) for x in command], cwd=str(ROOT),
                            capture_output=True, text=True, timeout=60)
    value = {'command': [str(x) for x in command], 'returncode': result.returncode,
             'stdout': result.stdout, 'stderr': result.stderr}
    if result.returncode:
        raise RuntimeError(json.dumps(value))
    return value


def main():
    record = ROOT / 'records' / CASE
    auth = read(ROOT / 'records/authorization.json')
    assert CASE in auth['allowed_cases'] and auth['authority']['technical_recovery']
    assert auth['authority']['formal_training']
    sys.path.insert(0, str(ROOT))
    from src.scheduler import code_identity
    assert code_identity(ROOT) == auth['code_hash']
    assert sha((ROOT / 'configs/protocol-v3.json').read_bytes()) == auth['protocol_sha256']
    jobs_path = ROOT / 'records/scheduler_jobs.json'
    jobs = read(jobs_path)
    assert str(jobs[CASE]) == PREVIOUS
    diagnosis = read(record / 'repairs/missing_wrapper_252379_20261029_001/DIAGNOSIS.json')
    assert diagnosis['all_heads_match_pre_submission_baseline']
    assert diagnosis['files']['wrapper']['sha256'] == GUARD_SHA
    assert diagnosis['files']['admitted_guard_source']['sha256'] == GUARD_SHA
    assert not (record / ('runtime_binding_' + PREVIOUS + '.json')).exists()
    assert not list((ROOT / 'runs').glob('*/failure.json'))
    assert not list(record.glob('external_stage_wait_' + PREVIOUS + '.json'))
    queue = query([SLURM / 'squeue', '-h', '-u', 'sunyiq', '-o', '%i|%j|%T|%Z|%o'])
    assert not [row for row in queue['stdout'].splitlines()
                if CASE in row or str(ROOT) in row or row.startswith(PREVIOUS + '|')]
    accounting = query([SLURM / 'sacct', '-n', '-X', '-j', PREVIOUS,
                        '--format=JobID,State,ExitCode,Start,End,NodeList', '-P'])
    rows = [row.split('|') for row in accounting['stdout'].splitlines()
            if row.startswith(PREVIOUS + '|')]
    assert len(rows) == 1 and rows[0][1:3] == ['FAILED', '2:0']
    log = ROOT / ('logs/zj003_' + CASE + '_' + PREVIOUS + '.out')
    assert sha(log.read_bytes()) == diagnosis['files']['job_log']['sha256']
    assert b"can't open file" in log.read_bytes() and b'hpc/run_fixed200_case.py' in log.read_bytes()
    template = ROOT / 'hpc/fixed200_case.slurm'
    original_script = template.read_bytes()
    assert sha(original_script) == auth['scheduler']['script_sha256']
    assert sha((ROOT / 'hpc/submit_fixed200_continuation.py').read_bytes()) == '933796be13b8a8eff99a59e512752c66591031bf7c9af8fa17dbb384e9fec9de'
    guard = ROOT.parent / 'external_gru_foundation_20261028_001/run_fixed200_case_external_guard.py'
    guard_raw = guard.read_bytes()
    assert sha(guard_raw) == GUARD_SHA == sha((ROOT / 'hpc/run_fixed200_case.py').read_bytes())
    reservation = read(record / 'external_final_foundation_20261028.json')
    assert reservation['assignments'] == {'cloud': [17, 29], 'g15': [43, 61, 89]}
    registry = read(ROOT / 'configs/registry-v3.json')
    finals = [r for r in registry['runs'] if r['budget_group'] == CASE + '__final_foundation_group']
    assert sorted(r['seed'] for r in finals) == [17, 29, 43, 61, 89]
    assert all(not (ROOT / 'runs' / r['exp_id']).exists() for r in finals)
    with (record / 'writer.lock').open('a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        for member, old in EXPECTED.items():
            run = ROOT / 'runs' / member
            head = read(run / 'checkpoint_head.json')
            assert head['completed_epochs'] == old['completed_epochs']
            assert head['checkpoint_sha256'] == old['checkpoint_sha256']
            assert head['anchor_sha256'] == old['anchor_sha256'] == sha((run / 'continuation_anchor.json').read_bytes())
            assert (run / 'continuation.pt').is_file() and (run / 'continuation.pt').stat().st_size > 0
        folder = record / 'repairs' / KEY
        folder.mkdir(exist_ok=False)
        for label, path in {'failed_job_log': log, 'original_template': template,
                            'admitted_wrapper': ROOT / 'hpc/run_fixed200_case.py',
                            'original_submitter': ROOT / 'hpc/submit_fixed200_continuation.py',
                            'scheduler_jobs_before': jobs_path,
                            'authorization': ROOT / 'records/authorization.json'}.items():
            (folder / (label + '.preserved')).write_bytes(path.read_bytes())
        new(folder / 'checkpoint_baseline.json', EXPECTED)
        bootstrap = ('EXPECTED = ' + repr(EXPECTED) + '\nGUARD_B64 = ' +
                     repr(base64.b64encode(guard_raw).decode()) + '\n' + BOOTSTRAP)
        original_text = original_script.decode()
        invocation = 'python -B -u hpc/run_fixed200_case.py --case ' + CASE
        assert original_text.count(invocation) == 1
        insertion = "python -B - <<'VERIFY_EXACT_GUARD_PATH'\n" + bootstrap + "\nVERIFY_EXACT_GUARD_PATH\n"
        new_text = original_text.replace(invocation, insertion + invocation)
        new_script = ROOT / 'hpc' / ('fixed200_case_' + KEY + '.slurm')
        with new_script.open('x') as handle:
            handle.write(new_text)
        attempt = {'schema': '003-scoped-startup-path-recovery-v1',
                   'at_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
                   'case': CASE, 'previous_job': PREVIOUS, 'queue': queue,
                   'accounting': accounting, 'original_template_sha256': sha(original_script),
                   'recovery_script': str(new_script), 'recovery_script_sha256': sha(new_script.read_bytes()),
                   'guard_sha256': GUARD_SHA, 'checkpoint_baseline': str(folder / 'checkpoint_baseline.json'),
                   'scientific_code_changed': False, 'model_or_Adam_reset': False,
                   'original_healthy_termination_gate_changed': False,
                   'recovery_verified': False}
        new(folder / 'submission.attempt.json', attempt)
        # The exclusive attempt is durable before submission. The compute-side
        # preflight must acquire this same writer lock and see only its own job.
        fcntl.flock(lock, fcntl.LOCK_UN)
        try:
            response = query([SLURM / 'xbatch', new_script])
        except Exception as exc:
            new(folder / 'submission.response.json', {'status': 'uncertain_reconcile_readonly', 'error': repr(exc)})
            raise
        new(folder / 'submission.response.json', response)
        match = re.fullmatch(r'Submitted batch job ([0-9]+)\s*', response['stdout'])
        assert match, 'uncertain submission; do not replay'
        jobs[CASE] = match.group(1)
        temporary = jobs_path.with_name('scheduler_jobs.' + KEY + '.tmp')
        new(temporary, jobs)
        temporary.replace(jobs_path)
        result = dict(attempt, status='scoped_startup_path_recovery_submitted', job_id=match.group(1),
                      native_submission_confirmed=True, new_complete_epochs_confirmed=False)
        new(folder / 'submission.confirmed.json', result)
        new(record / (KEY + '.confirmed.json'), result)
        print('GRU_STARTUP_PATH_RECOVERY_JSON ' + json.dumps(result, sort_keys=True), flush=True)


if __name__ == '__main__':
    main()

ONE_SCOPED_STARTUP_PATH_RECOVERY

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
                     'scheduler_slice_end_' + job + '.json', 'submission_context_repair.confirmed.json'):
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
