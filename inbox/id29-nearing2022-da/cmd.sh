#!/bin/bash
# ID29 seq=89: read-only inventory of every comparison-register evidence path plus current Slurm/artifact health; keep candidate manifest 202293 held.
set -eo pipefail

ROOT=/data1/home/sunyiq/nearing2022_da
JOBS=202214,202215,202216,202222,202226,202227,202228,202229,202230,202238,202293,202294,202315

echo "=== SQUEUE COUNTS BY ARRAY PARENT AND STATE ==="
squeue -h -j "$JOBS" -o '%F|%T' | sort | uniq -c

echo "=== ACTIVE FAILURE STATES ==="
sacct -n -P -j "$JOBS" --format=JobID,State,ExitCode | awk -F'|' '
  $1 !~ /\./ && $2 ~ /^(FAILED|TIMEOUT|OUT_OF_MEMORY|NODE_FAIL|PREEMPTED|BOOT_FAIL|DEADLINE)/ { print }
' || true

echo "=== FINAL DEPENDENCIES AND HOLD ==="
for job in 202229 202230 202293 202294 202315; do
  scontrol show job -o "$job" | sed -n "s/.*Dependency=\([^ ]*\).*/$job|\1/p"
done
HELD_STATE=$(squeue -h -j 202293 -o '%i|%T|%r|%j')
echo "held_manifest=$HELD_STATE"
test "$HELD_STATE" = "202293|PENDING|JobHeldUser|N22-manifest"

source ~/miniconda3/etc/profile.d/conda.sh
conda activate nh_final
cd "$ROOT"
export PYTHONPATH="$ROOT${PYTHONPATH:+:$PYTHONPATH}"

echo "=== REGISTERED FULL-ROLE ARTIFACT PROGRESS ==="
python - <<'PY'
from collections import Counter
import json
from pathlib import Path
import sys

import pandas as pd

root = Path('/data1/home/sunyiq/nearing2022_da')
scripts = root / 'src/29_nearing2022_da_ar/scripts'
sys.path.insert(0, str(scripts))
from aggregate_registered_results import _registered_run
from prepare_evaluation_run import resolve_source_run
from verify_registered_closure import (
    EVALUATION_AGGREGATION_FILES,
    HYPERPARAMETER_AGGREGATION_FILES,
    _metrics_path,
)

registry_root = root / 'src/29_nearing2022_da_ar/registry'
training = pd.read_csv(registry_root / 'experiment_registry.csv', keep_default_na=False, dtype=str)
evaluations = pd.read_csv(registry_root / 'evaluation_registry.csv', keep_default_na=False, dtype=str)
hyper = pd.read_csv(registry_root / 'assimilation_hyperparameter_registry.csv', keep_default_na=False, dtype=str)


def require(paths):
    missing = [path for path in paths if not path.is_file()]
    if missing:
        raise FileNotFoundError(missing[0])


training_done = Counter()
for _, row in training.iterrows():
    try:
        run = resolve_source_run(root, training, row['exp_id'])
        require([run / 'config.yml', run / 'model_epoch030.pt', run / 'output.log', run / 'train_data/train_data_scaler.yml'])
        training_done[row['family']] += 1
    except (FileNotFoundError, KeyError, ValueError):
        pass

evaluation_done = Counter()
for _, row in evaluations.iterrows():
    try:
        run = _registered_run(root, training, row)
        result = run / row['result_file']
        reference_run = resolve_source_run(root, training, row['reference_exp_id'])
        reference_result = reference_run / 'test/model_epoch030/test_results.p'
        require([run / 'config.yml', run / 'model_epoch030.pt', run / 'output.log', result, _metrics_path(result), reference_result, _metrics_path(reference_result)])
        evaluation_done[row['family']] += 1
    except (FileNotFoundError, KeyError, ValueError):
        pass

