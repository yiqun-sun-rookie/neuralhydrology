#!/usr/bin/env bash
set -euo pipefail
export PYTHONNOUSERSITE=1 PYTHONDONTWRITEBYTECODE=1

/data1/home/sunyiq/miniconda3/envs/knet_clean/bin/python -B - <<'PY'
from __future__ import annotations

import hashlib
import json
from pathlib import Path
import stat
import subprocess
import xml.etree.ElementTree as ET

import numpy as np


PHASE = Path('/data1/home/sunyiq/kalmannet_tukf09_scaled_noise_local_selection_remaining_453_20260930_attempt1/canary11')
OLD = Path('/data1/home/sunyiq/kalmannet_tukf09_scaled_noise_rehearsal_20260922/full_budget_01142500_20260928_attempt1/bundle')
PREVIOUS_WRAPPER = Path('/data1/home/sunyiq/kalmannet_tukf09_scaled_noise_rehearsal_20260922/full_budget_01142500_20260929_attempt2/tukf09_full_budget_01142500_20260929.py')
JOB_ID = '233308'
PAYLOAD_SHA = 'c6cd14d7a72815e71dc4e3be9b679a04206029dbbd1f51beabd26fe47561f137'
OLD_MANIFEST_SHA = '4ebee2dcbd215e9751c86ca9895b84090956e7857d84b524fc87d60a3ea6afa1'
SCIENCE_SHA = 'b4b70d97e4fdeca92ef1a7a8a6335a41d45acead5b40db5bdf1ab92ff70a3a5e'
CONTRACT_SHA = '27239212680bd370bd76f40e53337b7d68d80cbe4dc01feac2164bab4917f8a1'
PREVIOUS_WRAPPER_SHA = '52a79db0169082449c8ea10548f957a7f1a38b4a9fdba84eefa96b5a188cf60a'
CANARIES = (
    ('01052500', 7), ('01031500', 8), ('01162500', 9), ('01022500', 10),
    ('02202600', 11), ('02297310', 12), ('01139000', 13), ('02296500', 15),
    ('02108000', 17), ('04040500', 18), ('01411300', 20),
)
SUCCESS = {0, 1, 2, 3, 7, 9, 10}
WATCHDOG_FAILURE = {4: (151, 150), 5: (144, 143), 6: (127, 126)}
GATE_FAILURE = 8
COUNTS = {
    'start_count': 8,
    'updates_per_start': 31,
    'checkpoints': 256,
    'gradient_updates': 248,
    'training_objective_calls': 256,
    'validation_objective_calls': 256,
    'evaluation_array_reads': 0,
}
SELECTION_ORDER = [
    'minimum validation objective',
    'minimum training objective',
    'lexicographically smallest actual process-variance vector',
    'smallest checkpoint index',
]


def require(condition: bool, message: str) -> None:
    if not condition:
        raise RuntimeError(message)


def sha(path: Path) -> str:
    require(path.is_file() and not path.is_symlink(), 'missing, linked, or non-file evidence: ' + str(path))
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def load_json(path: Path) -> dict:
    require(path.is_file() and not path.is_symlink(), 'missing or linked JSON evidence: ' + str(path))
    return json.loads(path.read_text(encoding='utf-8'))


def command(arguments: list[str]) -> dict:
    result = subprocess.run(arguments, text=True, capture_output=True, timeout=30)
    return {'exit_code': result.returncode, 'stdout': result.stdout, 'stderr': result.stderr}


def junit_counts(path: Path) -> tuple[int, int, int, int]:
    require(path.is_file() and not path.is_symlink(), 'missing or linked test report: ' + str(path))
    root = ET.fromstring(path.read_bytes())
    if root.tag == 'testsuite':
        suites = [root]
    elif root.tag == 'testsuites' and 'tests' in root.attrib:
        suites = [root]
    else:
        suites = list(root.iter('testsuite'))
    require(bool(suites), 'test report contains no suite: ' + str(path))
    return tuple(
        sum(int(suite.attrib.get(name, '0')) for suite in suites)
        for name in ('tests', 'failures', 'errors', 'skipped')
    )


