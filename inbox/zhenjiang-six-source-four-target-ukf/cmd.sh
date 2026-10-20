#!/usr/bin/env bash
set -eo pipefail
source /data1/home/sunyiq/miniconda3/etc/profile.d/conda.sh
conda activate nh_final
set -u
export CUDA_VISIBLE_DEVICES=""
export PYTHONDONTWRITEBYTECODE=1
export OMP_NUM_THREADS=2
python -B - <<'BOUNDARY_003'
"""Read-only source/configuration preflight; stage data receipts without training.

Usage on HPC: python -B check_boundary.py
Reads the two complete historical-capacity cases and already admitted 2017--2022
NPZ files. Writes only a new boundary evidence directory. No trainer, optimizer
step, tide refit, scheduler mutation, source write, or activation is performed.
"""
import copy
import datetime
import gc
import hashlib
import importlib
import json
from pathlib import Path
import shutil
import subprocess
import sys

import torch

BASE = Path('/data1/home/sunyiq')
DEST = BASE / 'zhenjiang_fixed200_003_boundary_20261020_001'
OLD = BASE / 'zhenjiang_fixed200_003_candidates_20261019_002'
ARCHIVE = BASE / 'zhenjiang_fixed200_003_sources_20261019_001'
CASES = {
    'explicit_gru__historical_capacity': ('sqrt_gru_recovery', BASE / 'zhenjiang_complete_comparison_20261017_sqrt_recovery_001', '244445'),
    'legacy_lstm__historical_capacity': ('base', BASE / 'zhenjiang_complete_comparison_20261006_002', '236707'),
}


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def stable(path):
    for _ in range(3):
        before = path.stat()
        raw = path.read_bytes()
        after = path.stat()
        if (before.st_size, before.st_mtime_ns) == (after.st_size, after.st_mtime_ns) and len(raw) == after.st_size:
            return raw
    raise ValueError('source replaced during read: ' + str(path))


def read(path):
    return json.loads(stable(path))


