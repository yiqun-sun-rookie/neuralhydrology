#!/bin/bash
# ID29 seq=68: array-aware health plus artifact-coordinate progress snapshot.
set -eo pipefail

JOBS=202214,202215,202216,202222,202226,202227,202228,202229,202230

echo "=== SQUEUE COUNTS BY ARRAY PARENT AND STATE ==="
squeue -h -j "$JOBS" -o '%F|%T' | sort | uniq -c

echo "=== SACCT COUNTS BY ARRAY PARENT, STATE, AND EXIT CODE ==="
sacct -n -P -j "$JOBS" --format=JobID,State,ExitCode | awk -F'|' '
  NF >= 3 && $1 !~ /\./ {
    parent = $1
    sub(/_.*/, "", parent)
    key = parent "|" $2 "|" $3
    count[key]++
  }
  END {
    for (key in count) print count[key] "|" key
  }
' | sort -t'|' -k2,2n -k3,3

echo "=== AGGREGATION DEPENDENCIES ==="
scontrol show job -o 202229 | sed -n 's/.*Dependency=\([^ ]*\).*/202229|\1/p'
scontrol show job -o 202230 | sed -n 's/.*Dependency=\([^ ]*\).*/202230|\1/p'

echo "=== REGISTERED ARTIFACT PROGRESS ==="
ROOT=/data1/home/sunyiq/nearing2022_da
source ~/miniconda3/etc/profile.d/conda.sh
conda activate nh_final
cd "$ROOT"
export PYTHONPATH="$ROOT${PYTHONPATH:+:$PYTHONPATH}"
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

registry_root = root / 'src/29_nearing2022_da_ar/registry'
training = pd.read_csv(registry_root / 'experiment_registry.csv', keep_default_na=False, dtype=str)
evaluations = pd.read_csv(registry_root / 'evaluation_registry.csv', keep_default_na=False, dtype=str)
hyper = pd.read_csv(registry_root / 'assimilation_hyperparameter_registry.csv', keep_default_na=False, dtype=str)

training_done = Counter()
training_missing = []
for _, row in training.iterrows():
    try:
        run = resolve_source_run(root, training, row['exp_id'])
        required = [run / 'config.yml', run / 'model_epoch030.pt', run / 'train_data']
        if not all(path.exists() for path in required):
            raise FileNotFoundError(required)
        training_done[row['family']] += 1
    except (FileNotFoundError, KeyError, ValueError) as exc:
        training_missing.append(f"{row['exp_id']}:{type(exc).__name__}")

evaluation_done = Counter()
evaluation_missing = []
for _, row in evaluations.iterrows():
    try:
        run = _registered_run(root, training, row)
        result = run / row['result_file']
        if not result.is_file():
            raise FileNotFoundError(result)
        evaluation_done[row['family']] += 1
    except (FileNotFoundError, KeyError, ValueError) as exc:
        evaluation_missing.append(f"{row['eval_id']}:{type(exc).__name__}")

hyper_done = 0
hyper_missing = []
for _, row in hyper.iterrows():
    run = Path(row['run_dir'])
    if not run.is_absolute():
        run = root / run
    result = run / row['result_file']
    if result.is_file():
        hyper_done += 1
    else:
        hyper_missing.append(row['eval_id'])

payload = {
    'training_complete': sum(training_done.values()),
    'training_total': len(training),
    'training_by_family': dict(sorted(training_done.items())),
    'training_missing_first': training_missing[:5],
    'evaluation_complete': sum(evaluation_done.values()),
    'evaluation_total': len(evaluations),
    'evaluation_by_family': dict(sorted(evaluation_done.items())),
    'evaluation_missing_first': evaluation_missing[:5],
    'hyperparameter_complete': hyper_done,
    'hyperparameter_total': len(hyper),
    'hyperparameter_missing_first': hyper_missing[:5],
    'evaluation_aggregation_exists': (root / 'closure_20260810/aggregation/evaluations/aggregation_summary.json').is_file(),
    'hyperparameter_aggregation_exists': (root / 'closure_20260810/aggregation/hyperparameters/selection_summary.json').is_file(),
}
print(json.dumps(payload, sort_keys=True))
PY