def verify_manifest(root: Path, manifest: dict, expected_schema: str, expected_status: str) -> None:
    require(manifest.get('schema_version') == expected_schema, 'manifest schema changed: ' + str(root))
    require(manifest.get('status') == expected_status, 'manifest status changed: ' + str(root))
    files = manifest.get('files')
    require(isinstance(files, dict) and manifest.get('file_count') == len(files), 'manifest file count changed: ' + str(root))
    for name, record in files.items():
        path = root / name
        require(path.is_file() and not path.is_symlink(), 'manifest member missing or linked: ' + str(path))
        require(path.stat().st_size == record.get('size_bytes') and sha(path) == record.get('sha256'),
                'manifest member hash or size mismatch: ' + str(path))


def parse_progress(path: Path) -> tuple[list[dict], int, int]:
    require(path.is_file() and not path.is_symlink(), 'progress log missing or linked: ' + str(path))
    raw = path.read_bytes()
    require(raw.endswith(b'\n'), 'progress log has an incomplete tail: ' + str(path))
    events = [json.loads(line) for line in raw.decode('utf-8').splitlines()]
    require([event.get('event_index') for event in events] == list(range(1, len(events) + 1)),
            'progress event sequence changed: ' + str(path))
    checkpoints = sum(event.get('type') == 'checkpoint' for event in events)
    updates = sum(event.get('type') == 'gradient_update' for event in events)
    cursor = 0
    for checkpoint in range(1, checkpoints + 1):
        require(cursor < len(events), 'progress checkpoint missing: ' + str(path))
        event = events[cursor]
        cursor += 1
        require(
            event.get('type') == 'checkpoint'
            and event.get('checkpoint') == checkpoint
            and event.get('start_index') == (checkpoint - 1) % 8
            and event.get('update_index') == (checkpoint - 1) // 8
            and event.get('training_calls') == checkpoint
            and event.get('validation_calls') == checkpoint
            and event.get('gradient_updates') == min(checkpoint - 1, updates, 248)
            and event.get('training_objective_wall_ns', 0) > 0
            and event.get('validation_objective_wall_ns', 0) > 0,
            'progress checkpoint record changed: ' + str(path) + ':' + str(checkpoint),
        )
        if checkpoint <= updates:
            require(cursor < len(events), 'progress update missing: ' + str(path))
            update = events[cursor]
            cursor += 1
            require(
                update.get('type') == 'gradient_update'
                and update.get('gradient_update') == checkpoint
                and update.get('training_calls') == checkpoint
                and update.get('validation_calls') == checkpoint
                and update.get('optimizer_wall_ns', 0) > 0,
                'progress update record changed: ' + str(path) + ':' + str(checkpoint),
            )
    require(cursor == len(events), 'progress event tail changed: ' + str(path))
    return events, checkpoints, updates


require(PHASE.is_dir() and not PHASE.is_symlink(), 'isolated canary root missing or linked')
require(OLD.is_dir() and not OLD.is_symlink(), 'sealed parent bundle missing or linked')
require(sha(PHASE / 'payload_manifest.json') == PAYLOAD_SHA, 'payload manifest hash changed')
require(sha(OLD / 'bundle_manifest.json') == OLD_MANIFEST_SHA, 'sealed parent manifest hash changed')
require(sha(OLD / 'hpc/tukf09_455_scaled_noise_common_v1.py') == SCIENCE_SHA, 'frozen science source hash changed')
require(sha(OLD / 'hpc/tukf09_455_scaled_noise_local_transfer_contract_v1.json') == CONTRACT_SHA,
        'frozen science contract hash changed')
require(sha(PREVIOUS_WRAPPER) == PREVIOUS_WRAPPER_SHA,
        'sealed previous wrapper hash changed')

payload = load_json(PHASE / 'payload_manifest.json')
expected_canaries = [
    {'array_index': index, 'basin_id': basin, 'state_dimension': dimension}
    for index, (basin, dimension) in enumerate(CANARIES)
]
require(
    payload.get('schema_version') == 'tukf09_remaining453_canary11_payload_v1'
    and payload.get('canaries') == expected_canaries
    and payload.get('maximum_scheduler_submissions') == 1
    and payload.get('maximum_concurrent_tasks') == 4
    and payload.get('cpus_per_task') == 1
    and payload.get('wall_seconds_per_task') == 28800
    and payload.get('memory_limit_bytes_per_task') == 8 * 2**30
    and payload.get('output_limit_bytes_per_task') == 100 * 2**20
    and payload.get('old_manifest_sha256') == OLD_MANIFEST_SHA
    and payload.get('science_source_sha256') == SCIENCE_SHA
    and payload.get('science_contract_sha256') == CONTRACT_SHA
    and payload.get('previous_wrapper_sha256') == PREVIOUS_WRAPPER_SHA
    and payload.get('evaluation_array_reads') == 0
    and payload.get('formal_evaluation_authorized') is False
    and payload.get('transfer_library_authorized') is False
    and payload.get('automatic_retry_authorized') is False
    and payload.get('scientific_contract_changes_authorized') is False
    and payload.get('old_evidence_overwrite_authorized') is False,
    'payload identity, resource budget, or authority boundary changed',
)
for name, record in payload['files'].items():
    path = PHASE / name
    require(path.stat().st_size == record['size_bytes'] and sha(path) == record['sha256'],
            'deployed payload member changed: ' + name)

