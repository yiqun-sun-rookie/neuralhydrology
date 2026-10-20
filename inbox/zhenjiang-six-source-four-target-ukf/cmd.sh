#!/usr/bin/env bash
set -eo pipefail
source /data1/home/sunyiq/miniconda3/etc/profile.d/conda.sh
conda activate nh_final
set -u
export PYTHONDONTWRITEBYTECODE=1
python -B - <<'ACTIVATE_FIXED200_003'
"""Activate the two reviewed fixed-200 cases in a fresh formal output root.

Executed once through the registered mailbox. Reads authenticated 690 and 675
artifacts, copies complete candidates, writes isolated authority and submits
one job per case. Original sources and the frozen 003 release are unchanged.
"""
import datetime
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys

BASE = Path('/data1/home/sunyiq')
DEST = BASE / 'zhenjiang_complete_comparison_fixed200_20261019_003'
HANDOFF = BASE / 'zhenjiang_fixed200_003_handoff_20261020_001'
OLD = BASE / 'zhenjiang_fixed200_003_candidates_20261019_002'
SLURM = Path('/usr/local/globle/softs/slurm/19.05.4.1/bin')
SUPPORT_FILES = {'run_fixed200_case.py': '"""Run a frozen case with one writer and the existing scheduler deadline hook.\n\nUsage from an admitted runtime: python -B hpc/run_fixed200_case.py --case CASE\nInputs: authorization, case manifest, allocated GPU and frozen runtime files.\nOutputs: per-allocation device/start receipt, normal training or slice-end record.\nDoes not change scientific configuration or submit any scheduler job.\n"""\nimport datetime\nimport fcntl\nimport hashlib\nimport importlib.util\nimport json\nimport os\nfrom pathlib import Path\nimport subprocess\nimport sys\nimport time\n\nROOT = Path(__file__).resolve().parents[1]\nSLURM = Path(\'/usr/local/globle/softs/slurm/19.05.4.1/bin\')\n\n\ndef write_new(path, value):\n    with path.open(\'x\') as handle:\n        json.dump(value, handle, sort_keys=True, indent=2, allow_nan=False)\n        handle.write(\'\\n\')\n\n\ndef main():\n    import argparse\n    parser = argparse.ArgumentParser(description=__doc__)\n    parser.add_argument(\'--case\', required=True)\n    args = parser.parse_args()\n    case, job = args.case, os.environ[\'SLURM_JOB_ID\']\n    auth = json.loads((ROOT / \'records/authorization.json\').read_bytes())\n    if case not in auth[\'allowed_cases\'] or not auth[\'authority\'][\'formal_training\']:\n        raise PermissionError(\'case is outside activated scope\')\n    record = ROOT / \'records\' / case\n    record.mkdir(exist_ok=True)\n    with (record / \'writer.lock\').open(\'a\') as writer:\n        fcntl.flock(writer, fcntl.LOCK_EX | fcntl.LOCK_NB)\n        sys.path.insert(0, str(ROOT))\n        sys.path.insert(0, str(ROOT / \'scripts\'))\n        from src.execution import device_identity\n        from src.scheduler import code_identity\n        from src.training import SchedulerContinuation\n        actual = device_identity(\'cuda:0\')\n        if actual != auth[\'device_identity\'] or code_identity() != auth[\'code_hash\']:\n            raise ValueError(\'actual GPU or frozen implementation differs\')\n        command = [str(SLURM / \'squeue\'), \'-h\', \'-j\', job,\n                   \'-o\', \'%i|%T|%Z|%e|%l|%P|%C|%b|%N\']\n        result = subprocess.run(command, capture_output=True, text=True, timeout=30)\n        if result.returncode:\n            raise RuntimeError(\'allocation query failed: \' + result.stderr)\n        rows = [line.split(\'|\') for line in result.stdout.splitlines() if line.strip()]\n        if len(rows) != 1 or len(rows[0]) != 9:\n            raise ValueError(\'one actual allocation required\')\n        row = dict(zip((\'job\', \'state\', \'root\', \'end\', \'limit\', \'partition\',\n                        \'cpus\', \'gres\', \'node\'), rows[0]))\n        if (row[\'job\'] != job or row[\'state\'] != \'RUNNING\' or row[\'root\'] != str(ROOT)\n                or row[\'partition\'] != auth[\'scheduler\'][\'partition\'] or row[\'cpus\'] != \'4\'\n                or row[\'gres\'] != \'gpu:1\' or row[\'node\'] != auth[\'scheduler\'][\'node\']):\n            raise ValueError(\'allocation identity differs\')\n        deadline = None\n        if row[\'limit\'] != \'UNLIMITED\':\n            remaining = datetime.datetime.fromisoformat(row[\'end\']).timestamp() - time.time()\n            if remaining <= 600:\n                raise ValueError(\'allocation lacks existing 600-second exit margin\')\n            deadline = time.perf_counter() + remaining - 600\n        receipt = {\'schema\': \'fixed200-runtime-start-v1\', \'case\': case, \'job_id\': job,\n                   \'at_utc\': datetime.datetime.now(datetime.timezone.utc).isoformat(),\n                   \'root\': str(ROOT), \'device_identity\': actual, \'scheduler\': row,\n                   \'code_hash\': auth[\'code_hash\'], \'protocol_sha256\': auth[\'protocol_sha256\'],\n                   \'migration_digest\': auth[\'migration_manifest_sha256_by_case\'][case],\n                   \'wrapper_sha256\': hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),\n                   \'entry_invoked\': False, \'new_complete_epochs_confirmed\': False}\n        write_new(record / (\'runtime_binding_\' + job + \'.json\'), receipt)\n        print(json.dumps(receipt), flush=True)\n        spec = importlib.util.spec_from_file_location(\'fixed200_formal_case\', ROOT / \'scripts/train_supercomputer_case.py\')\n        module = importlib.util.module_from_spec(spec)\n        spec.loader.exec_module(module)\n        original = module.execute_group\n\n        def execute(*positional, **keywords):\n            if \'scheduler_deadline\' in keywords:\n                raise ValueError(\'duplicate scheduler deadline\')\n            return original(*positional, scheduler_deadline=deadline, **keywords)\n\n        module.execute_group = execute\n        sys.argv = [str(ROOT / \'scripts/train_supercomputer_case.py\'), \'--case\', case,\n                    \'--migration-manifest\', str(record / \'migration_manifest.json\')]\n        try:\n            module.main()\n        except SchedulerContinuation:\n            value = {\'status\': \'scheduler_slice_saved_for_continuation\', \'job_id\': job,\n                     \'case\': case, \'at_utc\': datetime.datetime.now(datetime.timezone.utc).isoformat(),\n                     \'code_hash\': auth[\'code_hash\'], \'scientific_budget_changed\': False,\n                     \'checkpoint_boundary\': \'each member retains its own last complete current/Adam/history\'}\n            write_new(record / (\'scheduler_slice_end_\' + job + \'.json\'), value)\n            print(json.dumps(value), flush=True)\n\n\nif __name__ == \'__main__\':\n    main()\n', 'submit_fixed200_continuation.py': '"""Continue one activated fixed-200 case after a healthy scheduler stop.\n\nExample: python -B hpc/submit_fixed200_continuation.py --case CASE\nCalled by the existing monitor after a fresh terminal-status check. Does not\ninitialize missing runs, change configs, resume scientific failures or retry an\nuncertain submission. The case entry validates complete checkpoint state.\n"""\nimport argparse\nimport datetime\nimport hashlib\nimport json\nfrom pathlib import Path\nimport re\nimport subprocess\nimport sys\n\nROOT = Path(__file__).resolve().parents[1]\nSLURM = Path(\'/usr/local/globle/softs/slurm/19.05.4.1/bin\')\n\n\ndef read(path):\n    return json.loads(path.read_bytes())\n\n\ndef save(path, value):\n    with path.open(\'x\') as handle:\n        json.dump(value, handle, sort_keys=True, indent=2, allow_nan=False)\n        handle.write(\'\\n\')\n\n\ndef query(command):\n    result = subprocess.run(list(map(str, command)), cwd=str(ROOT), capture_output=True, text=True, timeout=60)\n    value = {\'command\': list(map(str, command)), \'returncode\': result.returncode,\n             \'stdout\': result.stdout, \'stderr\': result.stderr}\n    if result.returncode:\n        raise RuntimeError(json.dumps(value))\n    return value\n\n\ndef main():\n    parser = argparse.ArgumentParser(description=__doc__)\n    parser.add_argument(\'--case\', required=True)\n    case = parser.parse_args().case\n    auth = read(ROOT / \'records/authorization.json\')\n    if case not in auth[\'allowed_cases\'] or not auth[\'authority\'][\'routine_scheduler_continuation\']:\n        raise PermissionError(\'case continuation not authorized\')\n    record = ROOT / \'records\' / case\n    if (record / \'training_complete.json\').exists():\n        print(json.dumps({\'status\': \'case_complete_no_continuation\', \'case\': case}))\n        return\n    sys.path.insert(0, str(ROOT))\n    from src.scheduler import code_identity\n    if code_identity() != auth[\'code_hash\'] or hashlib.sha256((ROOT / \'configs/protocol-v3.json\').read_bytes()).hexdigest() != auth[\'protocol_sha256\']:\n        raise ValueError(\'frozen implementation or protocol changed\')\n    if list((ROOT / \'runs\').glob(\'*/failure.json\')):\n        raise ValueError(\'scientific failure requires diagnosis\')\n    for folder in (ROOT / \'runs\').iterdir():\n        if folder.is_dir() and folder.name.startswith(case + \'__\') and not (folder / \'continuation.pt\').is_file():\n            raise FileNotFoundError(\'existing member lacks complete checkpoint\')\n    jobs_path = ROOT / \'records/scheduler_jobs.json\'\n    jobs = read(jobs_path)\n    previous = str(jobs[case])\n    queue = query([SLURM / \'squeue\', \'-h\', \'-u\', \'sunyiq\', \'-o\', \'%i|%j|%T|%Z|%o\'])\n    if any(case in line or str(ROOT) in line or line.startswith(previous + \'|\') for line in queue[\'stdout\'].splitlines()):\n        print(json.dumps({\'status\': \'case_has_existing_job_no_submission\', \'case\': case, \'queue\': queue}))\n        return\n    accounting = query([SLURM / \'sacct\', \'-n\', \'-X\', \'-j\', previous,\n                        \'--format=JobID,State,ExitCode,Start,End,NodeList\', \'-P\'])\n    rows = [line.split(\'|\') for line in accounting[\'stdout\'].splitlines() if line.startswith(previous + \'|\')]\n    if len(rows) != 1 or not (rows[0][1] in (\'TIMEOUT\', \'PREEMPTED\', \'NODE_FAIL\') or\n            (rows[0][1:3] == [\'COMPLETED\', \'0:0\'] and (record / (\'scheduler_slice_end_\' + previous + \'.json\')).exists())):\n        raise ValueError(\'healthy scheduler termination required\')\n    template = ROOT / \'hpc/fixed200_case.slurm\'\n    if hashlib.sha256(template.read_bytes()).hexdigest() != auth[\'scheduler\'][\'script_sha256\']:\n        raise ValueError(\'scheduler template changed\')\n    key = \'continuation_after_\' + previous\n    save(record / (key + \'.attempt.json\'), {\'case\': case, \'previous_job\': previous, \'queue\': queue,\n         \'accounting\': accounting, \'at_utc\': datetime.datetime.now(datetime.timezone.utc).isoformat(),\n         \'script_sha256\': auth[\'scheduler\'][\'script_sha256\']})\n    try:\n        result = query([SLURM / \'xbatch\', template])\n    except Exception as error:\n        save(record / (key + \'.response.json\'), {\'status\': \'uncertain_reconcile_readonly\', \'error\': str(error)})\n        raise\n    save(record / (key + \'.response.json\'), result)\n    match = re.fullmatch(r\'Submitted batch job ([0-9]+)\\s*\', result[\'stdout\'])\n    if not match:\n        raise RuntimeError(\'uncertain submission: reconcile without replay\')\n    jobs[case] = match.group(1)\n    temporary = jobs_path.with_suffix(\'.json.tmp\')\n    save(temporary, jobs)\n    temporary.replace(jobs_path)\n    save(record / (key + \'.confirmed.json\'), {\'case\': case, \'job_id\': match.group(1), \'previous_job\': previous})\n    print(json.dumps({\'status\': \'fixed200_continuation_submitted\', \'case\': case, \'job_id\': match.group(1)}), flush=True)\n\n\nif __name__ == \'__main__\':\n    main()\n'}
PLAN_RECORD = {'schema': 'fixed200-reviewed-plan-execution-v1', 'user_instruction': 'go after the next-step plan and independent review completed on 2026-10-20', 'plan_sha256': 'ae10962b2049d1db97a1974cd82881647c1bfe3af7e42cf5307693fb82d98e26', 'independent_review_sha256': 'ceae3bd70ae9a1f5e278ea3a0c3a2de1328de2e8571ff33ba446bf427e1d4c97', 'release_manifest_sha256': '28f547202d5ee1dfafc845714fafd791bd08b853bd184a14f95b78958be47d43', 'independent_reviewer': '/root/review_stage_sources', 'independent_review_passed': True, 'model_specific_astra_review_claimed': False, 'scope': ['legacy_lstm__historical_capacity', 'explicit_gru__historical_capacity'], 'routine_HPC_authority': 'user stated their own HPC does not require fee or routine resource approval'}
CASES = {
    'legacy_lstm__historical_capacity': {
        'variant': 'base', 'partition': 'hgpu2p', 'node': 'ngu001', 'limit': '0',
        'code_hash': 'd1f1e39c22ae7e86f59a882b7581065ce8b9b330d612f8122d08bd5da9949ff4',
        'migration_digest': '64ff724839d49bca796ab97ccea494a95666b658ad1880852d0bd9087d21c462',
        'device_identity': {'device': 'cuda:0', 'name': 'NVIDIA GeForce RTX 3090', 'total_memory_bytes': 25296044032},
    },
    'explicit_gru__historical_capacity': {
        'variant': 'sqrt_gru_recovery', 'partition': 'hgpu4', 'node': 'ngu102', 'limit': '12:00:00',
        'code_hash': '109a24b738c940a00d6f1ec0a9e132f63f9231b779b3931af8f6c12c1770c426',
        'migration_digest': '7da5d8b8419d5ad16f9fc3650da828f4ab21978ca641bb8ea30af3306921d363',
        'device_identity': {'device': 'cuda:0', 'name': 'NVIDIA A40', 'total_memory_bytes': 47622258688},
    },
}


