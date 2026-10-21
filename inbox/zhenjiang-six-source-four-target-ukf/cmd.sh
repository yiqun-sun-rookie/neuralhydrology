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

# Authorized read-only scope supplement; no model or tensor loading.
legacy_baseline = {'explicit_gru__small': {'root': '/data1/home/sunyiq/zhenjiang_complete_comparison_20261006_002', 'job_id': '236706', 'members': {'explicit_gru__small__tune_branch__encoder_fixed__s101__lr0p0003': {'config_sha256': '193cf6125cebb59bae217dea7da977a33c3165c5dd9a4924a3d622180dd21533', 'completed_epochs': 275, 'history_sha256': '8992edcd3b29e761f995a7bd4720c3ee9e943e4ec5184f6ba1070971b3cb29b7'}, 'explicit_gru__small__tune_branch__encoder_fixed__s101__lr0p001': {'config_sha256': 'c3771f414619fbf07e91edfd7c3fd19443afa2ef5f21c65b3d541e83ebb5ee2b', 'completed_epochs': 275, 'history_sha256': 'd7b9db82b0a85d84eb288db1583c2733897c455abb52c6609e58c3443a999f8b'}, 'explicit_gru__small__tune_branch__encoder_fixed__s101__lr0p003': {'config_sha256': '618d3b6572907557b324d5bed7d093186650e57a9336747aba0d98c73bc1af97', 'completed_epochs': 275, 'history_sha256': '8d79fc1bbe522c88b53d1eb55364db14087dea17022a83d9709316c3c2ea6a37'}, 'explicit_gru__small__tune_branch__encoder_joint__s101__lr0p0003': {'config_sha256': '7d0bfac8842ff0411f6b73147e44503c05dff716a1cb319ab01a965604000e47', 'completed_epochs': 275, 'history_sha256': '94fbb1ef60912e6a4f9dccaa47fc8a4c390b1d5c5c79c70c0db3f7fbd6fb82a5'}, 'explicit_gru__small__tune_branch__encoder_joint__s101__lr0p001': {'config_sha256': '827875db61542fed7eb8bd0eba5007c325af2513531ffbc6b2fb95e68c1fc472', 'completed_epochs': 275, 'history_sha256': 'e702d6e37945cb92b15a7b33b4cfe8c216501e0efc24e5c44debff10ece998d5'}, 'explicit_gru__small__tune_branch__encoder_joint__s101__lr0p003': {'config_sha256': 'a18a45cb6d50e04625c699bd29bf692f4045e35a8c9fa3636e27d660b20711d3', 'completed_epochs': 275, 'history_sha256': 'f4d697f17004799df2fdadd607e64cd0f00ec984500363e630cbab61ed9d230d'}, 'explicit_gru__small__tune_branch__filter_fixed__s101__lr0p0003': {'config_sha256': 'e7051fa37edd8f10e9b8c0075ad8b1ae8a5f152db66b49f6036b78dab59328b9', 'completed_epochs': 275, 'history_sha256': '2247b130193daa9000099bac36ffcd951a0e59eb237c98e148da2f2072801392'}, 'explicit_gru__small__tune_branch__filter_fixed__s101__lr0p001': {'config_sha256': '6cbbcf8c2e712711580cfade4a2896be366ec58b20a38976daa71ee16e9ba828', 'completed_epochs': 275, 'history_sha256': '978792741f1eb3348ebe6872b3e6171d71606fffda03615b954cf3353943df61'}, 'explicit_gru__small__tune_branch__filter_fixed__s101__lr0p003': {'config_sha256': '98add4c10116f2842174bde18628f9ce83c1fe3593ff824e76255109287082a7', 'completed_epochs': 275, 'history_sha256': '8008aafd184c8fc91c9388c1056f3472a733cd1a5b55d44ab0bda464342df75e'}, 'explicit_gru__small__tune_branch__filter_joint__s101__lr0p0003': {'config_sha256': '0fa9c806b49a651c706b713d009ad4b84aaf669b9ee7b59495477b0693566cf9', 'completed_epochs': 274, 'history_sha256': '11723a98c2a0696a0ab177fde8fd390e26b5e76131df2fb8db6c73e59891ca66'}, 'explicit_gru__small__tune_branch__filter_joint__s101__lr0p001': {'config_sha256': 'c16523a2ecd52b57acb5bad85d297d9589e1c7898d693d212777e690c33d03b1', 'completed_epochs': 274, 'history_sha256': 'c7a93c23a7d13c20e11452f11a7b1510af1f1908678f36a3b908f92639835675'}, 'explicit_gru__small__tune_branch__filter_joint__s101__lr0p003': {'config_sha256': '8d4770dd2d865c6535667c0c16cb4d6b39ec395c465a1b79fef3f1f6c7eaa468', 'completed_epochs': 274, 'history_sha256': '1e685c0d13ebd8d6d9e22c0439a6fe032b0f450a50dcd21ea87a12ea5cd690bb'}, 'explicit_gru__small__tune_foundation__foundation__s101__lr0p0003': {'config_sha256': 'a709cc96e6ea8162f6f41a520bb357a4656a60f566da769dce135f56bfc3db2e', 'completed_epochs': 400, 'history_sha256': 'cd04eb815f41694c30c51cc0d1f225fa14a800b78ac51122424aa1c0a047324c'}, 'explicit_gru__small__tune_foundation__foundation__s101__lr0p001': {'config_sha256': 'f63836b60a6bb783075edbbc3cb0a01f251d1e3001d136e7e6883db6c8c6282e', 'completed_epochs': 400, 'history_sha256': '353aefbc2385d2a187ca14b8e16e0f78c2fa76d2ab97d149d8fd1ea3ddc2a524'}, 'explicit_gru__small__tune_foundation__foundation__s101__lr0p003': {'config_sha256': '49b1bb64e347b924e493b4ecf52e09510b5fd3596d5739e4bd2bb7168847d16a', 'completed_epochs': 400, 'history_sha256': 'a0e950667f57796adf1f0013159d12cfe5d509ed48bae089caaf6daaf76a9174'}}}, 'legacy_lstm__small': {'root': '/data1/home/sunyiq/zhenjiang_complete_comparison_20261008_recovery_002', 'job_id': '237928', 'members': {'legacy_lstm__small__tune_branch__encoder_fixed__s101__lr0p0003': {'config_sha256': '49adbee35b1a23be92b55519b453e4d0cc236137f152983e171b546fa6e6431c', 'completed_epochs': 214, 'history_sha256': '2e1ab34562e9c51c451e5b7f315b9aeff97ece311e3f1d52eaafbb31de3d8e4b'}, 'legacy_lstm__small__tune_branch__encoder_fixed__s101__lr0p001': {'config_sha256': '0ceb7b21bbf318db314218af1418ca2b8e976d3f5e1aaa118fb90ad62d1ffad7', 'completed_epochs': 214, 'history_sha256': '93bfb6ec23c61a24c3fec30ceac28756282a7eb55b64fecd95cdd3e6d22f64d3'}, 'legacy_lstm__small__tune_branch__encoder_fixed__s101__lr0p003': {'config_sha256': '9d54ff17e32ec9b0274920a6e508b7f12105ea9ee44e2e85321b09cf54a1f355', 'completed_epochs': 214, 'history_sha256': '3f92e10140c49f6060b2341808733e88c0a60d8676477dd82506ce18f6c3351f'}, 'legacy_lstm__small__tune_branch__encoder_joint__s101__lr0p0003': {'config_sha256': '106d68e50e65c4bd05db01f39d047b690dbdc499cf10a954570fc3ed5c688930', 'completed_epochs': 214, 'history_sha256': '3fccac0e74e9a9a771c1b1856017ca82a6e7c0a78cee17b7f4ce17db2fb6e5b6'}, 'legacy_lstm__small__tune_branch__encoder_joint__s101__lr0p001': {'config_sha256': 'eac12d0b1a4067e8a7cddb75d97f3bc3ae4426c5cb4c30113f014a760db75cb2', 'completed_epochs': 214, 'history_sha256': '343e28ba05901b54cb216176386a990ab2cc59a3d944f68c898d0ed3e2c68cdb'}, 'legacy_lstm__small__tune_branch__encoder_joint__s101__lr0p003': {'config_sha256': '0b967227bd4d756bc6c29d6330e18a264b7ca43d666d81486716dec4df40a751', 'completed_epochs': 214, 'history_sha256': '8b001f0fa574846bb382aa2456cd83d4404c0561118ebda461585f350c50b754'}, 'legacy_lstm__small__tune_branch__filter_fixed__s101__lr0p0003': {'config_sha256': '8031cced43b3543fc5a4482241cbc6c92e24b9f5c6303fbb2f05a474bad0fc01', 'completed_epochs': 214, 'history_sha256': '2316a831e2ebde26d477ed9f58db88ecffef99b3bc7ccff1ff713ea29322e7a4'}, 'legacy_lstm__small__tune_branch__filter_fixed__s101__lr0p001': {'config_sha256': '01a19522ae6d57bd8099878ab6ca22f81009b781edd361cde420a98fe460696d', 'completed_epochs': 214, 'history_sha256': '30c1439b45a191ddda406bbb8347d42c40ef884cd3ee1bfe087dd77eddbe7fd2'}, 'legacy_lstm__small__tune_branch__filter_fixed__s101__lr0p003': {'config_sha256': '97ab345de75490a8dd758ed129e426ac39478087a166af6bcc69690784d577e4', 'completed_epochs': 214, 'history_sha256': 'd72dfcd5470b5df9675d2018a2f5c929328a5c5931cf48bb2221105b650b2fb7'}, 'legacy_lstm__small__tune_branch__filter_joint__s101__lr0p0003': {'config_sha256': 'aa1277e9d66f47250d53dec409e28a6b1f2c4fb95d336b0e700b54b9f11ed8a8', 'completed_epochs': 214, 'history_sha256': '72bf5decfff327f6720ac1bb33654dc4f9bd70bb7ceeb6b0e5781b79d61c8652'}, 'legacy_lstm__small__tune_branch__filter_joint__s101__lr0p001': {'config_sha256': '53f1a7ab29b6954dcac4ced3897b6e1bb6efefcc7d210bed3a10f55d1163d792', 'completed_epochs': 214, 'history_sha256': 'b589ae59d87896c23184619e23978ebd289261bf79c23bdf023b30555bdca524'}, 'legacy_lstm__small__tune_branch__filter_joint__s101__lr0p003': {'config_sha256': 'c993e6836a39a1fb57a4ca56b14925612dda5912bedda4f98d1040aea8fb6e80', 'completed_epochs': 213, 'history_sha256': '633a399bd0c293d8fcbc6508b35549cf70c1a04c897aad1822b550ecb016a95f'}, 'legacy_lstm__small__tune_foundation__foundation__s101__lr0p0003': {'config_sha256': 'c83279fce611acd91deedc8adff68c1a91d93f2d1b8ba9ab6088f60ec1e28554', 'completed_epochs': 400, 'history_sha256': 'd2a8ebc87494babfb02df431827269e56e38af9747788be06732f54da8e0b2ca'}, 'legacy_lstm__small__tune_foundation__foundation__s101__lr0p001': {'config_sha256': '7b31c226e49c7da03659032d2632745f15c265c29ae51fa55a379c6c995cbb59', 'completed_epochs': 400, 'history_sha256': '93c43055a3cc95c6c77df62e9ecaa2106bb1eb01c115928097974a465ca2e1ec'}, 'legacy_lstm__small__tune_foundation__foundation__s101__lr0p003': {'config_sha256': 'e38fbb2a41a086a6599753cb3fbdbce742da550907dc67c12cb920c0945a32f6', 'completed_epochs': 400, 'history_sha256': '37257634bc6ca1b6e1c08c523740fb8488022fabebf3479c49cda39ffca1734a'}}}}

