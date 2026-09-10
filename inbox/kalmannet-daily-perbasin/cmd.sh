#!/bin/bash
set -uo pipefail
task_sequence=96
task_job=224875
[[ "$task_sequence" =~ ^[1-9][0-9]*$ && "$task_job" =~ ^[1-9][0-9]*$ ]] || exit 80
printf 'channel=kalmannet-daily-perbasin sequence=%s purpose=read-only-training-summary-job%s\n' "$task_sequence" "$task_job"
task_root=/data1/home/sunyiq/kalmannet_daily_camels_per_basin_21_development_20260908
task_request=$task_root/runtime/train_08190500_A40_entryrepair_seq91
task_run=$task_root/runs/DAILY_CAMELS_KNET_PER_BASIN_21_DEVELOPMENT_V2_20260908_BASIN_08190500_A40_TRAIN1_SEQ91
for task_path in /data1 /data1/home /data1/home/sunyiq "$task_root" "$task_root/runtime" "$task_request" "$task_root/runs" "$task_run"; do
  [[ -d "$task_path" && ! -L "$task_path" && "$(readlink -f -- "$task_path")" == "$task_path" ]] || exit 81
done
printf '%s\n' 'QUERY_PARENT_ACCOUNTING_BEGIN'
timeout 20s sacct -X -n -P -j "$task_job" --format=JobIDRaw,JobName,State,ExitCode,ElapsedRaw,AllocCPUS,ReqTRES,AllocTRES,NodeList,Submit,Start,End
printf 'QUERY_PARENT_ACCOUNTING_EXIT=%s\n' "$?"
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -I -B - <<'KNET_READ_ONLY_TRAINING_SUMMARY'
import hashlib
import json
import math
import pathlib
import stat

root = pathlib.Path('/data1/home/sunyiq/kalmannet_daily_camels_per_basin_21_development_20260908')
run = root / 'runs/DAILY_CAMELS_KNET_PER_BASIN_21_DEVELOPMENT_V2_20260908_BASIN_08190500_A40_TRAIN1_SEQ91'
expected = {
    'preflight': run / 'preflight.json',
    'history': run / 'epoch_history.json',
    'result': run / 'result_summary.json',
    'manifest': run / 'manifest.sha256.json',
    'completion': run / 'completion.marker.json',
}

def safe_regular(path):
    if not path.is_relative_to(root) or '..' in path.parts:
        raise ValueError('foreign path')
    info = path.lstat()
    if not stat.S_ISREG(info.st_mode) or stat.S_ISLNK(info.st_mode):
        raise ValueError('unsafe file: ' + str(path))
    for ancestor in path.parents:
        parent = ancestor.lstat()
        if not stat.S_ISDIR(parent.st_mode) or stat.S_ISLNK(parent.st_mode):
            raise ValueError('unsafe ancestor: ' + str(ancestor))
        if ancestor == root:
            break
    if path.resolve(strict=True) != path:
        raise ValueError('noncanonical file: ' + str(path))
    return info

def read_json(path, maximum):
    info = safe_regular(path)
    if info.st_size > maximum:
        raise ValueError('metadata exceeds bounded read: ' + str(path))
    with path.open('rb') as handle:
        before = os_fstat = __import__('os').fstat(handle.fileno())
        raw = handle.read(maximum + 1)
        after = __import__('os').fstat(handle.fileno())
    if (before.st_size, before.st_mtime_ns) != (after.st_size, after.st_mtime_ns):
        raise RuntimeError('metadata changed during read: ' + str(path))
    if len(raw) != after.st_size or len(raw) > maximum:
        raise RuntimeError('bounded metadata read differs: ' + str(path))
    return json.loads(raw), {
        'bytes': len(raw),
        'sha256': hashlib.sha256(raw).hexdigest(),
    }

preflight, preflight_file = read_json(expected['preflight'], 65536)
history, history_file = read_json(expected['history'], 400000)
result, result_file = read_json(expected['result'], 400000)
manifest, manifest_file = read_json(expected['manifest'], 400000)
completion, completion_file = read_json(expected['completion'], 65536)
if not isinstance(history, list) or not history:
    raise ValueError('epoch history is not a non-empty list')

def finite(value):
    return type(value) in (int, float) and math.isfinite(float(value))

post = history[1:]
training_values = [row.get('training_objective') for row in post]
gradient_values = [row.get('gradient_norm_before_clip') for row in post]
checkpoint_values = [row.get('checkpoint_objective_728') for row in history]
parameters = [row.get('parameter_sha256') for row in history]
best_epoch = result.get('best_epoch')
if type(best_epoch) is not int or not 0 <= best_epoch < len(history):
    raise ValueError('best epoch is outside history')
