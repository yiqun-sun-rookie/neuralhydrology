#!/usr/bin/env bash
set -eo pipefail

TARGET=/data1/home/sunyiq/kalmannet_tukf06_20260809/retry2
SOURCE="$TARGET/source"
OUTPUT="$TARGET/results/tukf06_full_diagonal_search_head_to_head_v1"
JID=202136
MAILBOX=/data1/home/sunyiq/hpc_mailbox
AUDIT_DIR="$TARGET/audit"

if [[ -z "${SLURM_JOB_ID:-}" ]]; then
  if [[ -e "$OUTPUT/evaluation_summary.json" || -e "$OUTPUT/evaluation" ]]; then
    echo "evaluation artifact exists before selection audit" >&2
    exit 85
  fi
  echo "=== FORMAL SELECTION ACCOUNTING ==="
  sacct -j "$JID" --format=JobID%18,JobName%20,Partition%10,NodeList%12,State%18,ExitCode%8,Elapsed%10,TotalCPU%12,MaxRSS%12
  selection_state=$(sacct -j "$JID" -X -n -o State | awk 'NF {print $1; exit}')
  selection_exit=$(sacct -j "$JID" -X -n -o ExitCode | awk 'NF {print $1; exit}')
  if [[ "$selection_state" != "COMPLETED" || "$selection_exit" != "0:0" ]]; then
    echo "selection accounting gate failed: state=$selection_state exit_code=$selection_exit" >&2
    exit 81
  fi
  existing=$(squeue -h -u "$USER" -n tukf06-audit -o '%i %T' | head -n 1)
  if [[ -n "$existing" ]]; then
    echo "a TUKF06 selection-audit job already exists: $existing" >&2
    exit 86
  fi
  mkdir -p "$AUDIT_DIR"
  audit_job=$(sbatch --parsable \
    -J tukf06-audit \
    -p hcpu48 \
    -N 1 \
    -n 1 \
    --cpus-per-task=48 \
    -t 00:20:00 \
    -o "$AUDIT_DIR/selection-audit-%j.out" \
    -e "$AUDIT_DIR/selection-audit-%j.err" \
    --wrap="/bin/bash -lc 'source /data1/home/sunyiq/miniconda3/etc/profile.d/conda.sh; conda activate nh_final; export MKL_THREADING_LAYER=GNU MKL_SERVICE_FORCE_INTEL=1 OMP_NUM_THREADS=1 MKL_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 NUMEXPR_NUM_THREADS=1; bash $MAILBOX/inbox/kalmannet-tukf06/cmd.sh'")
  audit_job=${audit_job%%;*}
  echo "selection_audit_job_id=$audit_job"
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
  audit_stdout="$AUDIT_DIR/selection-audit-${audit_job}.out"
  audit_stderr="$AUDIT_DIR/selection-audit-${audit_job}.err"
  test -f "$audit_stdout" -a -f "$audit_stderr"
  echo "=== SCHEDULED AUDIT STDOUT ==="
  cat "$audit_stdout"
  echo "=== SCHEDULED AUDIT STDERR ==="
  cat "$audit_stderr"
  if [[ "$audit_state" != "COMPLETED" || "$audit_exit" != "0:0" ]]; then
    echo "scheduled selection audit failed: state=$audit_state exit_code=$audit_exit" >&2
    exit 87
  fi
  if [[ -s "$audit_stderr" ]]; then
    echo "scheduled selection audit stderr is nonempty" >&2
    exit 88
  fi
  grep -F 'TUKF06_SELECTION_READ_ONLY_AUDIT_PASS' "$audit_stdout"
  echo "TUKF06_SCHEDULED_SELECTION_AUDIT_PASS job_id=$audit_job"
  exit 0
fi

echo "=== FORMAL SELECTION ACCOUNTING ==="
echo "selection job $JID was verified COMPLETED with exit code 0:0 on the login node before this audit was scheduled"
if [[ ! -f "$OUTPUT/selection.sealed.json" ]]; then
  echo "selection seal is absent" >&2
  exit 82