import re

def scope_stat(path):
    if not path.is_file():
        return {'exists': False}
    st = path.stat()
    return {'exists': True, 'bytes': st.st_size, 'mtime_ns': st.st_mtime_ns,
            'mtime_utc': datetime.datetime.fromtimestamp(st.st_mtime, datetime.timezone.utc).isoformat()}

report['legacy_small_cases'] = {}
for case, baseline_row in legacy_baseline.items():
    try:
        runtime = Path(baseline_row['root'])
        case_row = {'root': str(runtime), 'job_id': baseline_row['job_id'], 'members': {}, 'logs': []}
        for member, before in baseline_row['members'].items():
            folder = runtime / 'runs' / member
            assert sha(folder / 'config.json') == before['config_sha256']
            with (folder / 'metrics.json').open('rb') as stream:
                prefix = stream.read(131072).decode('utf-8')
            match = re.search(r'"validation_mae_cm"\s*:\s*', prefix)
            assert match is not None
            values = json.JSONDecoder().raw_decode(prefix[match.end():])[0]
            n = len(values)
            assert n >= before['completed_epochs']
            history = hashlib.sha256(json.dumps(values[:before['completed_epochs']], separators=(',', ':')).encode()).hexdigest()
            assert history == before['history_sha256']
            checkpoint = scope_stat(folder / 'continuation.pt')
            assert checkpoint['exists'] and checkpoint['bytes'] > 0
            case_row['members'][member] = {'completed_epochs': n, 'previous_epochs': before['completed_epochs'],
                'delta_since_691': n-before['completed_epochs'], 'configuration_and_history_prefix_preserved': True,
                'continuation_checkpoint_stat': checkpoint, 'failure_exists': (folder / 'failure.json').exists()}
        for path in sorted((runtime / 'logs').glob('*_' + baseline_row['job_id'] + '.out')):
            with path.open('rb') as stream:
                stream.seek(max(0, path.stat().st_size-7000))
                tail = stream.read().decode('utf-8', errors='replace')
            case_row['logs'].append({'path':str(path), 'stat':scope_stat(path),
                'error_lines_in_tail':[line[:1200] for line in tail.splitlines() if re.search(r'Traceback|Error|Exception|out of memory|training_stopped|slurmstepd|Killed',line,re.I)][-10:]})
        case_row['completed_member_epochs'] = sum(v['completed_epochs'] for v in case_row['members'].values())
        case_row['delta_since_691'] = sum(v['delta_since_691'] for v in case_row['members'].values())
        report['legacy_small_cases'][case] = case_row
    except Exception as error:
        report['errors'].append({'case':case,'type':type(error).__name__,'message':str(error),'scope':'registered_legacy_small'})
