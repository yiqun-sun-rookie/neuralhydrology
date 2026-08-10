#!/bin/bash
# ID29 seq=171: extend the frozen partial numerical audit to every currently complete evaluation coordinate.
set -eo pipefail

ROOT=/data1/home/sunyiq/nearing2022_da
DIAGNOSTIC_ROOT="$ROOT/results/29_nearing2022_da_ar/formal_closure/diagnostics"
FINAL="$DIAGNOSTIC_ROOT/partial_numerical_audit_seq171.json"
TEMP="$FINAL.preparing-seq171"

test ! -e "$FINAL"
test ! -e "$TEMP"
mkdir -p "$DIAGNOSTIC_ROOT"

source ~/miniconda3/etc/profile.d/conda.sh
conda activate nh_final
cd "$ROOT"
export PYTHONPATH="$ROOT${PYTHONPATH:+:$PYTHONPATH}"

python - "$TEMP" <<'PY'
from collections import Counter
import hashlib
import json
from pathlib import Path
import sys

import pandas as pd

root = Path('/data1/home/sunyiq/nearing2022_da')
output = Path(sys.argv[1])
scripts = root / 'src/29_nearing2022_da_ar/scripts'
sys.path.insert(0, str(scripts))
from aggregate_registered_results import (  # noqa: E402
    _author_time_value,
    _read_registry,
    _registered_run,
    load_legacy_pandas_pickle,
)
from prepare_evaluation_run import resolve_source_run  # noqa: E402
from score_reproduction_matrix import METRICS, _load_pickle, score_payloads  # noqa: E402
from verify_registered_closure import _metrics_path  # noqa: E402


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


registry_root = root / 'src/29_nearing2022_da_ar/registry'
reference_root = root / 'src/29_nearing2022_da_ar/reference'
training_path = registry_root / 'experiment_registry.csv'
evaluation_path = registry_root / 'evaluation_registry.csv'
author_path = reference_root / 'author_time_split_statistics.pkl'
acceptance_path = reference_root / 'reproduction_acceptance.json'
training = _read_registry(training_path, 'exp_id')
evaluations = _read_registry(evaluation_path, 'eval_id')
author = load_legacy_pandas_pickle(author_path)
acceptance = json.loads(acceptance_path.read_text(encoding='utf-8'))
tolerances = {key: float(value) for key, value in acceptance['absolute_difference_tolerance'].items()}
systematic = {
    key: float(value) for key, value in acceptance['median_signed_difference_tolerance'].items()
}

complete = []
artifact_paths = {
    str(training_path.relative_to(root)),
    str(evaluation_path.relative_to(root)),
    str(author_path.relative_to(root)),
    str(acceptance_path.relative_to(root)),
}
for _, row in evaluations.iterrows():
    try:
        run = _registered_run(root, training, row)
        result = run / row['result_file']
        reference_run = resolve_source_run(root, training, row['reference_exp_id'])
        reference = reference_run / 'test/model_epoch030/test_results.p'
        roles = [
            run / 'config.yml',
            run / 'model_epoch030.pt',
            run / 'output.log',
            result,
            _metrics_path(result),
            reference,
            _metrics_path(reference),
        ]
        if all(path.is_file() for path in roles):
            complete.append((row, reference, result, roles))
            artifact_paths.update(str(path.relative_to(root)) for path in roles)
    except (FileNotFoundError, KeyError, ValueError):
        continue

if len(complete) < 12:
    raise ValueError(f'Expected at least the 12 coordinates verified by sequence 170, found {len(complete)}')