fi
if [[ -e "$OUTPUT/evaluation_summary.json" || -e "$OUTPUT/evaluation" ]]; then
  echo "evaluation artifact exists before authorization gate" >&2
  exit 83
fi

echo "=== INDEPENDENT READ-ONLY SELECTION AUDIT ==="
python - "$SOURCE" "$OUTPUT" <<'PY'
import hashlib
import json
import math
import pathlib
import sys

import numpy as np

source = pathlib.Path(sys.argv[1]).resolve()
root = pathlib.Path(sys.argv[2]).resolve()

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
        if not math.isfinite(float(value)):
            raise AssertionError(f'non-finite JSON number at {where}')

config_path = source / 'configs/tukf06_full_diagonal_search_head_to_head_v1.json'
design_path = source / 'configs/tukf06_search_design_v1.npz'
config = json.loads(config_path.read_text(encoding='utf-8'))
basins = config['basins']
dims = config['expected_state_dimensions']
assert len(basins) == len(set(basins)) == 21

seal_path = root / 'selection.sealed.json'
manifest_path = root / 'selection_manifest.sha256.json'
summary_path = root / 'selection_summary.json'
source_manifest_path = root / 'source_manifest.json'
seal = json.loads(seal_path.read_text(encoding='utf-8'))
manifest = json.loads(manifest_path.read_text(encoding='utf-8'))
summary = json.loads(summary_path.read_text(encoding='utf-8'))
source_manifest = json.loads(source_manifest_path.read_text(encoding='utf-8'))

assert seal == {
    'experiment_id': config['experiment_id'],
    'status': 'SELECTED_SEALED',
    'basin_count': 21,
    'selection_manifest_sha256': sha_file(manifest_path),
    'evaluation_period_read': False,
}
assert manifest['status'] == 'SELECTION_COMPLETE'
assert manifest['evaluation_period_read'] is False
assert manifest['contract_sha256'] == sha_file(config_path)
assert manifest['search_design_sha256'] == sha_file(design_path)
assert manifest['source_manifest_sha256'] == sha_file(source_manifest_path)
assert summary['status'] == 'SELECTION_COMPLETE'
assert summary['requested_basin_count'] == summary['basin_count'] == 21
assert summary['evaluation_period_read'] is False
assert summary['failures'] == []
assert summary['environment']['worker_count'] == 21
assert summary['environment']['slurm_job_id'] == '202136'
assert [row['basin_id'] for row in summary['basins']] == basins

for relative, expected in manifest['files'].items():
    path = root / relative
    assert path.is_file(), f'missing manifest member: {relative}'
    assert sha_file(path) == expected, f'manifest hash mismatch: {relative}'
assert set(source_manifest) == set(config['code_and_input_files_to_hash'])
for relative, expected in source_manifest.items():
    assert sha_file(source / relative) == expected, f'source hash mismatch: {relative}'

validation_differences = []
training_differences = []
sampling_exact = sampling_outer = 0
backprop_exact = backprop_outer = 0
sampling_q = []
backprop_q = []
sampling_rb = []
backprop_rb = []
start_relative_spread = []
budget_validation_differences = {str(value): [] for value in (32, 64, 128, 256)}
bound_rtol = 64.0 * np.finfo(np.float64).eps