for case_row in report['cases'].values():
    for log in case_row['logs']:
        log['stat'] = scope_stat(Path(log['path']))
allowed_roots = {row['root'] for row in report['cases'].values()} | {row['root'] for row in legacy_baseline.values()}
# Only the four currently registered case roots are included.
known_terminal_jobs = {'236707','244445','245560'}
queue_rows = [line for line in report['queue']['stdout'].splitlines()
              if len(line.split('|')) >= 4 and (line.split('|')[3] in allowed_roots or line.split('|')[0] in known_terminal_jobs)]
report['queue']['stdout'] = '\n'.join(queue_rows) + ('\n' if queue_rows else '')
report['queue']['scope_filter_applied'] = True
report['known_terminal_accounting'] = query([SLURM/'sacct','-n','-X','-j',','.join(sorted(known_terminal_jobs)),
    '--format=JobID,State,ExitCode,Start,End,NodeList','-P'])
report['scope_finished_at_utc'] = datetime.datetime.now(datetime.timezone.utc).isoformat()


# Metadata-only follow-up for the one checkpoint gap recorded in receipt706.
# Standard library only: no torch, tensor deserialization, model or source writes.
import os
import pickletools
import zipfile

target_member = 'explicit_gru__small__tune_branch__filter_fixed__s101__lr0p0003'
target_root = Path(legacy_baseline['explicit_gru__small']['root'])
target_folder = target_root / 'runs' / target_member
target_path = target_folder / 'continuation.pt'
probe = {'member': target_member, 'path': str(target_path),
         'method': 'ZIP directory and streamed primitive values-list metadata only',
         'tensor_storage_bytes_read': 0, 'tensor_deserialization': False,
         'checkpoint_tensor_crc_verified': False, 'checkpoint_full_hash_computed': False}