reference_cache = {}
details = []
coordinates = []
for row, reference_path, result_path, roles in complete:
    if reference_path not in reference_cache:
        reference_cache[reference_path] = _load_pickle(reference_path)
    reference = reference_cache[reference_path]
    scores = score_payloads(reference, _load_pickle(result_path), expected_basins=len(reference))
    if len(scores) != 531 or scores['basin'].nunique() != 531:
        raise ValueError(f"{row['eval_id']} did not score exactly 531 unique basins")
    failures = []
    metrics = {}
    maximum_absolute_difference = 0.0
    for metric in METRICS:
        reproduction = float(scores[metric].median())
        author_value = _author_time_value(author, row, metric)
        difference = reproduction - author_value
        within = abs(difference) <= tolerances[metric] + 1e-12
        metrics[metric] = {
            'reproduction': reproduction,
            'author': author_value,
            'difference': difference,
            'absolute_tolerance': tolerances[metric],
            'within_tolerance': within,
        }
        details.append({
            'eval_id': row['eval_id'],
            'family': row['family'],
            'metric': metric,
            'difference': difference,
            'within_tolerance': within,
        })
        if not within:
            failures.append(metric)
        maximum_absolute_difference = max(maximum_absolute_difference, abs(difference))
    coordinates.append({
        'eval_id': row['eval_id'],
        'family': row['family'],
        'lead': int(row['lead']),
        'train_holdout': float(row['train_holdout']) if row['train_holdout'] else None,
        'test_holdout': float(row['test_holdout']),
        'basins': len(scores),
        'metrics': metrics,
        'maximum_absolute_metric_difference': maximum_absolute_difference,
        'failed_metrics': failures,
        'result_path': str(result_path.relative_to(root)),
        'result_sha256': digest(result_path),
        'reference_path': str(reference_path.relative_to(root)),
        'reference_sha256': digest(reference_path),
        'candidate_checkpoint_sha256': digest(roles[1]),
    })

frame = pd.DataFrame(details)
metric_summaries = {}
for metric in METRICS:
    values = frame.loc[frame['metric'] == metric]
    median_difference = float(values['difference'].median())
    metric_summaries[metric] = {
        'coordinates': len(values),
        'median_signed_difference': median_difference,
        'systematic_tolerance': systematic[metric],
        'partial_within_systematic_tolerance': bool(
            abs(median_difference) <= systematic[metric] + 1e-12
        ),
        'maximum_absolute_difference': float(values['difference'].abs().max()),
        'individual_failures': int((~values['within_tolerance']).sum()),
    }

payload = {
    'schema': 'nearing2022-partial-numerical-audit-v2',
    'mailbox_sequence': 171,
    'scope': (
        'Every evaluation coordinate with all frozen registered roles present at execution; interim diagnostic only. '
        'The final numerical gate still requires all 180 evaluation and 660 hyperparameter coordinates.'
    ),
    'complete_coordinates': len(complete),
    'complete_by_family': dict(sorted(Counter(row['family'] for row, _, _, _ in complete).items())),
    'comparison_rows': len(frame),
    'individual_tolerance_failures': int((~frame['within_tolerance']).sum()),
    'coordinates_with_failures': int(sum(bool(row['failed_metrics']) for row in coordinates)),
    'metric_summaries': metric_summaries,
    'coordinates': coordinates,
    'source_artifacts': {
        path: {'sha256': digest(root / path), 'bytes': (root / path).stat().st_size}
        for path in sorted(artifact_paths)
    },
    'registered_matrix_modified': False,
    'frozen_acceptance_modified': False,
}
output.write_text(json.dumps(payload, indent=2, sort_keys=True) + '\n', encoding='utf-8')
print(json.dumps({
    'complete_coordinates': payload['complete_coordinates'],
    'complete_by_family': payload['complete_by_family'],
    'comparison_rows': payload['comparison_rows'],
    'individual_tolerance_failures': payload['individual_tolerance_failures'],
    'coordinates_with_failures': payload['coordinates_with_failures'],
    'metric_summaries': payload['metric_summaries'],
    'failed_coordinates': [
        {'eval_id': row['eval_id'], 'failed_metrics': row['failed_metrics']}
        for row in coordinates if row['failed_metrics']
    ],
}, sort_keys=True))
PY

test -f "$TEMP"
mv "$TEMP" "$FINAL"
sha256sum "$FINAL"

echo "=== SAFETY BOUNDARY ==="
test "$(squeue -h -j 202293 -o '%i|%T|%r|%j')" = '202293|PENDING|JobHeldUser|N22-manifest'
test ! -e "$ROOT/closure_20260810/aggregation/final_reproduction_gate.json"
test ! -e "$ROOT/closure_20260810/aggregation/final_reproduction_differences.csv"
echo "registered_matrix_modified=false"