authorization = load_json(PHASE / 'canary11_authorization.json')
metadata = load_json(PHASE / 'canary11_metadata.json')
require(
    authorization.get('authorized_basin_count') == 11
    and authorization.get('maximum_concurrent_tasks') == 4
    and authorization.get('maximum_scheduler_submissions') == 1
    and authorization.get('automatic_retry_or_requeue_authorized') is False
    and authorization.get('formal_evaluation_authorized') is False
    and authorization.get('transfer_library_authorized') is False
    and authorization.get('scientific_contract_changes_authorized') is False
    and authorization.get('old_evidence_overwrite_authorized') is False
    and metadata.get('canary_count') == 11
    and metadata.get('canary_selection_rule') == 'first unrun basin in frozen population order for each observed state dimension'
    and metadata.get('completed_excluded_basins') == ['01047000', '01142500']
    and metadata.get('evaluation_array_reads') == 0,
    'authorization or canary selection evidence changed',
)

attempt = load_json(PHASE / 'control/submission_attempt.json')
submission = load_json(PHASE / 'control/submission.json')
require(
    attempt.get('status') == 'CANARY11_ARRAY_SUBMISSION_CONSUMED_OUTCOME_UNKNOWN_UNTIL_RECEIPT'
    and attempt.get('maximum_scheduler_submissions') == 1
    and attempt.get('maximum_concurrent_tasks') == 4
    and attempt.get('array_indices') == '0-10'
    and attempt.get('evaluation_array_reads') == 0
    and attempt.get('automatic_retry_or_requeue_authorized') is False
    and attempt.get('formal_evaluation_authorized') is False
    and attempt.get('transfer_library_authorized') is False
    and submission.get('status') == 'CANARY11_ARRAY_SUBMISSION_CONFIRMED_NOT_MODEL_COMPLETION'
    and submission.get('job_id') == JOB_ID
    and submission.get('raw_sbatch_output') == JOB_ID
    and submission.get('scheduler_submission_count') == 1
    and submission.get('array_indices') == '0-10'
    and submission.get('maximum_concurrent_tasks') == 4
    and submission.get('slurm_script_sha256') == payload['files']['canary11_full_budget.slurm']['sha256']
    and submission.get('evaluation_array_reads') == 0
    and submission.get('automatic_retry_or_requeue_authorized') is False
    and submission.get('formal_evaluation_authorized') is False
    and submission.get('transfer_library_authorized') is False,
    'unique scheduler submission evidence changed',
)

contract = load_json(OLD / 'hpc/tukf09_455_scaled_noise_local_transfer_contract_v1.json')
local_contract = contract['local_scaled_process_noise']
optimizer = local_contract['optimizer']
lower = float(local_contract['common_ratio_lower'])
upper = float(local_contract['common_ratio_upper'])
tolerance = float(local_contract['rho_q_round_trip_absolute_tolerance'])
require(
    lower == 1e-4
    and upper == 1.0
    and local_contract['objective']['selection_order'] == SELECTION_ORDER
    and optimizer.get('start_count') == 8
    and optimizer.get('updates_per_start') == 31
    and optimizer.get('checkpoints_per_basin') == 256
    and optimizer.get('backpropagations_per_basin') == 248
    and optimizer.get('early_stopping') is False,
    'frozen budget, process-noise bounds, or selection order changed',
)

sacct = command([
    'sacct', '-X', '-j', JOB_ID, '--array', '--noheader', '--parsable2',
    '--format=JobID,JobIDRaw,ArrayTaskID,JobName,Partition,AllocCPUS,ElapsedRaw,State,ExitCode,Start,End,Timelimit,MaxRSS',
])
squeue = command(['squeue', '-j', JOB_ID, '-h', '-o', '%i|%j|%T|%R|%M'])
require(sacct['exit_code'] == 0 and not sacct['stderr'], 'terminal scheduler accounting query failed')
require(not squeue['stdout'] and (squeue['exit_code'] == 0 or 'Invalid job id specified' in squeue['stderr']),
        'array still present in queue or queue query failed unexpectedly')