try:
    with target_path.open('rb') as checkpoint_stream:
        before = os.fstat(checkpoint_stream.fileno())
        probe['open_file_stat'] = {'bytes': before.st_size, 'mtime_ns': before.st_mtime_ns,
            'mtime_utc': datetime.datetime.fromtimestamp(before.st_mtime,datetime.timezone.utc).isoformat(),
            'inode': before.st_ino}
        with zipfile.ZipFile(checkpoint_stream) as archive:
            entries = archive.infolist()
            assert len(entries) == len({x.filename for x in entries})
            assert all(not x.flag_bits & 1 and 0 <= x.header_offset < before.st_size
                       and x.header_offset + 30 + x.compress_size <= before.st_size for x in entries)
            pickles = [x for x in entries if x.filename.endswith('/data.pkl') or x.filename == 'data.pkl']
            assert len(pickles) == 1
            storages = [x for x in entries if '/data/' in x.filename and not x.is_dir()]
            assert storages and all(x.file_size > 0 for x in storages)
            probe['zip_directory_readable'] = True
            probe['zip_entries'] = len(entries)
            probe['tensor_storage_entries'] = len(storages)
            probe['tensor_storage_declared_bytes'] = sum(x.file_size for x in storages)
            probe['data_pickle_declared_bytes'] = pickles[0].file_size
            saved_values = []
            phase = 'find_values_key'
            with archive.open(pickles[0]) as metadata:
                for count, (opcode, argument, position) in enumerate(pickletools.genops(metadata)):
                    assert count < 200000 and position < 4*1024*1024, 'metadata prefix exceeds lightweight bound'
                    if phase == 'find_values_key':
                        if opcode.name in ('BINUNICODE','SHORT_BINUNICODE','UNICODE') and argument == 'values':
                            phase = 'expect_list'
                    elif phase == 'expect_list':
                        if opcode.name in ('BINPUT','LONG_BINPUT','MEMOIZE'):
                            continue
                        assert opcode.name == 'EMPTY_LIST', 'saved values uses unsupported encoding'
                        phase = 'read_values'
                    else:
                        if opcode.name in ('BINPUT','LONG_BINPUT','MEMOIZE','MARK','APPEND','APPENDS'):
                            continue
                        if opcode.name in ('BINFLOAT','FLOAT','BININT','BININT1','BININT2','INT','LONG','LONG1','LONG4'):
                            assert isinstance(argument,(int,float)) and not isinstance(argument,bool)
                            saved_values.append(argument)
                            continue
                        assert opcode.name in ('BINUNICODE','SHORT_BINUNICODE','UNICODE') and argument == 'train_metrics', 'unsupported saved values boundary'
                        phase = 'done'
                        probe['data_pickle_prefix_bytes_read'] = metadata.tell()
                        break
            assert phase == 'done' and saved_values
            probe['checkpoint_saved_value_count'] = len(saved_values)
            probe['checkpoint_saved_value_prefix_sha256'] = hashlib.sha256(json.dumps(saved_values,separators=(',',':')).encode()).hexdigest()
        after = os.fstat(checkpoint_stream.fileno())
        assert (before.st_ino,before.st_size,before.st_mtime_ns) == (after.st_ino,after.st_size,after.st_mtime_ns)
        probe['open_file_stable_during_metadata_read'] = True
    current = target_path.stat()
    probe['path_still_same_opened_file'] = (current.st_ino,current.st_size,current.st_mtime_ns) == (before.st_ino,before.st_size,before.st_mtime_ns)
    with (target_folder/'metrics.json').open('rb') as metrics_stream:
        prefix = metrics_stream.read(131072).decode('utf-8')
    match = re.search(r'"validation_mae_cm"\s*:\s*',prefix)
    assert match is not None
    metric_values = json.JSONDecoder().raw_decode(prefix[match.end():])[0]
    probe['metric_history_count_at_checkpoint_probe'] = len(metric_values)
    probe['saved_values_match_metric_prefix'] = saved_values == metric_values[:len(saved_values)]
    probe['saved_values_match_complete_metric_history'] = saved_values == metric_values
    probe['structural_metadata_status'] = 'CHECKPOINT_METADATA_READ_AND_HISTORY_BOUND'
