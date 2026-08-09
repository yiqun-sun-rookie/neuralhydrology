#!/usr/bin/env bash
set -eo pipefail

TARGET=/data1/home/sunyiq/kalmannet_tukf06_20260809/retry2
SOURCE="$TARGET/source"
OUTPUT="$TARGET/results/tukf06_full_diagonal_search_head_to_head_v1"
MAILBOX=/data1/home/sunyiq/hpc_mailbox
AUDIT_DIR="$TARGET/audit"
EVALUATION_JOB=202156
SELECTION_MANIFEST_SHA=63160e786c2b6b07bbb144766deda8bdc29c86d889dbeb8a0f81d468623bc8c3
SELECTION_SEAL_SHA=9151f439e110a679802739eadd7a21857ab396e824ce3c4ea01052b6c611e35a
EVALUATION_SUMMARY_SHA=f053e8f9af10ec82e4005ed113e7d987bf4a9f09399383b4411e3d55a9720a9d
EVALUATION_MANIFEST_SHA=50fbdc6c44efa9e055f1ebd8772c992bb98dc9ca77a854d676954cd39f609965

if [[ -z "${SLURM_JOB_ID:-}" ]]; then
  state=$(sacct -j "$EVALUATION_JOB" -X -n -o State | awk 'NF {print $1; exit}')
  exit_code=$(sacct -j "$EVALUATION_JOB" -X -n -o ExitCode | awk 'NF {print $1; exit}')
  if [[ "$state" != "COMPLETED" || "$exit_code" != "0:0" ]]; then
    echo "evaluation accounting gate failed: state=$state exit_code=$exit_code" >&2
    exit 121
  fi
  test ! -e "$OUTPUT/evaluation_failed.json"
  test -f "$TARGET/logs/evaluation-${EVALUATION_JOB}.out"
  test -f "$TARGET/logs/evaluation-${EVALUATION_JOB}.err"
  test ! -s "$TARGET/logs/evaluation-${EVALUATION_JOB}.err"
  grep -F 'EVALUATION_COMPLETE verdict=' "$TARGET/logs/evaluation-${EVALUATION_JOB}.out"
  test "$(sha256sum "$OUTPUT/selection_manifest.sha256.json" | awk '{print $1}')" = "$SELECTION_MANIFEST_SHA"
  test "$(sha256sum "$OUTPUT/selection.sealed.json" | awk '{print $1}')" = "$SELECTION_SEAL_SHA"
  test "$(sha256sum "$OUTPUT/evaluation_summary.json" | awk '{print $1}')" = "$EVALUATION_SUMMARY_SHA"
  test "$(sha256sum "$OUTPUT/evaluation_manifest.sha256.json" | awk '{print $1}')" = "$EVALUATION_MANIFEST_SHA"
  existing=$(squeue -h -u "$USER" -n tukf06-eval-audit -o '%i %T' | head -n 1)
  if [[ -n "$existing" ]]; then
    echo "a TUKF06 evaluation-audit job already exists: $existing" >&2
    exit 122
  fi
  mkdir -p "$AUDIT_DIR"
  audit_job=$(sbatch --parsable \
    -J tukf06-eval-audit \
    -p hcpu48 \
    -N 1 \
    -n 1 \
    --cpus-per-task=48 \
    -t 00:20:00 \
    -o "$AUDIT_DIR/evaluation-audit-%j.out" \
    -e "$AUDIT_DIR/evaluation-audit-%j.err" \
    --wrap="/bin/bash -lc 'source /data1/home/sunyiq/miniconda3/etc/profile.d/conda.sh; conda activate nh_final; export OMP_NUM_THREADS=1 MKL_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 NUMEXPR_NUM_THREADS=1; bash $MAILBOX/inbox/kalmannet-tukf06/cmd.sh'")
  audit_job=${audit_job%%;*}
  echo "evaluation_audit_job_id=$audit_job"
  for _ in $(seq 1 120); do
    audit_state=$(sacct -j "$audit_job" -X -n -o State | awk 'NF {print $1; exit}')
    case "$audit_state" in
      COMPLETED|FAILED|CANCELLED|TIMEOUT|OUT_OF_MEMORY|NODE_FAIL|PREEMPTED) break ;;
    esac
    sleep 10
  done
  sacct -j "$audit_job" --format=JobID%18,JobName%20,Partition%10,NodeList%12,State%18,ExitCode%8,Elapsed%10,TotalCPU%12,MaxRSS%12
  audit_state=$(sacct -j "$audit_job" -X -n -o State | awk 'NF {print $1; exit}')
  audit_exit=$(sacct -j "$audit_job" -X -n -o ExitCode | awk 'NF {print $1; exit}')
  audit_stdout="$AUDIT_DIR/evaluation-audit-${audit_job}.out"
  audit_stderr="$AUDIT_DIR/evaluation-audit-${audit_job}.err"
  test -f "$audit_stdout" -a -f "$audit_stderr"
  echo "=== SCHEDULED EVALUATION AUDIT STDOUT ==="
  cat "$audit_stdout"
  echo "=== SCHEDULED EVALUATION AUDIT STDERR ==="
  cat "$audit_stderr"
  if [[ "$audit_state" != "COMPLETED" || "$audit_exit" != "0:0" ]]; then
    echo "scheduled evaluation audit failed: state=$audit_state exit_code=$audit_exit" >&2
    exit 123
  fi
  if [[ -s "$audit_stderr" ]]; then
    echo "scheduled evaluation audit stderr is nonempty" >&2
    exit 124
  fi
  grep -F 'TUKF06_EVALUATION_READ_ONLY_AUDIT_PASS' "$audit_stdout"
  echo "=== DEDICATED ARTIFACT SIZES ==="
  du -sb "$OUTPUT" "$TARGET/logs" "$TARGET/audit" "$TARGET/smoke" 2>/dev/null || true
  echo "TUKF06_SCHEDULED_EVALUATION_AUDIT_PASS job_id=$audit_job"
  exit 0