for index, basin in enumerate(basins):
    dimension = int(dims[basin])
    json_path = root / 'selection' / f'basin_{basin}.json'
    history_path = root / 'selection' / f'basin_{basin}.npz'
    input_path = root / 'selection_inputs' / f'basin_{basin}.npz'
    record = json.loads(json_path.read_text(encoding='utf-8'))
    require_json_finite(record, basin)
    assert record == summary['basins'][index]
    assert record['experiment_id'] == config['experiment_id']
    assert record['basin_id'] == basin
    assert record['state_dimension'] == dimension
    assert record['evaluation_period_read'] is False
    assert record['contract_sha256'] == sha_file(config_path)
    assert record['source_manifest_sha256'] == sha_file(source_manifest_path)
    assert record['search_design_sha256'] == sha_file(design_path)

    histories = load_npz(history_path)
    inputs = load_npz(input_path)
    assert record['history_sha256'] == sha_arrays(histories)
    assert record['selection_input_sha256'] == sha_arrays(inputs)
    for name, array in histories.items():
        assert np.isfinite(array).all(), f'non-finite history: {basin}:{name}'
    for name, array in inputs.items():
        assert np.isfinite(array).all(), f'non-finite input: {basin}:{name}'

    expected_shapes = {
        'sampling_theta_log': (256, dimension + 1),
        'sampling_training_objective': (256,),
        'sampling_validation_objective': (256,),
        'backpropagation_theta_log': (256, dimension + 1),
        'backpropagation_training_objective': (256,),
        'backpropagation_validation_objective': (256,),
        'shared_start_theta_log': (8, dimension + 1),
    }
    assert {name: tuple(array.shape) for name, array in histories.items()} == expected_shapes
    np.testing.assert_array_equal(
        histories['sampling_theta_log'][:8], histories['shared_start_theta_log'])
    np.testing.assert_array_equal(
        histories['backpropagation_theta_log'][:8], histories['shared_start_theta_log'])

    methods = {
        'sampling_search': (0, histories['sampling_validation_objective']),
        'backpropagation': (248, histories['backpropagation_validation_objective']),
    }
    for method_name, (updates, validation_history) in methods.items():
        method = record[method_name]
        assert method['training_queries'] == 256
        assert method['validation_queries'] == 256
        assert method['filter_passes'] == 512
        assert method['gradient_updates'] == updates
        assert set(method['budget_best_indices']) == {'32', '64', '128', '256'}
        assert 0 <= method['selected_index'] < 256
        selected = method['selected']
        assert len(selected['theta_log']) == dimension + 1
        assert len(selected['q_diagonal']) == dimension
        theta_values = np.asarray(selected['theta_log'], dtype=np.float64)
        q_values = np.asarray(selected['q_diagonal'], dtype=np.float64)
        r_b_value = float(selected['r_b'])
        q_log_lower, q_log_upper = math.log(1e-5), math.log(0.1)
        r_log_lower, r_log_upper = math.log(0.0025), math.log(0.32)
        assert np.all(theta_values[:-1] >= q_log_lower - bound_rtol * abs(q_log_lower))
        assert np.all(theta_values[:-1] <= q_log_upper + bound_rtol * abs(q_log_upper))
        assert r_log_lower - bound_rtol * abs(r_log_lower) <= theta_values[-1]
        assert theta_values[-1] <= r_log_upper + bound_rtol * abs(r_log_upper)
        np.testing.assert_allclose(
            q_values, np.exp(theta_values[:-1]), rtol=bound_rtol, atol=0.0)
        assert math.isclose(
            r_b_value, math.exp(float(theta_values[-1])), rel_tol=bound_rtol, abs_tol=0.0)
        assert np.all(q_values >= 1e-5 * (1.0 - bound_rtol))
        assert np.all(q_values <= 0.1 * (1.0 + bound_rtol))
        assert 0.0025 * (1.0 - bound_rtol) <= r_b_value <= 0.32 * (1.0 + bound_rtol)
        assert selected['validation_objective'] == validation_history[method['selected_index']]

    sampling = record['sampling_search']
    backprop = record['backpropagation']
    validation_differences.append(
        backprop['selected']['validation_objective'] - sampling['selected']['validation_objective'])
    training_differences.append(
        backprop['selected']['training_objective'] - sampling['selected']['training_objective'])
    sampling_exact += int(sampling['boundary']['exact_any'])
    sampling_outer += int(sampling['boundary']['outer_five_percent_any'])
    backprop_exact += int(backprop['boundary']['exact_any'])
    backprop_outer += int(backprop['boundary']['outer_five_percent_any'])
    sampling_q.extend(sampling['selected']['q_diagonal'])
    backprop_q.extend(backprop['selected']['q_diagonal'])
    sampling_rb.append(sampling['selected']['r_b'])
    backprop_rb.append(backprop['selected']['r_b'])
    start_relative_spread.append(record['backpropagation_start_dispersion']['relative_spread'])
    for budget in ('32', '64', '128', '256'):
        si = sampling['budget_best_indices'][budget]
        bi = backprop['budget_best_indices'][budget]
        budget_validation_differences[budget].append(
            histories['backpropagation_validation_objective'][bi]
            - histories['sampling_validation_objective'][si])