except Exception as error:
    probe['structural_metadata_status'] = 'CHECKPOINT_METADATA_NOT_CONFIRMED'
    probe['error'] = {'type': type(error).__name__, 'message': str(error)}
probe['checked_at_utc'] = datetime.datetime.now(datetime.timezone.utc).isoformat()
report['focused_checkpoint_followup_706_gap'] = probe

# Read-only245929 attribution and first-complete-progress proof; no training imports.
import os,re
CASE='explicit_gru__historical_capacity'
TARGET_JOB='245929'
BASELINE726={'explicit_gru__historical_capacity__tune_branch__encoder_fixed__s101__lr0p0003': {'completed_epochs': 66, 'checkpoint_sha256': '28cdda150d4b85475669f535e424f21b823dc8757c90f40cd2a9d873bf5a85ed'}, 'explicit_gru__historical_capacity__tune_branch__encoder_fixed__s101__lr0p001': {'completed_epochs': 66, 'checkpoint_sha256': '59dbb7424baf415c3fefed201dabe1f554ca97d0b425dcb2eb52a6dd3a7d9e60'}, 'explicit_gru__historical_capacity__tune_branch__encoder_fixed__s101__lr0p003': {'completed_epochs': 66, 'checkpoint_sha256': 'd9ab97b562456a8ecb95959c98b49853ef11508010dd21de0ec4517e7654a1fa'}, 'explicit_gru__historical_capacity__tune_branch__encoder_joint__s101__lr0p0003': {'completed_epochs': 66, 'checkpoint_sha256': '59b78f675e1eaa8f3d2e1677c7c89630065bc543341b83012c06cab88ed73b74'}, 'explicit_gru__historical_capacity__tune_branch__encoder_joint__s101__lr0p001': {'completed_epochs': 66, 'checkpoint_sha256': '223676e95ab63cf184fe4c2e3c1b26f2f50a0be572afdd5b90ba95e8667a9551'}, 'explicit_gru__historical_capacity__tune_branch__encoder_joint__s101__lr0p003': {'completed_epochs': 66, 'checkpoint_sha256': '1dbfbb2e3f0bfee024318ba5a5d4420f669c29f16a144d87330559daa643ccdf'}, 'explicit_gru__historical_capacity__tune_branch__filter_fixed__s101__lr0p0003': {'completed_epochs': 66, 'checkpoint_sha256': 'efb53eaf6bf35f96170d7462e2517146da3cf9df0ff827e821fd3c4a0d90f47a'}, 'explicit_gru__historical_capacity__tune_branch__filter_fixed__s101__lr0p001': {'completed_epochs': 65, 'checkpoint_sha256': 'f6c3371968d825405a6ab876db80cb0b2919bbb8b827ed67eab46b70dc537a2f'}, 'explicit_gru__historical_capacity__tune_branch__filter_fixed__s101__lr0p003': {'completed_epochs': 65, 'checkpoint_sha256': '06b9c5625657cc304363ee17a69ee59323d5aa52bc51ae7d4bdf4b4e37d4cd27'}, 'explicit_gru__historical_capacity__tune_branch__filter_joint__s101__lr0p0003': {'completed_epochs': 65, 'checkpoint_sha256': '8445626d45ae05f8167f8511c5ae268118a74d30f680eed6212967baa4ca2204'}, 'explicit_gru__historical_capacity__tune_branch__filter_joint__s101__lr0p001': {'completed_epochs': 65, 'checkpoint_sha256': 'c83bb140f717de3864102d8b8cbbd956a0f04316a586ad45afd4cebc1712739f'}, 'explicit_gru__historical_capacity__tune_branch__filter_joint__s101__lr0p003': {'completed_epochs': 65, 'checkpoint_sha256': '032f67620d5ab60b5616a1d85a8da84271ce6da799930c5df16e36205e237612'}}
row=report['cases'][CASE]
root=Path(row['root']);record=root/'records'/CASE
detail=dict(job_id=row['job_id'],expected_job_id=TARGET_JOB,baseline_sequence=726,baseline_cumulative_case_epochs=116,baseline_members=BASELINE726,continuation_records={},changed_members=[],new_complete_member_epochs=0,hashed_new_checkpoint_files=0,unchanged_checkpoint_files_rehashed=0,training_executed=False,scheduler_submissions=0,node_live_pid_available=False,gpu_utilization_available=False)
def file_stat(p):
 st=p.stat();return dict(bytes=st.st_size,mtime_ns=st.st_mtime_ns,mtime_utc=datetime.datetime.fromtimestamp(st.st_mtime,datetime.timezone.utc).isoformat())
