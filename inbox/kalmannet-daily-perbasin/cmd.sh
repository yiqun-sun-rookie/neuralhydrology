#!/bin/bash
# kalmannet-daily-perbasin sequence=99: READ-ONLY extract of the five-method comparison scores
# of job 224875 from result_summary.json (bounded, hash-checked).  No submission, no modification.
set -o pipefail
echo "channel=kalmannet-daily-perbasin sequence=99 purpose=read-only-scores-job224875"
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -I -B - <<'KDPP_READ_ONLY_SCORES'
import hashlib, json, pathlib
run = pathlib.Path('/data1/home/sunyiq/kalmannet_daily_camels_per_basin_21_development_20260908/runs/DAILY_CAMELS_KNET_PER_BASIN_21_DEVELOPMENT_V2_20260908_BASIN_08190500_A40_TRAIN1_SEQ91')
path = run / 'result_summary.json'
raw = path.read_bytes()
digest = hashlib.sha256(raw).hexdigest()
if len(raw) != 284026 or digest != '9b0358330c73bb7c44f20c89820a8bb1043523d50d6e8a73f430c146cdef45fb':
    raise SystemExit('RESULT_SUMMARY_IDENTITY_DIFFERS ' + str(len(raw)) + ' ' + digest)
result = json.loads(raw)
best = int(result['best_epoch'])
history = result['history']
extract = {
    'schema_version': 'daily_camels_knet_job224875_read_only_scores_v1',
    'result_summary_sha256': digest,
    'best_epoch': best,
    'objectives_728': {
        'epoch_zero': result.get('epoch_zero_checkpoint_objective_728'),
        'best': result.get('best_checkpoint_objective_728'),
        'last': result.get('last_checkpoint_objective_728'),
    },
    'comparisons': result.get('comparisons'),
    'kalmannet_minus_ukf_nse_by_lead': result.get('kalmannet_minus_unscented_kalman_filter_nse_by_lead'),
    'kalmannet_minus_ukf_mean_nse': result.get('kalmannet_minus_unscented_kalman_filter_mean_nse'),
    'relative_accuracy_status': result.get('relative_accuracy_status'),
    'scientific_gate_evidence': result.get('scientific_gate_evidence'),
    'scientific_capability_status': result.get('scientific_capability_status'),
    'correction_cap': result.get('correction_cap'),
    'diagnostics': result.get('diagnostics'),
    'resources': result.get('resources'),
    'best_row': {key: history[best].get(key) for key in ('epoch', 'checkpoint_objective_728', 'reporting_objective_712', 'nse_by_lead', 'mse_by_lead', 'validation_saturation_fraction', 'training_objective', 'gradient_norm_before_clip')},
    'epoch_zero_row': {key: history[0].get(key) for key in ('checkpoint_objective_728', 'reporting_objective_712', 'nse_by_lead', 'mse_by_lead')},
    'read_scope': {'files_read': 1, 'checkpoints_read': 0, 'prediction_arrays_read': 0, 'formal_evaluation_read': 0, 'submissions': 0},
}
print('SCORES_JSON_BEGIN')
print(json.dumps(extract, sort_keys=True, separators=(',', ':')))
print('SCORES_JSON_END')
print('READ_ONLY_SCORES_COMPLETE submissions=0 checkpoints_read=0 prediction_arrays_read=0 formal_evaluation_read=0')
KDPP_READ_ONLY_SCORES