def write(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open('x') as handle:
        json.dump(value, handle, sort_keys=True, indent=2, allow_nan=False)
        handle.write('\n')


def query(command):
    result = subprocess.run(command, text=True, capture_output=True, timeout=30)
    return {'command': command, 'returncode': result.returncode, 'stdout': result.stdout, 'stderr': result.stderr}


def scheduler():
    return [query(['squeue', '-h', '-u', 'sunyiq', '-o', '%i|%j|%T|%R|%M|%N|%Z|%o']),
            query(['sacct', '-n', '-X', '-j', '236706,236707,237928,244445', '--format=JobID,State,ExitCode,Elapsed,NodeList', '-P']),
            query(['scontrol', 'show', 'job', '236707']), query(['scontrol', 'show', 'job', '244445'])]


def differences(left, right, prefix=''):
    if isinstance(left, dict) and isinstance(right, dict):
        result = []
        for key in sorted(set(left) | set(right)):
            path = prefix + '.' + key if prefix else key
            result.extend([path] if key not in left or key not in right else differences(left[key], right[key], path))
        return result
    return [] if left == right else [prefix]


assert not DEST.exists(), 'existing boundary evidence must be reconciled, never replayed'
DEST.mkdir()
torch.set_num_threads(2)
report = {'schema': 'fixed200-inactive-boundary-check-v1',
          'started_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
          'activated': False, 'training_steps': 0, 'tide_fits': 0,
          'old_jobs_modified': False, 'source_writes': False, 'evaluation_values_read': False,
          'candidate_root': str(OLD), 'evidence_root': str(DEST),
          'scheduler_before': scheduler(), 'cases': {}, 'foundation_sources': [], 'errors': []}
previous = read(OLD / 'candidate_report.json')
preserved = read(ARCHIVE / 'preservation_report.json')
catalogue = read(OLD / 'release/stage_source_admission.json')

# Check the original complete-400 identity, rather than regenerating its seal.
for group, source in catalogue['sources'].items():
    row = {'group': group, 'members': []}
    report['foundation_sources'].append(row)
    try:
        original = Path(source['outcome_sample_root']) / source['original_outcome_path']
        raw = stable(original)
        assert sha(raw) == source['original_outcome_sha256']
        assert json.loads(raw)['seal'] == source['seal']
        row['original_outcome_sha256'] = sha(raw)
        for rid, member in source['seal']['member_evidence'].items():
            raw = stable(Path(member['checkpoint_path']))
            assert sha(raw) == member['checkpoint_sha256']
            assert member['epochs'] == len(member['validation_mae']) == 400
            row['members'].append({'run_id': rid, 'epochs': 400, 'sha256': sha(raw)})
        row['verified_original400'] = True
    except Exception as error:
        row['error'] = type(error).__name__ + ': ' + str(error)
        report['errors'].append({'group': group, 'error': row['error']})

for case, (variant, original_root, job) in CASES.items():
    row = {'variant': variant, 'source_root': str(original_root), 'job_id': job,
           'members': [], 'data': {}, 'configuration_regeneration': 'not_checked',
           'hardware_check': 'frozen identity used for CPU regeneration; actual next GPU must match',
           'single_writer_transfer': 'not_performed'}
    report['cases'][case] = row
    try:
        runtime_root = DEST / 'runtimes' / variant
        shutil.copytree(OLD / 'release/runtimes' / variant, runtime_root)
        for key in list(sys.modules):
            if key == 'src' or key.startswith('src.'):
                del sys.modules[key]
        sys.path.insert(0, str(runtime_root))
        sched = importlib.import_module('src.scheduler')
        runtime = importlib.import_module('src.runtime')
        models = importlib.import_module('src.models')
        estimators = importlib.import_module('src.state_estimators')
        cp = importlib.import_module('src.continuation')
        contracts = importlib.import_module('src.contracts')
        protocol_raw = stable(runtime_root / 'configs/protocol-v3.json')
        protocol = json.loads(protocol_raw)
        registry = read(runtime_root / 'configs/registry-v3.json')
        sched.validate_registry(registry, protocol)
        assert not protocol['authority']['formal_training']
        row['staged_runtime'] = str(runtime_root)
        row['code_hash'] = sched.code_identity(runtime_root)
        source_code_hash = sched.code_identity(original_root)
        assert source_code_hash == previous['cases'][case]['source_code_hash']
        row['original_code_hash'] = source_code_hash
        original_prep = read(original_root / 'records/data_preparation_complete.json')
        assert original_prep['status'] == 'admitted' and not original_prep['evaluation_values_read']
        manifests, statistics, data_reports = {}, {}, {}
        for split in ('tuning', 'final'):
            source_dir = original_root / 'prepared' / split
            raw = stable(source_dir / 'manifest.json')
            manifest = json.loads(raw)
            assert manifest['status'] == 'admitted' and not manifest['evaluation_year_reads']
            file_ledger = []
            for entry in manifest['files']:
                assert set(entry['years']).issubset({2017, 2018, 2019, 2020, 2021, 2022})
                path = Path(entry['path'])
                assert sha(stable(path)) == entry['sha256']
                file_ledger.append({'path': str(path), 'sha256': entry['sha256'], 'years': entry['years']})
            # Keep the original absolute paths and manifest bytes. No new tide fit.
            out = runtime_root / 'prepared' / split
            out.mkdir(parents=True, exist_ok=False)
            (out / 'manifest.json').write_bytes(raw)
            tide_raw = stable(source_dir / 'tide_fit.json')
            assert sched.digest_json(json.loads(tide_raw)) == manifest['tide_source_hash']
            (out / 'tide_fit.json').write_bytes(tide_raw)
            phases = {phase: runtime.load_stage(manifest, phase) for phase in (split + '_train', split + '_select')}
            stats = runtime.stats_record(runtime.fit_stage_stats(phases[split + '_train'], manifest))
            previous_admission = read(source_dir / 'admission.json')
            assert stats == previous_admission['statistics']
            assert sched.digest_json(manifest) == previous_admission['manifest_sha256']
            assert original_prep['reports'][split]['statistics'] == stats
            assert original_prep['reports'][split]['manifest_sha256'] == sched.digest_json(manifest)
            detail = {'manifest_sha256': sched.digest_json(manifest), 'manifest_file_sha256': sha(raw),
                      'normalization_hash': sched.digest_json(stats), 'statistics': stats,
                      'tide_source_hash': manifest['tide_source_hash'], 'files_verified': len(file_ledger),
                      'eligible_windows': {p: len(s['eligible']) for p, s in phases.items()},
                      'external_original_paths_preserved': True, 'file_ledger': file_ledger,
                      'evaluation_values_read': False}
            data_reports[split] = detail
            row['data'][split] = {k: v for k, v in detail.items() if k not in ('statistics', 'file_ledger')}
            manifests[split], statistics[split] = manifest, stats
            write(out / 'read_only_revalidation.json', detail)
            del phases
            gc.collect()
        data_receipt = {'status': 'admitted', 'code_hash': row['code_hash'],
                        'schema': 'existing-prepared-data-read-only-revalidation-v1',
                        'source_preparation_receipt_sha256': sha(stable(original_root / 'records/data_preparation_complete.json')),
                        'source_preparation_root': str(original_root), 'reports': data_reports,
                        'fresh_tide_fits_this_operation': 0, 'evaluation_values_read': False,
                        'formal_training_authorized': False}
        write(runtime_root / 'records/data_preparation_complete.json', data_receipt)
        row['data_reuse_receipt_sha256'] = sha(stable(runtime_root / 'records/data_preparation_complete.json'))

        foundation = sched.load_tuning_foundation_source(case + '__tune_foundation_group__seal')
        parent_id = min(foundation['members'], key=lambda k: (min(foundation['members'][k]['validation_mae']), foundation['members'][k]['learning_rate']))
        parent = foundation['members'][parent_id]
        seals = {case + '__tune_foundation_group__seal': contracts.GroupSeal(**foundation['seal'])}
        configs = {}
        old_rows = {r['run_id']: r for r in preserved['cases'][case]}
        for run in [r for r in registry['runs'] if r['case'] == case and r['type'] == 'tune_branch' and r['status'] != 'alias']:
            rid = run['exp_id']
            folder = original_root / 'runs' / rid
            state, source, inspected, cfg_raw, state_raw = cp.load_continuation(folder)
            assert inspected['config_sha256'] == old_rows[rid]['files']['config.json']['sha256']
            assert source['effective_config']['code_hash'] == source_code_hash
            archived = torch.load(ARCHIVE / case / rid / 'continuation.pt', map_location='cpu', weights_only=True)
            n0 = old_rows[rid]['completed_epochs']
            assert state['values'][:n0] == archived['values']
            assert state['train_metrics'][:n0] == archived['train_metrics']
            assert state['shuffle_hashes'][:n0] == archived['shuffle_hashes']
            assert not (folder / 'failure.json').exists()
            batch_count = sum(map(len, state['train_metrics']))
            steps = [float(v['step']) for v in state['optimizer']['state'].values()]
            assert min(steps) == max(steps) == batch_count
            baseline_receipt = read(OLD / 'candidates' / variant / 'runs' / rid / 'migration_source.json')
            assert baseline_receipt['source_checkpoint_sha256'] == old_rows[rid]['files']['continuation.pt']['sha256']
            item = {'run_id': rid, 'snapshot672_epochs': n0, 'current_completed_epochs': inspected['completed_epochs'],
                    'source_checkpoint_sha256': sha(state_raw), 'source_config_sha256': sha(cfg_raw),
                    'snapshot672_histories_preserved': True, 'completed_batch_count': batch_count,
                    'optimizer_step_min': min(steps), 'optimizer_step_max': max(steps),
                    'candidate675_source_checkpoint_sha256': baseline_receipt['source_checkpoint_sha256'],
                    'candidate675_source_is_current': sha(state_raw) == baseline_receipt['source_checkpoint_sha256'],
                    'device_identity': source['effective_config']['device_identity']}
            row['members'].append(item)
            manifest = manifests['tuning']
            identities = {'parent_hash': None, 'parent_run_id': None, 'parent_checkpoint': None, 'parent_best_epoch': None,
                          'initializer_hash': None, 'analysis_initialization_hash': None, 'whitening_hash': None, 'whitening': None,
                          'training_data_hash': sched.digest_json(manifest), 'normalization_hash': sched.digest_json(statistics['tuning']),
                          'tide_source_hash': manifest['tide_source_hash'], 'code_hash': row['code_hash'],
                          'shuffle_hash': sched.digest_json({'seed': run['seed'], 'offset': 200000, 'stride': 12, 'phases': 'epoch_modulo_12'})}
            assert parent['normalization_hash'] == identities['normalization_hash']
            identities.update(parent_run_id=parent_id, parent_hash=parent['checkpoint_sha256'],
                              parent_checkpoint=parent['checkpoint_path'], parent_best_epoch=parent['best_epoch'],
                              initializer_hash=parent['initializer_hash'])
            if run['method'].startswith('encoder'):
                family, capacity = case.split('__')
                branches = estimators.make_branches(models.make_parts(family, capacity, run['seed']), run['seed'] + 100000)
                identities['analysis_initialization_hash'] = estimators.hash_module(branches[run['method']].encoder)
                del branches
            else:
                whitening = read(Path(parent['checkpoint_path']).parent / 'whitening.json')
                identities.update(whitening=whitening, whitening_hash=parent['whitening_hash'])
            effective = sched.resolve_effective_config(run, protocol, run['learning_rate'], identities)
            identity = source['effective_config']['device_identity']
            effective.update(device=identity['device'], device_identity=identity, group_wall_seconds_limit=None,
                             scheduler_continuation=True)
            sched.verify_parent_binding(run, effective, seals)
            configs[rid] = {'status': 'frozen_authorized', 'registration': run,
                            'protocol_sha256': sha(protocol_raw), 'effective_config': effective}
            del state, archived, state_raw
            gc.collect()
        bindings = cp.migration_bindings(runtime_root, case, OLD / 'candidates' / variant / 'runs')
        assert bindings == read(Path(previous['cases'][case]['migration_manifest']))
        write(DEST / 'regenerated_configs' / (case + '_before_binding.json'), configs)
        row['configuration_differences'] = {}
        for rid, expected in configs.items():
            compared = copy.deepcopy(expected)
            compared['effective_config']['continuation_required'] = True
            changed = differences(read(OLD / 'candidates' / variant / 'runs' / rid / 'config.json'), compared)
            if changed:
                row['configuration_differences'][rid] = changed
        bound = cp.bind_migration_configs(configs, bindings, OLD / 'candidates' / variant / 'runs')
        write(DEST / 'regenerated_configs' / (case + '.json'), bound)
        row['configuration_regeneration'] = 'exact_12_of_12_match_with_frozen_GPU_identity'
        row['migration_manifest_digest'] = sched.digest_json(bindings)
        row['device_identities'] = list({json.dumps(x['device_identity'], sort_keys=True) for x in row['members']})
        assert len(row['device_identities']) == 1
        row['stale_candidate_members'] = sum(not x['candidate675_source_is_current'] for x in row['members'])
        row['data_and_config_ready'] = True
        sys.path.remove(str(runtime_root))
    except Exception as error:
        row['error'] = type(error).__name__ + ': ' + str(error)
        report['errors'].append({'case': case, 'error': row['error']})

report['scheduler_after'] = scheduler()
report['finished_utc'] = datetime.datetime.now(datetime.timezone.utc).isoformat()
report['summary'] = {'verified_original400_members': sum(len(s['members']) for s in report['foundation_sources'] if s.get('verified_original400')),
                     'data_and_config_ready_cases': [case for case, row in report['cases'].items() if row.get('data_and_config_ready')],
                     'source_members_checked': sum(len(row['members']) for row in report['cases'].values()),
                     'stale_candidate_members': sum(row.get('stale_candidate_members', 0) for row in report['cases'].values()),
                     'errors': len(report['errors']), 'formal_activation_performed': False}
write(DEST / 'boundary_report.json', report)
print(json.dumps(report, sort_keys=True, allow_nan=False), flush=True)
print(json.dumps({'boundary_report_sha256': sha(stable(DEST / 'boundary_report.json')), 'root': str(DEST)}), flush=True)
if report['errors']:
    sys.exit(2)

BOUNDARY_003