for name in ['continuation_after_245769.attempt.json','continuation_after_245769.response.json','continuation_after_245769.confirmed.json']:
 p=record/name
 if p.exists():
  raw=p.read_bytes();value=json.loads(raw)
  if isinstance(value.get('queue'),dict):
   value['queue']['stdout']='\n'.join(line for line in value['queue']['stdout'].splitlines() if str(root) in line or CASE in line)
  detail['continuation_records'][name]=dict(value=value,stat=file_stat(p),sha256=hashlib.sha256(raw).hexdigest())
env=dict(os.environ);env['TZ']='UTC';env['SLURM_TIME_FORMAT']='%Y-%m-%dT%H:%M:%S%z'
command=[SLURM/'sacct','-n','-X','-j','245769,245929','--format=JobID,State,ExitCode,Submit%32,Eligible%32,Start%32,End%32,ElapsedRaw,Timelimit,AllocCPUS,Partition%20,NodeList%30','-P']
result=subprocess.run(list(map(str,command)),capture_output=True,text=True,timeout=45,env=env)
detail['accounting_with_submit_utc_format']=dict(command=list(map(str,command)),read_only_environment_overrides=dict(TZ='UTC',SLURM_TIME_FORMAT=env['SLURM_TIME_FORMAT']),returncode=result.returncode,stdout=result.stdout,stderr=result.stderr)
command=[SLURM/'scontrol','-o','show','job',TARGET_JOB]
result=subprocess.run(list(map(str,command)),capture_output=True,text=True,timeout=45,env=env)
keep={'JobId','JobName','JobState','Reason','SubmitTime','EligibleTime','StartTime','EndTime','TimeLimit','RunTime','NumCPUs','NumNodes','NodeList','BatchHost','TRES','TresPerNode','Gres','Partition','ReqNodeList','ExcNodeList','BatchFlag'}
selected={}
for item in result.stdout.split():
 if '=' in item:
  k,v=item.split('=',1)
  if k in keep:selected[k]=v
