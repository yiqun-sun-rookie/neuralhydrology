#!/bin/bash
set -euo pipefail
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -I -B - <<'ZHENJIANG_COMPLETE_SUMMARY'
import json
import math
from pathlib import Path

root = Path('/data1/home/sunyiq/zhenjiang_update_budget_20260922_001')
run = root / 'run'

def read(path, maximum=1000000):
    if path.is_symlink() or not path.is_file() or not 0 < path.stat().st_size <= maximum:
        raise ValueError('bounded result record missing: ' + str(path))
    return json.loads(path.read_bytes())

complete = read(run / 'complete.json')
result = read(run / 'result.json')
if complete.get('status') != 'complete' or result.get('status') != 'six_instances_complete':
    raise ValueError('formal completion records differ')

groups = {}
def minimum(values):
    values = list(values)
    return min(values) if values else None

for seed in (17, 29, 43):
    for stage in ('rolling_encoder', 'differentiable_filter'):
        directory = run / ('seed_' + str(seed)) / stage
        epochs = [read(directory / ('epoch_' + str(epoch) + '.json'), 16384)
                  for epoch in range(101)]
        gate = read(directory / 'epoch_20_identity.json', 16384)
        selection = read(directory / 'selection.json')
        raw_scores = [float(row['score_m']) for row in epochs]
        if not all(math.isfinite(value) and value >= 0 for value in raw_scores):
            raise ValueError('invalid raw validation score')
        earliest = min(range(101), key=lambda index: raw_scores[index])
        early = min(range(21), key=lambda index: raw_scores[index])
        if (earliest != selection['best_epoch']
                or raw_scores[earliest] != selection['best_score_m']
                or gate.get('status') != 'passed'
                or early != gate['old_best_epoch']
                or raw_scores[early] != gate['old_best_score_m']):
            raise ValueError('independent selection reconstruction differs')
        filter_training = [row['filter_training_health'] for row in epochs]
        filter_validation = [row['filter_validation_health'] for row in epochs]
        observation = [row['training'] for row in epochs[1:]]
        noise_rows = [row for row in epochs if row.get('noise') is not None]
        groups[str(seed) + '/' + stage] = {
            'epoch_count': len(epochs),
            'gate_status': gate['status'],
            'old_20_best_epoch': early,
            'old_20_best_score_m': raw_scores[early],
            'new_100_best_epoch': earliest,
            'new_100_best_score_m': raw_scores[earliest],
            'absolute_change_m': raw_scores[earliest] - raw_scores[early],
            'relative_change_percent': 100.0 * (raw_scores[earliest] / raw_scores[early] - 1.0),
            'improved_after_epoch_20': earliest > 20,
            'epoch_20_raw_score_m': raw_scores[20],
            'epoch_100_raw_score_m': raw_scores[100],
            'selected_state_sha256': selection['state_sha256'],
            'final_epoch_checkpoint': selection['final_epoch_checkpoint'],
            'training_batch_count': sum(row['batch_count'] for row in observation),
            'gradient_clipped_batch_count': sum(row['clipped_batches'] for row in observation),
            'maximum_preclip_gradient_norm': max(
                row['preclip_full_gradient_norm']['maximum'] for row in observation),
            'filter_training_clipped_samples': sum(row['clipped_samples'] for row in filter_training),
            'filter_validation_clipped_samples': sum(row['clipped_samples'] for row in filter_validation),
            'minimum_training_prior_eigenvalue': minimum(
                row['prior_minimum_eigenvalue'] for row in filter_training if row['hour_calls']),
            'minimum_training_posterior_eigenvalue': minimum(
                row['posterior_minimum_eigenvalue'] for row in filter_training if row['hour_calls']),
            'minimum_validation_prior_eigenvalue': minimum(
                row['prior_minimum_eigenvalue'] for row in filter_validation if row['hour_calls']),
            'minimum_validation_posterior_eigenvalue': minimum(
                row['posterior_minimum_eigenvalue'] for row in filter_validation if row['hour_calls']),
            'maximum_raw_noise_change_from_initial': max(
                (row['max_abs_raw_noise_change_from_initial'] for row in noise_rows), default=None),
            'peak_gpu_bytes_so_far_at_epoch_100': epochs[100]['job_peak_gpu_bytes_so_far'],
            'training_seconds_sum': sum(row['training_seconds_including_diagnostics'] for row in epochs),
            'validation_seconds_sum': sum(row['validation_seconds_including_diagnostics'] for row in epochs),
            'checkpoint_seconds_sum': sum(row['checkpoint_seconds'] for row in epochs)}

print(json.dumps({'job_id': complete['job_id'],
                  'complete_elapsed_seconds': complete['elapsed_seconds'],
                  'claim_limit': result.get('claim_limit'),
                  'statuses': result.get('statuses'),
                  'metadata_accounting_before_complete': complete.get(
                      'metadata_accounting_before_complete'),
                  'outputs': result.get('outputs'),
                  'data_reads': result.get('data_reads'),
                  'old_metadata_reads': result.get('old_metadata_reads'),
                  'old_common_reads': result.get('old_common_reads'),
                  'groups': groups}, sort_keys=True))
ZHENJIANG_COMPLETE_SUMMARY