fi

python - "$SOURCE" "$OUTPUT" "$SELECTION_MANIFEST_SHA" "$EVALUATION_MANIFEST_SHA" <<'PY'
import hashlib
import json
import math
import pathlib
import sys

import numpy as np

source = pathlib.Path(sys.argv[1]).resolve()
root = pathlib.Path(sys.argv[2]).resolve()
expected_selection_sha = sys.argv[3]
expected_evaluation_manifest_sha = sys.argv[4]

basins_config = json.loads((source / 'configs/tukf06_full_diagonal_search_head_to_head_v1.json').read_text(encoding='utf-8'))
basins = basins_config['basins']
assert len(basins) == len(set(basins)) == 21
leads = (1, 2, 3)
systems = (
    'same_forcing_open_loop',
    'default_noise_filter',
    'sampling_search_filter',
    'backpropagation_filter',
    'persistence',
    'second_order_autoregression',
)
filters = ('default_noise_filter', 'sampling_search_filter', 'backpropagation_filter')

def sha_file(path):
    digest = hashlib.sha256()
    with pathlib.Path(path).open('rb') as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b''):
            digest.update(block)
    return digest.hexdigest()

def load_npz(path):
    with np.load(path, allow_pickle=False) as archive:
        return {name: archive[name] for name in archive.files}

def sha_arrays(arrays):
    digest = hashlib.sha256()
    for name in sorted(arrays):
        array = np.ascontiguousarray(np.asarray(arrays[name]))
        digest.update(name.encode('utf-8'))
        digest.update(str(array.dtype).encode('ascii'))
        digest.update(np.asarray(array.shape, dtype=np.int64).tobytes())
        digest.update(array.tobytes())
    return digest.hexdigest()

def require_json_finite(value, where='root'):
    if isinstance(value, dict):
        for key, item in value.items():
            require_json_finite(item, f'{where}.{key}')
    elif isinstance(value, list):
        for index, item in enumerate(value):
            require_json_finite(item, f'{where}[{index}]')
    elif isinstance(value, (int, float)) and not isinstance(value, bool):
        assert math.isfinite(float(value)), f'non-finite JSON value at {where}'

def close(actual, expected, where, tolerance=2e-12):
    assert math.isclose(float(actual), float(expected), rel_tol=0.0, abs_tol=tolerance), (
        where, actual, expected)

selection_manifest_path = root / 'selection_manifest.sha256.json'
selection_seal_path = root / 'selection.sealed.json'
evaluation_manifest_path = root / 'evaluation_manifest.sha256.json'
summary_path = root / 'evaluation_summary.json'
assert sha_file(selection_manifest_path) == expected_selection_sha
assert sha_file(evaluation_manifest_path) == expected_evaluation_manifest_sha
assert not (root / 'evaluation_failed.json').exists()

seal = json.loads(selection_seal_path.read_text(encoding='utf-8'))
evaluation_manifest = json.loads(evaluation_manifest_path.read_text(encoding='utf-8'))
summary = json.loads(summary_path.read_text(encoding='utf-8'))
require_json_finite(evaluation_manifest, 'evaluation_manifest')
require_json_finite(summary, 'evaluation_summary')
assert seal['selection_manifest_sha256'] == expected_selection_sha
assert seal['evaluation_period_read'] is False
assert evaluation_manifest['status'] == 'EVALUATION_COMPLETE'
assert evaluation_manifest['evaluation_role'] == 'reused_historical_benchmark'
assert evaluation_manifest['selection_manifest_sha256'] == expected_selection_sha
assert summary['status'] == 'EVALUATION_COMPLETE'
assert summary['evaluation_role'] == 'reused_historical_benchmark'
assert summary['basin_count'] == 21
assert summary['selection_manifest_sha256'] == expected_selection_sha
assert summary['execution']['slurm_job_id'] == '202156'
assert 1 <= int(summary['execution']['worker_count']) <= 21