rows = []
total_checkpoints = 0
total_updates = 0
for index, (basin, dimension) in enumerate(CANARIES):
    root = PHASE / ('basin_' + basin)
    control = root / 'control'
    run = root / 'run'
    model = run / 'model'
    progress = run / 'progress'
    require(root.is_dir() and not root.is_symlink() and control.is_dir() and not control.is_symlink(),
            'basin root or control evidence missing or linked: ' + basin)
    deployment = load_json(control / 'deployment.json')
    require(
        deployment.get('status') == 'CANARY11_BASIN_STAGED_NOT_SUBMITTED'
        and deployment.get('array_index') == index
        and deployment.get('basin_id') == basin
        and deployment.get('state_dimension') == dimension,
        'basin deployment evidence changed: ' + basin,
    )
    meta = metadata['basins'][basin]
    require(meta.get('array_index') == index and meta.get('dimension') == dimension
            and len(meta.get('state_scale', [])) == dimension,
            'basin metadata identity or state scale changed: ' + basin)

    if index != GATE_FAILURE:
        gate = load_json(control / 'job_gate.json')
        canary_gate = load_json(control / 'canary_gate.json')
        gate_keys = (
            'original_linux_protection_tests', 'final_output_guard_regressions',
            'new_standard_library_gate_tests', 'synthetic_tensor_loop_tests',
        )
        require(
            [gate[key]['tests'] for key in gate_keys] == [41, 3, 44, 14]
            and all(gate[key]['failures'] == gate[key]['errors'] == gate[key]['skipped'] == 0 for key in gate_keys)
            and gate.get('status') == 'ALL_JOB_TESTS_PASSED_MODEL_MAY_START'
            and gate.get('model_calls') == 0
            and gate.get('evaluation_array_reads') == 0
            and canary_gate.get('status') == 'CANARY11_NODE_GATE_PASSED_MODEL_MAY_START'
            and canary_gate.get('array_index') == index
            and canary_gate.get('basin_id') == basin
            and canary_gate.get('state_dimension') == dimension
            and canary_gate.get('test_counts') == [41, 3, 44, 14]
            and canary_gate.get('total_tests') == 102
            and canary_gate.get('evaluation_array_reads') == 0
            and canary_gate.get('formal_evaluation') is False,
            '102-test compute-node gate evidence changed: ' + basin,
        )
        for name, expected in (
            ('original_tests.xml', 41), ('output_guard_regression.xml', 3),
            ('new_gate_tests.xml', 44), ('tensor_tests/tensor_tests.xml', 14),
        ):
            require(junit_counts(control / name) == (expected, 0, 0, 0),
                    'compute-node test report changed: ' + basin + '/' + name)
        started = load_json(model / 'started.json')
        require(
            started.get('status') == 'CANARY11_MODEL_STARTED'
            and started.get('array_index') == index
            and started.get('basin_id') == basin
            and started.get('dimension') == dimension
            and started.get('counts_authorized') == COUNTS
            and started.get('frozen_science_source_sha256') == SCIENCE_SHA
            and started.get('science_contract_sha256') == CONTRACT_SHA
            and started.get('fixed_observation_noise_multiplier') == meta['fixed_r_b']
            and started.get('state_scale') == meta['state_scale']
            and started.get('evaluation_array_reads') == 0
            and started['runtime']['python'].startswith('3.11.13')
            and started['runtime']['numpy'] == '1.26.4'
            and started['runtime']['torch'].startswith('2.2.2')
            and started['runtime']['torch_threads'] == 1
            and started['runtime']['torch_interop_threads'] == 1
            and started['runtime']['device'] == 'cpu'
            and started['runtime']['precision'] == 'float64',
            'model-start, state-scale, fixed-noise, source, or runtime evidence changed: ' + basin,
        )
        events, checkpoints, updates = parse_progress(progress / 'progress.jsonl')
        total_checkpoints += checkpoints
        total_updates += updates
    else:
        require(junit_counts(control / 'original_tests.xml') == (41, 1, 0, 0),
                'gate-failure test counts changed: ' + basin)
        xml_text = (control / 'original_tests.xml').read_text(encoding='utf-8')
        require('test_parent_death' in xml_text and "invalid literal for int() with base 10: ''" in xml_text,
                'gate-failure identity changed: ' + basin)
        require(not (control / 'job_gate.json').exists() and not (control / 'canary_gate.json').exists(),
                'gate-failed basin unexpectedly passed the gate: ' + basin)
        require(not run.exists(), 'gate-failed basin unexpectedly started a model: ' + basin)
        rows.append({
            'array_index': index, 'basin_id': basin, 'state_dimension': dimension,
            'terminal_class': 'gate_failure_before_model_start', 'gate_tests_passed': 40,
            'gate_tests_total': 41, 'failed_test': 'test_parent_death',
            'checkpoints': 0, 'gradient_updates': 0, 'result_triplet_complete': False,
            'evaluation_array_reads': 0,
        })
        continue

    supervisor = load_json(run / 'supervisor.json')
    if index in SUCCESS:
        require(checkpoints == 256 and updates == 248 and len(events) == 504,
                'successful basin budget changed: ' + basin)
        progress_complete = load_json(progress / 'progress_complete.json')
        require(
            progress_complete == {
                'status': 'CANARY11_PROGRESS_COMPLETE', 'array_index': index,
                'basin_id': basin, 'events': 504, 'checkpoints': 256,
                'training_objective_calls': 256, 'validation_objective_calls': 256,
                'gradient_updates': 248, 'evaluation_array_reads': 0,
            },
            'progress-completion record changed: ' + basin,
        )
        progress_manifest = load_json(progress / 'progress_manifest.sha256.json')
        verify_manifest(progress, progress_manifest, 'tukf09_remaining453_canary11_progress_v1',
                        'CANARY11_PROGRESS_COMPLETE')
        require(set(progress_manifest['files']) == {'progress.jsonl', 'progress_complete.json'},
                'progress manifest members changed: ' + basin)

        summary = load_json(model / 'summary.json')
        final_manifest = load_json(model / 'manifest.final.sha256.json')
        verify_manifest(model, final_manifest, 'tukf09_remaining453_canary11_result_manifest_v1',
                        'CANARY11_SINGLE_BASIN_COMPLETE')
        require(set(final_manifest['files']) == {'started.json', 'history.npz', 'summary.json'},
                'final result manifest members changed: ' + basin)
        require(
            summary.get('status') == 'CANARY11_SINGLE_BASIN_COMPLETE_NOT_FORMAL_EVALUATION'
            and summary.get('basin_id') == basin
            and summary.get('dimension') == dimension
            and summary.get('counts') == COUNTS
            and summary.get('fixed_observation_noise_multiplier') == meta['fixed_r_b']
            and summary.get('evaluation_array_reads') == 0
            and summary.get('scientific_performance_claim') is False,
            'successful result summary boundary changed: ' + basin,
        )
        require(
            supervisor.get('success') is True
            and supervisor.get('reason') == 'complete'
            and supervisor.get('exit_code') == 0
            and 0 < supervisor.get('wall_seconds', 0) < 28800
            and supervisor.get('peak_tree_rss_bytes', 8 * 2**30) < 8 * 2**30
            and supervisor.get('output_bytes', 100 * 2**20) < 100 * 2**20,
            'successful supervisor result changed: ' + basin,
        )

        with np.load(model / 'history.npz', allow_pickle=False) as archive:
            require(set(archive.files) == {
                'checkpoint_index', 'start_index', 'update_index', 'theta_log',
                'process_variance_actual', 'training_objective', 'validation_objective',
                'sealed_state_scale',
            }, 'history array member set changed: ' + basin)
            arrays = {name: np.array(archive[name], copy=True) for name in archive.files}
        require(
            arrays['checkpoint_index'].dtype == np.dtype('int64')
            and arrays['start_index'].dtype == np.dtype('int64')
            and arrays['update_index'].dtype == np.dtype('int64')
            and all(arrays[name].dtype == np.dtype('float64') for name in (
                'theta_log', 'process_variance_actual', 'training_objective',
                'validation_objective', 'sealed_state_scale')),
            'history array dtype changed: ' + basin,
        )
        require(
            arrays['theta_log'].shape == (256, dimension)
            and arrays['process_variance_actual'].shape == (256, dimension)
            and arrays['training_objective'].shape == (256,)
            and arrays['validation_objective'].shape == (256,)
            and arrays['sealed_state_scale'].shape == (dimension,)
            and np.array_equal(arrays['checkpoint_index'], np.arange(256, dtype=np.int64))
            and np.array_equal(arrays['start_index'], np.tile(np.arange(8, dtype=np.int64), 32))
            and np.array_equal(arrays['update_index'], np.repeat(np.arange(32, dtype=np.int64), 8))
            and all(np.all(np.isfinite(arrays[name])) for name in arrays),
            'history shape, order, or finite-value check failed: ' + basin,
        )
        scale = np.asarray(meta['state_scale'], dtype=np.float64)
        require(np.array_equal(arrays['sealed_state_scale'], scale),
                'history state scale differs from frozen metadata: ' + basin)
        require(np.allclose(np.exp(arrays['theta_log']), arrays['process_variance_actual'], rtol=3e-15, atol=0.0),
                'log process-noise coordinates do not decode to variances: ' + basin)
        ratio = np.sqrt(arrays['process_variance_actual']) / scale[None, :]
        require(np.all(ratio >= lower - tolerance) and np.all(ratio <= upper + tolerance),
                'process-noise ratio left the frozen range: ' + basin)
        clipped = np.clip(ratio, lower, upper)
        lower_hits = int(np.count_nonzero(np.abs(clipped - lower) <= tolerance))
        upper_hits = int(np.count_nonzero(np.abs(clipped - upper) <= tolerance))
        clip_count = int(np.count_nonzero(clipped != ratio))
        require(
            lower_hits == summary.get('ratio_lower_bound_hits')
            and upper_hits == summary.get('ratio_upper_bound_hits')
            and clip_count == summary.get('roundoff_ratio_clip_count'),
            'process-noise bound accounting changed: ' + basin,
        )
        training = arrays['training_objective']
        validation = arrays['validation_objective']
        process_variance = arrays['process_variance_actual']
        selected = min(range(256), key=lambda checkpoint: (
            float(validation[checkpoint]), float(training[checkpoint]),
            tuple(float(value) for value in process_variance[checkpoint]), checkpoint,
        ))
        require(
            selected == summary.get('selected_index')
            and float(training[selected]) == summary.get('selected_training_objective')
            and float(validation[selected]) == summary.get('selected_validation_objective')
            and np.array_equal(process_variance[selected],
                               np.asarray(summary.get('selected_process_variance'), dtype=np.float64)),
            'independent checkpoint selection differs from summary: ' + basin,
        )
        rows.append({
            'array_index': index, 'basin_id': basin, 'state_dimension': dimension,
            'terminal_class': 'technical_completion', 'gate_tests_passed': 102,
            'model_started': True, 'checkpoints': checkpoints, 'gradient_updates': updates,
            'result_triplet_complete': True,
            'history_sha256': sha(model / 'history.npz'),
            'summary_sha256': sha(model / 'summary.json'),
            'final_manifest_sha256': sha(model / 'manifest.final.sha256.json'),
            'state_scale_matches_frozen_metadata': True,
            'fixed_observation_noise_multiplier': meta['fixed_r_b'],
            'fixed_observation_noise_matches_frozen_metadata': True,
            'process_noise_ratio_minimum': float(np.min(ratio)),
            'process_noise_ratio_maximum': float(np.max(ratio)),
            'independent_selected_index': selected,
            'summary_selected_index': summary['selected_index'],
            'selection_order': SELECTION_ORDER,
            'evaluation_array_reads': 0,
        })
    else:
        expected_checkpoints, expected_updates = WATCHDOG_FAILURE[index]
        require(checkpoints == expected_checkpoints and updates == expected_updates,
                'watchdog-failure partial budget changed: ' + basin)
        require(
            supervisor.get('success') is False
            and supervisor.get('reason') == 'watchdog_exited'
            and supervisor.get('exit_code') == -9
            and 0 < supervisor.get('wall_seconds', 0) < 28800
            and supervisor.get('peak_tree_rss_bytes', 8 * 2**30) < 8 * 2**30,
            'watchdog-failure supervisor evidence changed: ' + basin,
        )
        require(not (model / 'history.npz').exists() and not (model / 'summary.json').exists()
                and not (model / 'manifest.final.sha256.json').exists()
                and not (progress / 'progress_complete.json').exists()
                and not (progress / 'progress_manifest.sha256.json').exists(),
                'watchdog-failed basin unexpectedly has completion evidence: ' + basin)
        rows.append({
            'array_index': index, 'basin_id': basin, 'state_dimension': dimension,
            'terminal_class': 'watchdog_failure_after_model_start', 'gate_tests_passed': 102,
            'model_started': True, 'checkpoints': checkpoints, 'gradient_updates': updates,
            'supervisor_reason': 'watchdog_exited', 'worker_exit_code': -9,
            'result_triplet_complete': False, 'exact_watchdog_exit_cause': 'undetermined_from_preserved_evidence',
            'evaluation_array_reads': 0,
        })