detail['scontrol_selected_utc']=dict(command=list(map(str,command)),returncode=result.returncode,selected=selected,stderr=result.stderr)
detail['source_login_clock_utc']=datetime.datetime.now(datetime.timezone.utc).isoformat()
logs=[];log_epochs={}
for path in (root/'logs').glob('*_'+TARGET_JOB+'.out'):
 with path.open('rb') as stream:
  stream.seek(max(0,path.stat().st_size-131072));tail=stream.read().decode('utf-8',errors='replace')
 parsed=[]
 for line in tail.splitlines():
  try:v=json.loads(line)
  except json.JSONDecodeError:continue
  if isinstance(v,dict) and v.get('run') in BASELINE726 and isinstance(v.get('epoch'),int):
   parsed.append(dict(member=v['run'],epoch=v['epoch']))
   log_epochs.setdefault(v['run'],set()).add(v['epoch'])
 logs.append(dict(path=str(path),stat=file_stat(path),max_tail_bytes=131072,complete_epoch_log_records=parsed,error_lines_in_tail=[line[:1200] for line in tail.splitlines() if re.search(r'Traceback|Error|Exception|out of memory|training_stopped|slurmstepd|Killed',line,re.I)][-10:]))
detail['new_job_log_samples']=logs
assert set(row['members'])==set(BASELINE726)
for member,current in row['members'].items():
 old=BASELINE726[member];n=current['completed_epochs'];pn=old['completed_epochs']
 detail['new_complete_member_epochs']+=n-pn
 if n>pn and row['job_id']==TARGET_JOB:
  folder=root/'runs'/member
  change=dict(member=member,baseline_epochs=pn,completed_epochs=n,baseline_checkpoint_sha256=old['checkpoint_sha256'],current_checkpoint_sha256=current['checkpoint_sha256_from_committed_head'],latest_event=current['new_epoch_event'],checkpoint_stat=file_stat(folder/'continuation.pt'),new_job_log_matches_current_epoch=n in log_epochs.get(member,set()))
  chain=[];head_sha=current['checkpoint_sha256_from_committed_head'];expected_n=n
  for _ in range(min(n-pn,32)):
   event=read(folder/'checkpoint_events'/(head_sha[:16]+'.json'))
   assert event['checkpoint_sha256']==head_sha and event['completed_epochs']==expected_n and event['previous_epochs']==expected_n-1
   chain.append(event);head_sha=event['previous_checkpoint_sha256'];expected_n-=1
  change['event_chain']=chain
  change['chain_reaches_726_checkpoint']=expected_n==pn and head_sha==old['checkpoint_sha256']
  if detail['hashed_new_checkpoint_files']==0 and change['new_job_log_matches_current_epoch']:
   path=folder/'continuation.pt';h=hashlib.sha256()
   head_before=(folder/'checkpoint_head.json').read_bytes()
   with path.open('rb') as stream:
    before=os.fstat(stream.fileno())
    for block in iter(lambda:stream.read(1024*1024),b''):h.update(block)
    after=os.fstat(stream.fileno())
   end=path.stat()
   stable=(before.st_ino,before.st_size,before.st_mtime_ns)==(after.st_ino,after.st_size,after.st_mtime_ns)==(end.st_ino,end.st_size,end.st_mtime_ns) and (folder/'checkpoint_head.json').read_bytes()==head_before
   change['new_checkpoint_byte_check']=dict(sha256=h.hexdigest(),bytes=before.st_size,stable_during_read=stable,matches_committed_head=h.hexdigest()==current['checkpoint_sha256_from_committed_head'])
   detail['hashed_new_checkpoint_files']+=1
  detail['changed_members'].append(change)