validation = np.asarray(validation_differences)
training = np.asarray(training_differences)
tol = 1e-10
payload = {
    'status': 'SELECTION_AUDIT_PASS',
    'experiment_id': config['experiment_id'],
    'basin_count': 21,
    'manifest_member_count': len(manifest['files']),
    'selection_manifest_sha256': sha_file(manifest_path),
    'selection_seal_sha256': sha_file(seal_path),
    'evaluation_period_read': False,
    'evaluation_artifacts_absent': True,
    'finite_json_and_arrays': True,
    'equal_budget_per_method_per_basin': {
        'training_queries': 256,
        'validation_queries': 256,
        'filter_passes': 512,
        'backpropagation_updates': 248,
    },
    'validation_objective_backprop_minus_sampling': {
        'median': float(np.median(validation)),
        'mean': float(np.mean(validation)),
        'minimum': float(np.min(validation)),
        'maximum': float(np.max(validation)),
        'backpropagation_better_basin_count': int(np.sum(validation < -tol)),
        'sampling_better_basin_count': int(np.sum(validation > tol)),
        'tie_basin_count': int(np.sum(np.abs(validation) <= tol)),
        'per_basin': dict(zip(basins, validation.tolist())),
    },
    'training_objective_backprop_minus_sampling_median': float(np.median(training)),
    'budget_validation_difference_medians': {
        budget: float(np.median(values))
        for budget, values in budget_validation_differences.items()
    },
    'selected_boundary_basin_counts': {
        'sampling_exact_any': sampling_exact,
        'sampling_outer_five_percent_any': sampling_outer,
        'backpropagation_exact_any': backprop_exact,
        'backpropagation_outer_five_percent_any': backprop_outer,
    },
    'selected_parameter_ranges': {
        'sampling_q': [float(min(sampling_q)), float(max(sampling_q))],
        'backpropagation_q': [float(min(backprop_q)), float(max(backprop_q))],
        'sampling_r_b': [float(min(sampling_rb)), float(max(sampling_rb))],
        'backpropagation_r_b': [float(min(backprop_rb)), float(max(backprop_rb))],
    },
    'backpropagation_start_relative_spread_median': float(np.median(start_relative_spread)),
    'physical_bound_relative_tolerance': float(bound_rtol),
    'selection_wall_seconds': float(summary['wall_seconds']),
    'worker_count': int(summary['environment']['worker_count']),
}
print(json.dumps(payload, indent=2, sort_keys=True))
PY

echo "=== LOG INTEGRITY ==="
stderr="$TARGET/logs/selection-${JID}.err"
stdout="$TARGET/logs/selection-${JID}.out"
test -f "$stderr" -a -f "$stdout"
echo "selection_stderr_bytes=$(wc -c < "$stderr")"
echo "selection_stdout_sha256=$(sha256sum "$stdout" | awk '{print $1}')"
if [[ -s "$stderr" ]]; then
  echo "selection stderr is nonempty" >&2
  exit 84
fi
grep -F 'SELECTION_SEALED basins=21' "$stdout"
echo "TUKF06_SELECTION_READ_ONLY_AUDIT_PASS"