error_logs = []
for path in sorted((PHASE / 'logs').glob('*.err')):
    require(path.is_file() and not path.is_symlink(), 'scheduler error log missing, linked, or non-file')
    if path.stat().st_size:
        error_logs.append({'path': path.relative_to(PHASE).as_posix(), 'size_bytes': path.stat().st_size,
                           'sha256': sha(path)})
require(len(error_logs) == 1 and error_logs[0]['path'] == 'logs/task-233308_8.err',
        'nonempty scheduler error-log set changed')

tree_records = []
for path in sorted(PHASE.rglob('*')):
    relative = path.relative_to(PHASE).as_posix()
    mode = path.lstat().st_mode
    require(not path.is_symlink(), 'linked terminal evidence is forbidden: ' + relative)
    if stat.S_ISDIR(mode):
        continue
    require(stat.S_ISREG(mode), 'nonregular terminal evidence is forbidden: ' + relative)
    tree_records.append((relative, path.stat().st_size, sha(path)))
tree_digest = hashlib.sha256()
for relative, size, digest in tree_records:
    tree_digest.update(relative.encode('utf-8') + b'\0' + str(size).encode('ascii') + b'\0' + digest.encode('ascii') + b'\n')

require(len(rows) == 11 and total_checkpoints == 2214 and total_updates == 2155,
        'terminal aggregate budget changed')