source_manifest = json.loads((root / 'source_manifest.json').read_text(encoding='utf-8'))
assert evaluation_manifest['source_sha256'] == source_manifest
for relative, expected in source_manifest.items():
    assert sha_file(source / relative) == expected, f'source hash mismatch: {relative}'

expected_files = {'evaluation_summary.json'}
for basin in basins:
    expected_files.add(f'evaluation/basin_{basin}.json')
    expected_files.add(f'evaluation/basin_{basin}.npz')
assert set(evaluation_manifest['files']) == expected_files
for relative, expected in evaluation_manifest['files'].items():
    path = root / relative
    assert path.is_file(), f'missing evaluation member: {relative}'
    assert sha_file(path) == expected, f'evaluation member hash mismatch: {relative}'

records = []
structural_nan_count = 0
for index, basin in enumerate(basins):
    record_path = root / 'evaluation' / f'basin_{basin}.json'
    archive_path = root / 'evaluation' / f'basin_{basin}.npz'
    record = json.loads(record_path.read_text(encoding='utf-8'))
    require_json_finite(record, basin)
    assert record == summary['basins'][index]
    assert record['experiment_id'] == summary['experiment_id']
    assert record['basin_id'] == basin
    assert record['evaluation_role'] == 'reused_historical_benchmark'
    arrays = load_npz(archive_path)
    assert record['archive_sha256'] == sha_arrays(arrays)
    expected_arrays = {'dates_ns', 'target', 'forcing'}
    expected_arrays.update(f'common_mask_lead_{lead}' for lead in leads)
    expected_arrays.update(f'{system}_lead_{lead}' for system in systems for lead in leads)
    assert set(arrays) == expected_arrays
    target = np.asarray(arrays['target'], dtype=np.float64)
    dates = np.asarray(arrays['dates_ns'], dtype=np.int64)
    forcing = np.asarray(arrays['forcing'], dtype=np.float64)
    assert target.ndim == dates.ndim == 1
    assert len(target) == len(dates) >= 3650
    assert forcing.ndim == 2 and forcing.shape[0] == len(target)
    assert np.isfinite(forcing).all()
    assert not np.isinf(target).any()
    assert np.all(np.diff(dates) == 86400 * 10**9)
    for lead in leads:
        predictions = {
            system: np.asarray(arrays[f'{system}_lead_{lead}'], dtype=np.float64)
            for system in systems
        }
        for system, prediction in predictions.items():
            assert prediction.shape == target.shape, (basin, lead, system, prediction.shape)
            assert not np.isinf(prediction).any(), (basin, lead, system)
            structural_nan_count += int(np.isnan(prediction).sum())
        stored_mask = np.asarray(arrays[f'common_mask_lead_{lead}'])
        assert stored_mask.dtype == np.bool_ and stored_mask.shape == target.shape
        expected_mask = np.isfinite(target)
        for prediction in predictions.values():
            expected_mask &= np.isfinite(prediction)
        expected_mask[:365] = False
        np.testing.assert_array_equal(stored_mask, expected_mask)
        assert int(stored_mask.sum()) == int(record['common_count_by_lead'][str(lead)])
        variance = float(np.var(target[stored_mask], ddof=0))
        assert variance > 0.0 and math.isfinite(variance)
        recomputed_scores = {}
        for system, prediction in predictions.items():
            error = prediction[stored_mask] - target[stored_mask]
            score = 1.0 - float(np.mean(error ** 2)) / variance
            assert math.isfinite(score)
            close(record['nse_by_system_and_lead'][system][str(lead)], score,
                  f'{basin}:{lead}:{system}')
            recomputed_scores[system] = score
        for method in filters:
            gain = recomputed_scores[method] - recomputed_scores['same_forcing_open_loop']
            close(record['gain_vs_same_forcing_open_loop'][method][str(lead)], gain,
                  f'{basin}:{lead}:{method}:gain')
        paired = (
            record['gain_vs_same_forcing_open_loop']['backpropagation_filter'][str(lead)]
            - record['gain_vs_same_forcing_open_loop']['sampling_search_filter'][str(lead)]
        )
        close(record['paired_backpropagation_minus_sampling_by_lead'][str(lead)], paired,
              f'{basin}:{lead}:paired')
    paired_mean = float(np.mean([
        record['paired_backpropagation_minus_sampling_by_lead'][str(lead)]
        for lead in leads
    ]))
    close(record['paired_backpropagation_minus_sampling_mean'], paired_mean,
          f'{basin}:paired_mean')
    records.append(record)