def now():
    return datetime.datetime.now(datetime.timezone.utc).isoformat()


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def digest(value):
    return sha(json.dumps(value, sort_keys=True, separators=(',', ':'), allow_nan=False).encode())


def read(path):
    return json.loads(path.read_bytes())


def write(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open('x') as handle:
        json.dump(value, handle, sort_keys=True, indent=2, allow_nan=False)
        handle.write('\n')


def code_hash(root):
    files = sorted([*root.joinpath('src').glob('*.py'), *root.joinpath('scripts').glob('*.py'),
                    *root.joinpath('vendor/pytides').glob('*.py')])
    return digest({p.relative_to(root).as_posix(): sha(p.read_bytes()) for p in files})


def query(command, checked=True):
    command = list(map(str, command))
    result = subprocess.run(command, capture_output=True, text=True, timeout=60)
    value = {'command': command, 'returncode': result.returncode, 'stdout': result.stdout,
             'stderr': result.stderr, 'at_utc': now()}
    if checked and result.returncode:
        raise RuntimeError(json.dumps(value))
    return value


def queue():
    return query([SLURM / 'squeue', '-h', '-u', 'sunyiq', '-o', '%i|%j|%T|%Z|%o'])


def slurm_script(case, setting, root):
    lines = ['#!/usr/bin/env bash', '#SBATCH --job-name=zj003_' + case,
             '#SBATCH -p ' + setting['partition'], '#SBATCH --nodelist=' + setting['node'],
             '#SBATCH --nodes=1', '#SBATCH --ntasks=1', '#SBATCH --cpus-per-task=4',
             '#SBATCH --gres=gpu:1', '#SBATCH --time=' + setting['limit']]
    if setting['partition'] == 'hgpu4':
        lines.append('#SBATCH --time-min=02:00:00')
    lines += ['#SBATCH --output=' + str(root / 'logs/%x_%j.out'), 'set -eo pipefail',
              'source /data1/home/sunyiq/miniconda3/etc/profile.d/conda.sh', 'conda activate nh_final',
              'set -u', 'export PYTHONDONTWRITEBYTECODE=1', 'export OMP_NUM_THREADS=4',
              'export MKL_NUM_THREADS=4', 'export OPENBLAS_NUM_THREADS=4',
              'export CUBLAS_WORKSPACE_CONFIG=:4096:8', 'cd ' + str(root),
              'python -B -u hpc/run_fixed200_case.py --case ' + case]
    return '\n'.join(lines) + '\n'


assert not DEST.exists(), 'formal root exists: inspect its receipt instead of replaying'
assert SUPPORT_FILES and PLAN_RECORD
before_queue = queue()
assert not any(case in line or str(DEST) in line for case in CASES
               for line in before_queue['stdout'].splitlines()), 'target case already has an active/queued writer'
handoff_raw = (HANDOFF / 'handoff_report.json').read_bytes()
assert sha(handoff_raw) == 'c48ec6273e1a6ecd38999c46ceb20f7641ed8f764cdb78367e0b87b169a87bf4'
handoff = json.loads(handoff_raw)
assert not handoff['errors'] and handoff['old_job_stopped']
DEST.mkdir()
write(DEST / 'records/activation_authority.json', PLAN_RECORD)
write(DEST / 'records/source_queue_before.json', before_queue)
report = {'schema': 'fixed200-activation-v1', 'started_utc': now(), 'root': str(DEST),
          'activated': False, 'scope': list(CASES), 'cases': {}, 'jobs_submitted': {}, 'errors': [],
          'original400_reused': True, 'source_files_written': False, 'evaluation_values_read': False,
          'tide_refits': 0, 'blocked_members_unchanged': 9, 'plan_sha256': PLAN_RECORD['plan_sha256']}
try:
    # Complete both deployments before the first scheduler mutation.
    for case, setting in CASES.items():
        variant = setting['variant']
        source_runtime = HANDOFF / 'runtimes' / variant
        root = DEST / variant
        assert code_hash(source_runtime) == setting['code_hash']
        shutil.copytree(source_runtime, root)
        (root / 'logs').mkdir(exist_ok=True)
        (root / 'hpc').mkdir(exist_ok=True)
        records = root / 'records' / case
        records.mkdir(exist_ok=True)
        if variant == 'base':
            migration_raw = (HANDOFF / 'lstm_migration_manifest.json').read_bytes()
        else:
            migration_raw = (OLD / 'candidates/sqrt_gru_recovery' / (case + '_migration_manifest.json')).read_bytes()
        migration = json.loads(migration_raw)
        assert digest(migration) == setting['migration_digest']
        assert migration['case'] == case and len(migration['members']) == 12
        if variant != 'base':
            runs = root / 'runs'
            runs.mkdir(exist_ok=True)
            for member in migration['members']:
                shutil.copytree(OLD / 'candidates/sqrt_gru_recovery/runs' / member, runs / member)
        assert sorted(p.name for p in (root / 'runs').iterdir() if p.is_dir()) == sorted(migration['members'])
        initial = {}
        for member, binding in migration['members'].items():
            folder = root / 'runs' / member
            assert binding['member_kind'] == 'continuation'
            assert not (folder / 'failure.json').exists()
            raw_config = (folder / 'config.json').read_bytes()
            config = json.loads(raw_config)
            assert sha(raw_config) == binding['config_sha256']
            assert sha((folder / 'migration_source.json').read_bytes()) == binding['receipt_sha256']
            assert sha((folder / 'continuation.pt').read_bytes()) == binding['checkpoint_sha256']
            assert config['effective_config']['device_identity'] == setting['device_identity']
            anchor = read(folder / 'continuation_anchor.json')
            head = read(folder / 'checkpoint_head.json')
            assert head['checkpoint_sha256'] == anchor['initial_checkpoint_sha256'] == binding['checkpoint_sha256']
            assert 0 < anchor['initial_epochs'] == head['completed_epochs'] < 200
            initial[member] = {'completed_epochs': head['completed_epochs'], 'checkpoint_sha256': head['checkpoint_sha256'],
                               'config_sha256': binding['config_sha256'], 'receipt_sha256': binding['receipt_sha256']}
        assert code_hash(root) == setting['code_hash']
        protocol_raw = (root / 'configs/protocol-v3.json').read_bytes()
        assert read(root / 'configs/protocol-v3.json')['future_run_root'] == str(root)
        prep = read(root / 'records/data_preparation_complete.json')
        assert prep['status'] == 'admitted' and prep['code_hash'] == setting['code_hash']
        with (records / 'migration_manifest.json').open('xb') as handle:
            handle.write(migration_raw)
        write(records / 'activation_starting_members.json', initial)
        for name, content in SUPPORT_FILES.items():
            with (root / 'hpc' / name).open('x') as handle:
                handle.write(content)
        script = root / 'hpc/fixed200_case.slurm'
        with script.open('x') as handle:
            handle.write(slurm_script(case, setting, root))
        authority = {'schema': 'fixed200-formal-activation-authority-v1', 'authority': {
            'formal_training': True, 'cluster_submission': True, 'technical_recovery': True,
            'routine_scheduler_continuation': True, 'evaluation_year_reads': False},
            'allowed_cases': [case], 'protocol_sha256': sha(protocol_raw), 'code_hash': setting['code_hash'],
            'migration_manifest_sha256_by_case': {case: setting['migration_digest']},
            'device_identity': setting['device_identity'], 'scheduler': {
                'partition': setting['partition'], 'node': setting['node'], 'time_limit_requested': setting['limit'],
                'script_sha256': sha(script.read_bytes())},
            'user_instruction': PLAN_RECORD['user_instruction'], 'approved_plan_sha256': PLAN_RECORD['plan_sha256'],
            'independent_review_sha256': PLAN_RECORD['independent_review_sha256'],
            'support_sha256': {name: sha(content.encode()) for name, content in SUPPORT_FILES.items()},
            'activated_at_utc': now(), 'new_experiment': False,
            'training_endpoints': {'tune_foundation': 'original_completed_400_source_reuse',
                                   'tune_branch': 200, 'final_foundation': 200, 'primary': 200, 'controlled': 200},
            'scope': 'continue complete migrated tuning branches, then registered final training for this case',
            'resource_authority': 'user_owned_HPC_no_separate_fee_or_routine_resource_approval'}
        write(root / 'records/authorization.json', authority)
        report['cases'][case] = {'variant': variant, 'root': str(root), 'code_hash': setting['code_hash'],
            'protocol_sha256': sha(protocol_raw), 'migration_digest': setting['migration_digest'],
            'authorization_sha256': sha((root / 'records/authorization.json').read_bytes()),
            'device_identity': setting['device_identity'], 'initial_members': initial,
            'script_sha256': sha(script.read_bytes()), 'data_receipt_sha256': sha((root / 'records/data_preparation_complete.json').read_bytes())}
        print(json.dumps({'status': 'case_deployed', 'case': case, 'root': str(root), 'members': len(initial)}), flush=True)
    report['activated'] = True
    write(DEST / 'records/deployment_complete.json', report)
    for case, setting in CASES.items():
        root = DEST / setting['variant']
        current_queue = queue()
        assert not any(case in line or str(root) in line for line in current_queue['stdout'].splitlines())
        record = root / 'records' / case
        script = root / 'hpc/fixed200_case.slurm'
        write(record / 'initial_submission.attempt.json', {'at_utc': now(), 'case': case,
              'queue': current_queue, 'script_sha256': sha(script.read_bytes())})
        try:
            submitted = query([SLURM / 'xbatch', script], checked=False)
        except Exception as error:
            write(record / 'initial_submission.response.json', {'status': 'uncertain_reconcile_readonly', 'error': str(error)})
            raise
        write(record / 'initial_submission.response.json', submitted)
        match = re.fullmatch(r'Submitted batch job ([0-9]+)\s*', submitted['stdout'])
        assert submitted['returncode'] == 0 and match, 'submission response requires read-only reconciliation'
        job = match.group(1)
        write(root / 'records/scheduler_jobs.json', {case: job})
        write(record / 'initial_submission.confirmed.json', {'case': case, 'job_id': job, 'at_utc': now()})
        report['jobs_submitted'][case] = job
        report['cases'][case]['job_id'] = job
        print(json.dumps({'status': 'fixed200_case_submitted', 'case': case, 'job_id': job}), flush=True)
    report['queue_after'] = queue()
    report['status'] = 'two_fixed200_cases_activated_submitted'
except Exception as error:
    report['errors'].append({'type': type(error).__name__, 'message': str(error)})
    report['status'] = 'activation_partial_or_error_preserved'
report['finished_utc'] = now()
write(DEST / 'records/activation_report.json', report)
print(json.dumps(report, sort_keys=True), flush=True)
print(json.dumps({'activation_report_sha256': sha((DEST / 'records/activation_report.json').read_bytes()), 'root': str(DEST)}), flush=True)
if report['errors']:
    sys.exit(2)

ACTIVATE_FIXED200_003