require(sum(row['terminal_class'] == 'technical_completion' for row in rows) == 7,
        'successful terminal count changed')
require(sum(row['terminal_class'].endswith('failure_after_model_start') for row in rows) == 3,
        'watchdog-failure count changed')
require(sum(row['terminal_class'] == 'gate_failure_before_model_start' for row in rows) == 1,
        'gate-failure count changed')

report = {
    'status': 'CANARY11_TERMINAL_INDEPENDENT_TECHNICAL_AUDIT_COMPLETE_WITH_FAILURES',
    'job_id': JOB_ID,
    'scheduler_submission_count': 1,
    'scheduler_accounting': sacct,
    'post_terminal_queue': squeue,
    'canaries': rows,
    'counts': {
        'basins': 11,
        'technical_completions': 7,
        'watchdog_failures_after_model_start': 3,
        'gate_failures_before_model_start': 1,
        'node_gates_passed': 10,
        'models_started': 10,
        'complete_result_triplets': 7,
        'total_checkpoints': total_checkpoints,
        'total_gradient_updates': total_updates,
        'nonempty_scheduler_error_logs': len(error_logs),
    },
    'payload_manifest_sha256': PAYLOAD_SHA,
    'frozen_parent_manifest_sha256': OLD_MANIFEST_SHA,
    'frozen_science_source_sha256': SCIENCE_SHA,
    'frozen_science_contract_sha256': CONTRACT_SHA,
    'process_noise_ratio_lower_bound': lower,
    'process_noise_ratio_upper_bound': upper,
    'checkpoint_selection_order': SELECTION_ORDER,
    'canary_selection_rule': metadata['canary_selection_rule'],
    'terminal_tree_file_count': len(tree_records),
    'terminal_tree_total_bytes': sum(size for _, size, _ in tree_records),
    'terminal_tree_manifest_sha256': tree_digest.hexdigest(),
    'nonempty_scheduler_error_logs': error_logs,
    'evaluation_array_reads': 0,
    'formal_evaluation_performed': False,
    'scientific_performance_claim': False,
    'transfer_library_constructed': False,
    'automatic_retry_performed': False,
    'later_waves_started': False,
    'later_waves_stopped': True,
    'scheduler_mutation_performed': False,
    'model_execution_started_by_audit': False,
}
print('CANARY11_TERMINAL_INDEPENDENT_AUDIT ' + json.dumps(report, sort_keys=True, separators=(',', ':')))
PY