families = {
    label: payload.get('experiment_family')
    for label, payload in (
        ('preflight', preflight), ('result', result),
        ('manifest', manifest), ('completion', completion),
    )
}
identities = {
    label: {
        key: payload.get(key)
        for key in ('experiment_family', 'experiment_id', 'execution_id', 'basin_id', 'state_dimension', 'configuration_sha256')
    }
    for label, payload in (
        ('preflight', preflight), ('result', result),
        ('manifest', manifest), ('completion', completion),
    )
}
summary = {
    'schema_version': 'daily_camels_knet_job224875_read_only_summary_v1',
    'files': {
        'preflight.json': preflight_file,
        'epoch_history.json': history_file,
        'result_summary.json': result_file,
        'manifest.sha256.json': manifest_file,
        'completion.marker.json': completion_file,
    },
    'history': {
        'row_count': len(history),
        'epochs_exact_0_through_80': [row.get('epoch') for row in history] == list(range(81)),
        'optimizer_steps_exact_0_through_80': [row.get('optimizer_steps') for row in history] == list(range(81)),
        'all_post_zero_training_objectives_finite': all(finite(value) for value in training_values),
        'training_objective_first': training_values[0] if training_values else None,
        'training_objective_last': training_values[-1] if training_values else None,
        'training_objective_minimum': min(training_values) if training_values and all(finite(value) for value in training_values) else None,
        'all_post_zero_gradient_norms_finite': all(finite(value) for value in gradient_values),
        'all_post_zero_gradient_norms_positive': all(finite(value) and float(value) > 0.0 for value in gradient_values),
        'gradient_norm_first': gradient_values[0] if gradient_values else None,
        'gradient_norm_last': gradient_values[-1] if gradient_values else None,
        'all_post_zero_nonzero_gradient_name_lists_nonempty': all(isinstance(row.get('nonzero_gradient_parameter_names'), list) and bool(row.get('nonzero_gradient_parameter_names')) for row in post),
        'all_checkpoint_objectives_finite': all(finite(value) for value in checkpoint_values),
        'epoch_zero_checkpoint_objective': checkpoint_values[0],
        'best_epoch': best_epoch,
        'best_checkpoint_objective': checkpoint_values[best_epoch],
        'last_checkpoint_objective': checkpoint_values[-1],
        'unique_parameter_sha256_count': len(set(parameters)),
        'epoch_zero_parameter_sha256': parameters[0],
        'best_parameter_sha256': parameters[best_epoch],
        'last_parameter_sha256': parameters[-1],
        'parameter_changed_by_first_update': len(parameters) > 1 and parameters[1] != parameters[0],
        'best_parameter_differs_from_epoch_zero': parameters[best_epoch] != parameters[0],
        'last_parameter_differs_from_epoch_zero': parameters[-1] != parameters[0],
    },
    'result': {
        key: result.get(key)
        for key in (
            'terminal_state', 'technical_success', 'scientific_capability_passed',
            'scientific_capability_status', 'relative_accuracy_status', 'convergence_status',
            'optimizer_steps', 'training_forecast_error_events', 'best_epoch',
            'epoch_zero_checkpoint_objective_728', 'best_checkpoint_objective_728',
            'last_checkpoint_objective_728', 'formal_evaluation_access_count',
            'scientific_gate_evidence', 'kalmannet_minus_unscented_kalman_filter_nse_by_lead',
            'kalmannet_minus_unscented_kalman_filter_mean_nse',
        )
    },
    'completion': {
        key: completion.get(key)
        for key in (
            'terminal_state', 'technical_success', 'scientific_capability_passed',
            'scientific_capability_status', 'relative_accuracy_status', 'convergence_status',
            'optimizer_steps', 'completed_epoch', 'last_checkpoint_epoch',
            'best_epoch', 'formal_evaluation_access_count',
        )
    },
    'identity': {
        'experiment_family_by_file': families,
        'fields_by_file': identities,
        'only_preflight_omits_experiment_family': families['preflight'] is None and len({families['result'], families['manifest'], families['completion']}) == 1 and families['result'] is not None,
    },
    'read_scope': {
        'submissions': 0,
        'checkpoints_read': 0,
        'prediction_arrays_read': 0,
        'formal_evaluation_read': 0,
    },
}
print(json.dumps(summary, sort_keys=True, separators=(',', ':')), flush=True)
print('READ_ONLY_TRAINING_SUMMARY_COMPLETE submissions=0 checkpoints_read=0 prediction_arrays_read=0 formal_evaluation_read=0', flush=True)
KNET_READ_ONLY_TRAINING_SUMMARY