detail['total_current_branch_member_epochs']=sum(x['completed_epochs'] for x in row['members'].values())
detail['runtime_binding_matches_job']=bool(row.get('runtime_binding') and row['runtime_binding']['job_id']==TARGET_JOB)
binding=row.get('runtime_binding') or {}
detail['runtime_binding_matches_frozen_identity']=bool(binding.get('code_hash')==row['authorization']['code_hash'] and binding.get('protocol_sha256')==row['authorization']['protocol_sha256'] and binding.get('device_identity')==row['authorization']['device_identity'])
active=[x.split('|') for x in report['queue']['stdout'].splitlines() if len(x.split('|'))>=4 and x.split('|')[3]==str(root)]
detail['active_same_root_jobs']=active
detail['single_expected_running_job']=len(active)==1 and active[0][0]==TARGET_JOB and active[0][2]=='RUNNING'
detail['first_progress_verified']=bool(row['job_id']==TARGET_JOB and detail['new_complete_member_epochs']>0 and detail['runtime_binding_matches_job'] and detail['runtime_binding_matches_frozen_identity'] and detail['single_expected_running_job'] and not row['failure_records'] and any(x['chain_reaches_726_checkpoint'] and x['new_job_log_matches_current_epoch'] and x.get('new_checkpoint_byte_check',{}).get('matches_committed_head') and x.get('new_checkpoint_byte_check',{}).get('stable_during_read') for x in detail['changed_members']))
detail['source_checked_at_utc']=datetime.datetime.now(datetime.timezone.utc).isoformat()
report['target245929_first_progress']=detail
allowed_roots={x['root'] for group in (report['cases'],report.get('legacy_small_cases',{})) for x in group.values()}
report['queue']['stdout']='\n'.join(line for line in report['queue']['stdout'].splitlines() if len(line.split('|'))>=4 and line.split('|')[3] in allowed_roots)+'\n'
report['queue']['scope_filter_applied']=True

report['scope_finished_at_utc']=datetime.datetime.now(datetime.timezone.utc).isoformat()
print(json.dumps(report,sort_keys=True),flush=True)

READ_FIXED200_003