for lead in leads:
    key = str(lead)
    for system in systems:
        expected = float(np.median([row['nse_by_system_and_lead'][system][key] for row in records]))
        close(summary['median_whole_system_nse'][system][key], expected,
              f'summary:{lead}:{system}:median_nse')
    for method in filters:
        gains = np.asarray([row['gain_vs_same_forcing_open_loop'][method][key] for row in records])
        close(summary['median_filter_gain_vs_same_forcing_open_loop'][method][key],
              float(np.median(gains)), f'summary:{lead}:{method}:median_gain')
        assert summary['negative_gain_basin_count'][method][key] == int(np.sum(gains < 0.0))
        persistence_wins = sum(
            row['nse_by_system_and_lead'][method][key]
            > row['nse_by_system_and_lead']['persistence'][key] for row in records)
        autoregression_wins = sum(
            row['nse_by_system_and_lead'][method][key]
            > row['nse_by_system_and_lead']['second_order_autoregression'][key]
            for row in records)
        assert summary['wins_over_persistence_basin_count'][method][key] == persistence_wins
        assert summary['wins_over_second_order_autoregression_basin_count'][method][key] == autoregression_wins

for method in filters:
    catastrophic = sum(
        row['gain_vs_same_forcing_open_loop'][method]['1'] < -0.10 for row in records)
    assert summary['catastrophic_lead1_basin_count'][method] == catastrophic

paired_means = np.asarray([row['paired_backpropagation_minus_sampling_mean'] for row in records])
paired_median = float(np.median(paired_means))
paired_summary = summary['paired_backpropagation_minus_sampling']
close(paired_summary['median_of_three_lead_basin_means'], paired_median, 'paired_median')
for lead in leads:
    expected = float(np.median([
        row['paired_backpropagation_minus_sampling_by_lead'][str(lead)] for row in records]))
    close(paired_summary['median_by_lead'][str(lead)], expected, f'paired_median_lead_{lead}')
tolerance = float(paired_summary['practical_equivalence_tolerance'])
expected_verdict = (
    'BACKPROPAGATION_ADVANTAGE' if paired_median >= tolerance else
    'SAMPLING_SEARCH_ADVANTAGE' if paired_median <= -tolerance else
    'NO_DISCERNIBLE_ADVANTAGE'
)
assert paired_summary['verdict'] == expected_verdict

bootstrap = basins_config['bootstrap']
rng = np.random.default_rng(int(bootstrap['seed']))
indices = rng.integers(0, len(paired_means), size=(int(bootstrap['paired_resamples']), len(paired_means)))
medians = np.median(paired_means[indices], axis=1)
alpha = (1.0 - float(bootstrap['interval'])) / 2.0
expected_interval = [float(np.quantile(medians, alpha)), float(np.quantile(medians, 1.0 - alpha))]
np.testing.assert_allclose(
    paired_summary['bootstrap_95_percent_interval'], expected_interval, rtol=0.0, atol=2e-12)

payload = {
    'status': 'EVALUATION_AUDIT_PASS',
    'experiment_id': summary['experiment_id'],
    'evaluation_role': summary['evaluation_role'],
    'basin_count': len(records),
    'evaluation_manifest_member_count': len(evaluation_manifest['files']),
    'selection_manifest_sha256': expected_selection_sha,
    'evaluation_manifest_sha256': expected_evaluation_manifest_sha,
    'evaluation_summary_sha256': sha_file(summary_path),
    'finite_on_every_common_scoring_index': True,
    'structural_nan_count_outside_common_masks': structural_nan_count,
    'paired_median_backpropagation_minus_sampling': paired_median,
    'practical_equivalence_tolerance': tolerance,
    'verdict': expected_verdict,
    'bootstrap_95_percent_interval': expected_interval,
    'evaluation_wall_seconds': float(summary['wall_seconds']),
    'worker_count': int(summary['execution']['worker_count']),
    'median_filter_gain_vs_same_forcing_open_loop': summary['median_filter_gain_vs_same_forcing_open_loop'],
    'negative_gain_basin_count': summary['negative_gain_basin_count'],
    'catastrophic_lead1_basin_count': summary['catastrophic_lead1_basin_count'],
    'wins_over_persistence_basin_count': summary['wins_over_persistence_basin_count'],
    'wins_over_second_order_autoregression_basin_count': summary['wins_over_second_order_autoregression_basin_count'],
}
print(json.dumps(payload, indent=2, sort_keys=True))
print('TUKF06_EVALUATION_READ_ONLY_AUDIT_PASS')
PY