hyper_done = 0
for _, row in hyper.iterrows():
    try:
        run = Path(row['run_dir'])
        run = run if run.is_absolute() else root / run
        result = run / row['result_file']
        reference_run = resolve_source_run(root, training, row['source_exp_id'])
        reference_result = reference_run / 'test/model_epoch030/test_results.p'
        require([run / 'config.yml', run / 'model_epoch030.pt', run / 'output.log', result, _metrics_path(result), reference_result, _metrics_path(reference_result)])
        hyper_done += 1
    except (FileNotFoundError, KeyError, ValueError):
        pass

evaluation_aggregation = root / 'closure_20260810/aggregation/evaluations'
hyper_aggregation = root / 'closure_20260810/aggregation/hyperparameters'
payload = {
    'training_complete': sum(training_done.values()),
    'training_total': len(training),
    'training_by_family': dict(sorted(training_done.items())),
    'evaluation_complete': sum(evaluation_done.values()),
    'evaluation_total': len(evaluations),
    'evaluation_by_family': dict(sorted(evaluation_done.items())),
    'hyperparameter_complete': hyper_done,
    'hyperparameter_total': len(hyper),
    'evaluation_aggregation_missing': [name for name in EVALUATION_AGGREGATION_FILES if not (evaluation_aggregation / name).is_file()],
    'hyperparameter_aggregation_missing': [name for name in HYPERPARAMETER_AGGREGATION_FILES if not (hyper_aggregation / name).is_file()],
    'final_gate_exists': (root / 'closure_20260810/aggregation/final_reproduction_gate.json').is_file(),
    'final_manifest_exists': (root / 'closure_20260810/aggregation/final_artifact_manifest.json').is_file(),
    'final_export_exists': (root / 'closure_20260810/export/nearing2022_final_closure.tar.gz').is_file(),
}
print(json.dumps(payload, sort_keys=True))
PY

echo "=== COMPARISON-REGISTER EVIDENCE PATH INVENTORY ==="
python - <<'PY'
import json
from pathlib import Path, PurePosixPath

root = Path('/data1/home/sunyiq/nearing2022_da').resolve()
register_path = root / 'results/29_nearing2022_da_ar/formal_closure/reproduction_comparison_register.json'
register = json.loads(register_path.read_text(encoding='utf-8'))
items = [item for layer in register['layers'].values() for item in layer]
evidence_paths = sorted({entry for item in items for entry in item.get('evidence', [])})
inventory = []
for relative in evidence_paths:
    pure = PurePosixPath(relative)
    if pure.is_absolute() or pure.as_posix() != relative or any(part in {'', '.', '..'} for part in pure.parts):
        inventory.append({'path': relative, 'kind': 'unsafe', 'files': 0, 'bytes': 0})
        continue
    path = (root / Path(*pure.parts)).resolve()
    try:
        path.relative_to(root)
    except ValueError:
        inventory.append({'path': relative, 'kind': 'outside_root', 'files': 0, 'bytes': 0})
        continue
    if path.is_file():
        inventory.append({'path': relative, 'kind': 'file', 'files': 1, 'bytes': path.stat().st_size})
    elif path.is_dir():
        files = [candidate for candidate in path.rglob('*') if candidate.is_file() and '__pycache__' not in candidate.parts and candidate.suffix != '.pyc']
        inventory.append({'path': relative, 'kind': 'directory', 'files': len(files), 'bytes': sum(candidate.stat().st_size for candidate in files)})
    else:
        inventory.append({'path': relative, 'kind': 'missing', 'files': 0, 'bytes': 0})

status_counts = {}
for item in items:
    status_counts[item['status']] = status_counts.get(item['status'], 0) + 1
payload = {
    'register_schema': register.get('schema'),
    'comparison_items': len(items),
    'status_counts': dict(sorted(status_counts.items())),
    'unique_evidence_paths': len(evidence_paths),
    'present_paths': sum(row['kind'] in {'file', 'directory'} for row in inventory),
    'missing_or_unsafe': [row for row in inventory if row['kind'] not in {'file', 'directory'}],
    'inventory': inventory,
}
print(json.dumps(payload, sort_keys=True))
PY
